defmodule RubberDuck.LLM.Service do
  @moduledoc """
  Main LLM service that manages connections to multiple providers with
  automatic fallback, circuit breaker patterns, and rate limiting.

  ## Features

  - Multiple provider support (OpenAI, Anthropic, Local models)
  - Automatic fallback between providers
  - Circuit breaker for fault tolerance
  - Rate limiting to prevent API quota exhaustion
  - Request queuing and retry logic
  - Cost tracking per provider
  - Health monitoring

  ## Configuration

  Configure providers in your application config:

      config :rubber_duck, RubberDuck.LLM.Service,
        providers: [
          %{
            name: :openai,
            adapter: RubberDuck.LLM.Providers.OpenAI,
            api_key: System.get_env("OPENAI_API_KEY"),
            models: ["gpt-4", "gpt-4-turbo", "gpt-3.5-turbo"],
            priority: 1,
            rate_limit: {100, :minute},
            max_retries: 3
          },
          %{
            name: :anthropic,
            adapter: RubberDuck.LLM.Providers.Anthropic,
            api_key: System.get_env("ANTHROPIC_API_KEY"),
            models: ["claude-3-sonnet", "claude-3-haiku"],
            priority: 2,
            rate_limit: {50, :minute},
            max_retries: 3
          }
        ]
  """

  use GenServer
  require Logger

  alias RubberDuck.LLM.{
    Request,
    Response,
    ProviderConfig,
    ProviderState,
    CostTracker,
    HealthMonitor
  }

  @type provider_name :: atom()
  @type model_name :: String.t()
  @type request_id :: String.t()

  @type state :: %{
          providers: %{provider_name() => ProviderState.t()},
          model_mapping: %{model_name() => provider_name()},
          request_queue: :queue.queue(),
          active_requests: %{request_id() => Request.t()},
          cost_tracker: CostTracker.t(),
          health_monitor: HealthMonitor.t()
        }

  # Client API

  @doc """
  Starts the LLM service.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a completion request to the appropriate provider.

  ## Options

  - `:model` - Specific model to use (required)
  - `:messages` - List of messages (required)
  - `:temperature` - Sampling temperature (0.0 to 2.0)
  - `:max_tokens` - Maximum tokens to generate
  - `:stream` - Whether to stream the response
  - `:timeout` - Request timeout in milliseconds
  - `:priority` - Request priority (:high, :normal, :low)
  """
  @spec completion(keyword()) :: {:ok, Response.t()} | {:error, term()}
  def completion(opts) do
    GenServer.call(__MODULE__, {:completion, opts}, timeout(opts))
  end

  @doc """
  Sends an async completion request.
  Returns immediately with a request ID.
  """
  @spec completion_async(keyword()) :: {:ok, request_id()} | {:error, term()}
  def completion_async(opts) do
    GenServer.call(__MODULE__, {:completion_async, opts})
  end

  @doc """
  Gets the result of an async request.
  """
  @spec get_result(request_id(), timeout()) :: {:ok, Response.t()} | {:error, term()} | :pending
  def get_result(request_id, timeout \\ 5000) do
    GenServer.call(__MODULE__, {:get_result, request_id}, timeout)
  end

  @doc """
  Sends a streaming completion request.

  The callback function will be called for each chunk received.
  Returns a reference that can be used to track the stream.

  ## Example

      {:ok, ref} = LLM.Service.completion_stream(
        [model: "gpt-4", messages: messages],
        fn chunk ->
          IO.write(chunk.content)
        end
      )
  """
  @spec completion_stream(keyword(), function()) :: {:ok, reference()} | {:error, term()}
  def completion_stream(opts, callback) when is_function(callback, 1) do
    GenServer.call(__MODULE__, {:completion_stream, opts, callback})
  end

  @doc """
  Lists available models across all providers.
  """
  @spec list_models() :: {:ok, [%{model: String.t(), provider: atom(), available: boolean()}]}
  def list_models do
    GenServer.call(__MODULE__, :list_models)
  end

  @doc """
  Gets health status for all providers.
  """
  @spec health_status() :: {:ok, %{provider_name() => map()}}
  def health_status do
    GenServer.call(__MODULE__, :health_status)
  end

  @doc """
  Gets cost tracking information.
  """
  @spec cost_summary(keyword()) :: {:ok, map()}
  def cost_summary(opts \\ []) do
    GenServer.call(__MODULE__, {:cost_summary, opts})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = load_config(opts)

    state = %{
      providers: initialize_providers(config.providers),
      model_mapping: build_model_mapping(config.providers),
      request_queue: :queue.new(),
      active_requests: %{},
      cost_tracker: CostTracker.new(),
      health_monitor: HealthMonitor.new()
    }

    # Start health monitoring
    schedule_health_check()

    # Start queue processor
    schedule_queue_processing()

    {:ok, state}
  end

  @impl true
  def handle_call({:completion, opts}, from, state) do
    case validate_request(opts, state) do
      {:ok, request} ->
        handle_completion_request(request, from, state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:completion_async, opts}, _from, state) do
    case validate_request(opts, state) do
      {:ok, request} ->
        request_id = generate_request_id()
        request = %{request | id: request_id, async: true}

        # Queue the request
        new_queue = :queue.in(request, state.request_queue)
        new_active = Map.put(state.active_requests, request_id, request)

        new_state = %{state | request_queue: new_queue, active_requests: new_active}

        {:reply, {:ok, request_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_result, request_id}, _from, state) do
    case Map.get(state.active_requests, request_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :completed, response: response} ->
        # Remove from active requests
        new_active = Map.delete(state.active_requests, request_id)
        {:reply, {:ok, response}, %{state | active_requests: new_active}}

      %{status: :failed, error: error} ->
        # Remove from active requests
        new_active = Map.delete(state.active_requests, request_id)
        {:reply, {:error, error}, %{state | active_requests: new_active}}

      %{status: status} when status in [:pending, :processing] ->
        {:reply, :pending, state}
    end
  end

  @impl true
  def handle_call({:completion_stream, opts, callback}, from, state) do
    case validate_request(opts, state) do
      {:ok, request} ->
        # Mark request as streaming
        request = Map.put(request, :stream, true)
        request = Map.put(request, :stream_callback, callback)

        # For now, use mock provider for streaming
        _provider_name = if request.model == "mock-fast", do: :mock, else: request.provider

        case get_provider_for_request(request, state) do
          {:ok, provider_name, provider_state} ->
            # Start streaming in a separate process
            ref = make_ref()
            parent = self()

            spawn_link(fn ->
              result = handle_streaming_request(request, provider_name, provider_state, callback)
              send(parent, {:stream_complete, ref, from, result})
            end)

            {:reply, {:ok, ref}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_models, _from, state) do
    models =
      for {model, provider_name} <- state.model_mapping do
        provider_state = Map.get(state.providers, provider_name)

        %{
          model: model,
          provider: provider_name,
          available: provider_state.circuit_state == :closed
        }
      end

    {:reply, {:ok, models}, state}
  end

  @impl true
  def handle_call(:health_status, _from, state) do
    health = HealthMonitor.get_all_status(state.health_monitor)
    {:reply, {:ok, health}, state}
  end

  @impl true
  def handle_call({:cost_summary, opts}, _from, state) do
    summary = CostTracker.get_summary(state.cost_tracker, opts)
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_info(:process_queue, state) do
    new_state = process_request_queue(state)
    schedule_queue_processing()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_checks(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:request_complete, request_id, result}, state) do
    new_state = handle_request_completion(request_id, result, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:stream_complete, ref, from, _result}, state) do
    # Notify the original caller that streaming is complete
    send(elem(from, 0), {:stream_complete, ref})
    {:noreply, state}
  end

  # Private Functions

  defp load_config(opts) do
    app_config = Application.get_env(:rubber_duck, __MODULE__, [])

    config = Keyword.merge(app_config, opts)

    %{
      providers: Keyword.get(config, :providers, []),
      queue_check_interval: Keyword.get(config, :queue_check_interval, 100),
      health_check_interval: Keyword.get(config, :health_check_interval, 30_000),
      default_timeout: Keyword.get(config, :default_timeout, 30_000)
    }
  end

  defp initialize_providers(provider_configs) do
    Map.new(provider_configs, fn config ->
      provider_state = %ProviderState{
        config: struct(ProviderConfig, config),
        circuit_state: :closed,
        circuit_failures: 0,
        rate_limiter: initialize_rate_limiter(config),
        last_health_check: DateTime.utc_now(),
        health_status: :unknown,
        active_requests: 0
      }

      {config.name, provider_state}
    end)
  end

  defp initialize_rate_limiter(config) do
    case config[:rate_limit] do
      {limit, unit} ->
        # Initialize rate limiter using ex_rated
        bucket_name = "llm_provider_#{config.name}"
        ExRated.delete_bucket(bucket_name)

        scale_ms =
          case unit do
            :second -> 1_000
            :minute -> 60_000
            :hour -> 3_600_000
          end

        %{
          bucket: bucket_name,
          limit: limit,
          scale_ms: scale_ms
        }

      nil ->
        nil
    end
  end

  defp build_model_mapping(provider_configs) do
    Enum.reduce(provider_configs, %{}, fn config, acc ->
      models = Map.get(config, :models, [])

      Map.merge(
        acc,
        Map.new(models, fn model ->
          {model, config.name}
        end)
      )
    end)
  end

  defp validate_request(opts, state) do
    with {:ok, model} <- validate_model(opts[:model], state),
         {:ok, messages} <- validate_messages(opts[:messages]),
         {:ok, validated_opts} <- validate_options(opts) do
      provider_name = Map.get(state.model_mapping, model)

      request = %Request{
        id: nil,
        model: model,
        provider: provider_name,
        messages: messages,
        options: validated_opts,
        timestamp: DateTime.utc_now(),
        status: :pending,
        retries: 0
      }

      {:ok, request}
    end
  end

  defp validate_model(nil, _state), do: {:error, :model_required}

  defp validate_model(model, state) do
    if Map.has_key?(state.model_mapping, model) do
      {:ok, model}
    else
      {:error, {:unknown_model, model}}
    end
  end

  defp validate_messages(nil), do: {:error, :messages_required}
  defp validate_messages([]), do: {:error, :messages_empty}
  defp validate_messages(messages) when is_list(messages), do: {:ok, messages}
  defp validate_messages(_), do: {:error, :invalid_messages}

  defp validate_options(opts) do
    validated = %{
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens),
      stream: Keyword.get(opts, :stream, false),
      timeout: Keyword.get(opts, :timeout, 30_000),
      priority: Keyword.get(opts, :priority, :normal)
    }

    {:ok, validated}
  end

  defp handle_completion_request(request, from, state) do
    provider_state = Map.get(state.providers, request.provider)

    # Check connection status via ConnectionManager
    provider_connected = check_provider_connection(request.provider)

    cond do
      # Check if provider is connected
      not provider_connected ->
        # Try fallback provider
        case find_fallback_provider(request, state) do
          {:ok, fallback_provider} ->
            request = %{request | provider: fallback_provider}
            handle_completion_request(request, from, state)

          :error ->
            {:reply, {:error, :provider_not_connected}, state}
        end

      # Check circuit breaker
      provider_state.circuit_state == :open ->
        # Try fallback provider
        case find_fallback_provider(request, state) do
          {:ok, fallback_provider} ->
            request = %{request | provider: fallback_provider}
            handle_completion_request(request, from, state)

          :error ->
            {:reply, {:error, :all_providers_unavailable}, state}
        end

      # Check rate limit
      not check_rate_limit(provider_state) ->
        # Queue the request
        request_with_from = %{request | from: from}
        new_queue = :queue.in(request_with_from, state.request_queue)
        {:noreply, %{state | request_queue: new_queue}}

      # Process immediately
      true ->
        # Generate request ID if not present
        request_id = request.id || generate_request_id()
        request_with_id = %{request | id: request_id, from: from}

        Task.start(fn ->
          result = execute_request(request_with_id, provider_state, state)
          send(self(), {:request_complete, request_id, result})
        end)

        # Update provider state
        new_provider_state = %{provider_state | active_requests: provider_state.active_requests + 1}
        new_providers = Map.put(state.providers, request.provider, new_provider_state)

        # Store active request
        new_active = Map.put(state.active_requests, request_id, request_with_id)

        # Notify ConnectionManager of usage
        notify_connection_usage(request.provider)

        {:noreply, %{state | providers: new_providers, active_requests: new_active}}
    end
  end

  defp find_fallback_provider(request, state) do
    # Find providers that support this model and are available
    state.providers
    |> Enum.filter(fn {name, provider_state} ->
      name != request.provider &&
        provider_state.circuit_state == :closed &&
        request.model in provider_state.config.models &&
        check_provider_connection(name)
    end)
    |> Enum.sort_by(fn {_name, provider_state} ->
      provider_state.config.priority
    end)
    |> Enum.map(fn {name, _} -> name end)
    |> List.first()
    |> case do
      nil -> :error
      provider -> {:ok, provider}
    end
  end

  defp check_rate_limit(%{rate_limiter: nil}), do: true

  defp check_rate_limit(%{rate_limiter: rate_limiter}) do
    case ExRated.check_rate(rate_limiter.bucket, rate_limiter.scale_ms, rate_limiter.limit) do
      {:ok, _count} -> true
      {:error, _limit} -> false
    end
  end

  defp execute_request(request, provider_state, _state) do
    adapter = provider_state.config.adapter

    try do
      # Execute with retry logic
      execute_with_retry(request, adapter, provider_state.config)
    rescue
      error ->
        Logger.error("LLM request failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp execute_with_retry(request, adapter, config, attempt \\ 1) do
    case adapter.execute(request, config) do
      {:ok, response} ->
        {:ok, response}

      {:error, _reason} when attempt < config.max_retries ->
        # Exponential backoff
        delay = (:math.pow(2, attempt) * 1000) |> round()
        Process.sleep(delay)

        execute_with_retry(request, adapter, config, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_request_queue(state) do
    case :queue.out(state.request_queue) do
      {{:value, request}, new_queue} ->
        # Try to process the request
        case can_process_request?(request, state) do
          true ->
            # Process the request
            handle_completion_request(request, request.from, %{state | request_queue: new_queue})

          false ->
            # Put it back in the queue
            state
        end

      {:empty, _queue} ->
        state
    end
  end

  defp can_process_request?(request, state) do
    provider_state = Map.get(state.providers, request.provider)

    provider_state.circuit_state == :closed && check_rate_limit(provider_state)
  end

  defp perform_health_checks(state) do
    # Update health status for each provider
    new_providers =
      Map.new(state.providers, fn {name, provider_state} ->
        new_health = check_provider_health(provider_state)

        # Update circuit breaker state based on health
        new_circuit_state = update_circuit_state(provider_state, new_health)

        updated_state = %{
          provider_state
          | health_status: new_health,
            circuit_state: new_circuit_state,
            last_health_check: DateTime.utc_now()
        }

        {name, updated_state}
      end)

    # Update health monitor
    new_health_monitor =
      Enum.reduce(new_providers, state.health_monitor, fn {name, provider_state}, monitor ->
        HealthMonitor.record_health(monitor, name, provider_state.health_status)
      end)

    %{state | providers: new_providers, health_monitor: new_health_monitor}
  end

  defp check_provider_health(provider_state) do
    # Simple health check based on recent failures and response times
    # In a real implementation, this would ping the provider's health endpoint
    cond do
      provider_state.circuit_failures > 5 -> :unhealthy
      provider_state.active_requests > 10 -> :degraded
      true -> :healthy
    end
  end

  defp update_circuit_state(provider_state, health_status) do
    case {provider_state.circuit_state, health_status} do
      {:closed, :unhealthy} -> :open
      {:open, :healthy} -> :half_open
      {:half_open, :healthy} -> :closed
      {:half_open, :unhealthy} -> :open
      {state, _} -> state
    end
  end

  defp handle_request_completion(request_id, result, state) do
    case Map.get(state.active_requests, request_id) do
      nil ->
        state

      request ->
        # Update request status
        {status, response_or_error} =
          case result do
            {:ok, response} -> {:completed, response}
            {:error, error} -> {:failed, error}
          end

        updated_request = %{request | status: status, response: response_or_error}

        # Update cost tracking if successful
        new_cost_tracker =
          case result do
            {:ok, response} ->
              CostTracker.record_usage(state.cost_tracker, request.provider, response)

            _ ->
              state.cost_tracker
          end

        # Update provider state
        provider_state = Map.get(state.providers, request.provider)

        {new_failures, new_circuit_state} =
          case result do
            {:ok, _} ->
              {0, provider_state.circuit_state}

            {:error, _} ->
              failures = provider_state.circuit_failures + 1
              circuit_state = if failures > 5, do: :open, else: provider_state.circuit_state
              {failures, circuit_state}
          end

        new_provider_state = %{
          provider_state
          | active_requests: max(0, provider_state.active_requests - 1),
            circuit_failures: new_failures,
            circuit_state: new_circuit_state
        }

        new_providers = Map.put(state.providers, request.provider, new_provider_state)

        # Reply if sync request
        if request.from && !request.async do
          GenServer.reply(request.from, result)
        end

        %{
          state
          | active_requests: Map.put(state.active_requests, request_id, updated_request),
            providers: new_providers,
            cost_tracker: new_cost_tracker
        }
    end
  end

  defp generate_request_id do
    ("req_" <> :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)
  end

  defp timeout(opts) do
    Keyword.get(opts, :timeout, 30_000)
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)
  end

  defp schedule_queue_processing do
    Process.send_after(self(), :process_queue, 100)
  end

  defp get_provider_for_request(request, state) do
    provider_name = request.provider || Map.get(state.model_mapping, request.model)

    case Map.get(state.providers, provider_name) do
      nil ->
        {:error, :provider_not_found}

      provider_state ->
        if provider_state.circuit_state == :closed do
          {:ok, provider_name, provider_state}
        else
          # Try fallback
          case find_fallback_provider(request, state) do
            {:ok, fallback_name} ->
              {:ok, fallback_name, Map.get(state.providers, fallback_name)}

            :error ->
              {:error, :all_providers_unavailable}
          end
        end
    end
  end

  defp handle_streaming_request(request, provider_name, provider_state, callback) do
    # For mock provider, simulate streaming
    if provider_name == :mock do
      simulate_mock_streaming(request, callback)
    else
      # Use provider's streaming capability
      adapter = provider_state.config.adapter

      if function_exported?(adapter, :stream_completion, 3) do
        adapter.stream_completion(request, provider_state.config, callback)
      else
        {:error, :streaming_not_supported}
      end
    end
  end

  defp simulate_mock_streaming(_request, callback) do
    # Simulate streaming response for mock provider
    messages = [
      "This ",
      "is ",
      "a ",
      "streaming ",
      "response ",
      "from ",
      "the ",
      "mock ",
      "provider."
    ]

    Enum.each(messages, fn content ->
      chunk = %{
        content: content,
        role: "assistant",
        finish_reason: nil,
        usage: nil,
        metadata: %{}
      }

      callback.(chunk)
      # Simulate network delay
      Process.sleep(100)
    end)

    # Final chunk with usage info
    final_chunk = %{
      content: nil,
      role: nil,
      finish_reason: "stop",
      usage: %{
        prompt_tokens: 10,
        completion_tokens: 9,
        total_tokens: 19
      },
      metadata: %{}
    }

    callback.(final_chunk)

    {:ok, :completed}
  end

  defp check_provider_connection(provider_name) do
    # Check if ConnectionManager is available
    case Process.whereis(RubberDuck.LLM.ConnectionManager) do
      nil ->
        # ConnectionManager not running, assume connected
        true

      _pid ->
        RubberDuck.LLM.ConnectionManager.connected?(provider_name)
    end
  end

  defp notify_connection_usage(provider_name) do
    # Notify ConnectionManager that the provider was used
    case Process.whereis(RubberDuck.LLM.ConnectionManager) do
      nil ->
        :ok

      pid ->
        send(pid, {:update_last_used, provider_name})
        :ok
    end
  end
end
