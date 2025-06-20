defmodule RubberDuck.Commands.CommandRouter do
  @moduledoc """
  Distributed command router that handles command execution routing across the cluster.
  
  The CommandRouter provides intelligent routing of commands to appropriate handlers,
  integrating with the CommandRegistry for command discovery and providing:
  
  - Command request validation and routing
  - Load balancing across available nodes
  - Fault tolerance and error handling
  - Integration with existing Interface.Gateway patterns
  - Performance monitoring and statistics
  - Support for sync/async and streaming commands
  
  ## Usage
  
      # Start the router (usually done by supervision tree)
      {:ok, pid} = CommandRouter.start_link(name: :command_router, registry: :command_registry)
      
      # Execute a command
      request = %{
        command: "analyze",
        params: %{file: "test.ex"},
        context: %{session_id: "session-123", interface: :cli}
      }
      
      {:ok, result} = CommandRouter.execute_command(:command_router, request)
      
      # Get routing statistics
      stats = CommandRouter.get_stats(:command_router)
  
  ## Request Format
  
  Commands are executed using request maps with the following structure:
  
      %{
        command: "command_name",           # Required: command name or alias
        params: %{key: value},             # Required: command parameters
        context: %{                        # Required: execution context
          session_id: "session-123",      # Session identifier
          interface: :cli,                # Interface type (:cli, :tui, :web, :ide)
          user_id: "user-456",            # Optional: user identifier
          request_id: "req-789",          # Optional: request tracking
          timeout: 5000,                  # Optional: execution timeout
          preferred_node: :local          # Optional: node preference
        },
        timeout: 5000                     # Optional: request timeout override
      }
  
  ## Response Format
  
  Responses follow these patterns:
  
  - `{:ok, result}` - Successful execution
  - `{:error, reason}` - Execution failed
  - `{:error, :command_not_found}` - Command not found in registry
  - `{:error, :invalid_request}` - Malformed request
  - `{:error, {:validation_failed, errors}}` - Parameter validation failed
  - `{:error, :registry_unavailable}` - Registry not available
  - `{:error, :router_unavailable}` - Router not available
  """

  use GenServer
  
  alias RubberDuck.Commands.{CommandRegistry, CommandBehaviour}
  
  require Logger

  @default_timeout 5_000
  @stats_window_size 100

  @type router_name :: atom() | pid()
  @type command_request :: %{
    command: String.t(),
    params: map(),
    context: map(),
    timeout: pos_integer()
  }
  @type execution_result :: {:ok, any()} | {:error, any()}
  @type routing_stats :: %{
    total_requests: non_neg_integer(),
    successful_requests: non_neg_integer(),
    failed_requests: non_neg_integer(),
    average_response_time: float(),
    current_load: non_neg_integer()
  }
  @type routing_info :: %{
    available_commands: [String.t()],
    node_load: map(),
    routing_strategy: atom()
  }

  # Client API

  @doc """
  Starts the command router with the given options.
  
  ## Options
  
  - `:name` - The name to register the process under (required)
  - `:registry` - The CommandRegistry to use for command lookup (required)
  - `:strategy` - Routing strategy (:local, :distributed, :load_balanced) (default: :local)
  - `:timeout` - Default command execution timeout (default: 5000ms)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a command through the router.
  
  The router will:
  1. Validate the request structure
  2. Look up the command in the registry
  3. Validate command parameters
  4. Route to appropriate execution handler
  5. Return the result
  """
  @spec execute_command(router_name(), command_request()) :: execution_result()
  def execute_command(router, request) do
    GenServer.call(router, {:execute_command, request}, get_timeout(request))
  rescue
    e in [ArgumentError, RuntimeError] ->
      {:error, "Router error: #{Exception.message(e)}"}
  catch
    :exit, {:noproc, _} ->
      {:error, :router_unavailable}
    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  @doc """
  Gets routing statistics from the router.
  """
  @spec get_stats(router_name()) :: routing_stats()
  def get_stats(router) do
    GenServer.call(router, :get_stats)
  catch
    :exit, {:noproc, _} ->
      %{
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        average_response_time: 0.0,
        current_load: 0
      }
  end

  @doc """
  Gets current routing information including available commands and node status.
  """
  @spec get_routing_info(router_name()) :: routing_info()
  def get_routing_info(router) do
    GenServer.call(router, :get_routing_info)
  catch
    :exit, {:noproc, _} ->
      %{
        available_commands: [],
        node_load: %{},
        routing_strategy: :unknown
      }
  end

  # Server Implementation

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    registry = Keyword.fetch!(opts, :registry)
    strategy = Keyword.get(opts, :strategy, :local)
    default_timeout = Keyword.get(opts, :timeout, @default_timeout)
    
    state = %{
      name: name,
      registry: registry,
      strategy: strategy,
      default_timeout: default_timeout,
      stats: init_stats()
    }
    
    Logger.debug("Starting command router: #{name} with registry: #{registry}")
    
    {:ok, state}
  end

  @impl true
  def handle_call({:execute_command, request}, _from, state) do
    case validate_request(request) do
      :ok ->
        start_time = System.monotonic_time(:millisecond)
        result = execute_command_internal(request, state)
        execution_time = System.monotonic_time(:millisecond) - start_time
        
        case result do
          {:ok, command_result} ->
            new_state = record_success(state, execution_time)
            {:reply, {:ok, command_result}, new_state}
          
          {:error, error} ->
            new_state = record_failure(state, error, execution_time)
            {:reply, {:error, error}, new_state}
        end
      
      {:error, reason} ->
        new_state = record_failure(state, reason)
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_current_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_routing_info, _from, state) do
    routing_info = get_current_routing_info(state)
    {:reply, routing_info, state}
  end


  # Internal Functions

  defp validate_request(request) when is_map(request) do
    with :ok <- validate_required_fields(request),
         :ok <- validate_field_types(request) do
      :ok
    end
  end
  defp validate_request(_), do: {:error, :invalid_request}

  defp validate_required_fields(request) do
    required_fields = [:command, :params, :context]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(request, field)
    end)
    
    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, :invalid_request}
    end
  end

  defp validate_field_types(request) do
    cond do
      not is_binary(request.command) or String.length(request.command) == 0 ->
        {:error, :invalid_request}
      
      not is_map(request.params) ->
        {:error, :invalid_request}
      
      not is_map(request.context) ->
        {:error, :invalid_request}
      
      true ->
        :ok
    end
  end


  defp execute_command_internal(request, state) do
    with {:ok, command_module} <- find_command(request.command, state),
         :ok <- validate_command_params(command_module, request.params),
         enhanced_context <- enhance_context(request.context, state),
         {:ok, result} <- execute_command_with_module(command_module, request.params, enhanced_context) do
      {:ok, result}
    end
  end

  defp find_command(command_name, state) do
    case CommandRegistry.find_command_module(state.registry, command_name) do
      {:ok, module} -> {:ok, module}
      {:error, :not_found} -> {:error, :command_not_found}
      {:error, :registry_unavailable} -> {:error, :registry_unavailable}
    end
  end

  defp validate_command_params(command_module, params) do
    case command_module.validate(params) do
      :ok -> :ok
      {:error, validation_errors} -> {:error, {:validation_failed, validation_errors}}
    end
  end

  defp enhance_context(context, state) do
    Map.merge(context, %{
      node: Node.self(),
      router: state.name,
      routing_strategy: state.strategy,
      routed_at: System.system_time(:microsecond)
    })
  end

  defp execute_command_with_module(command_module, params, context) do
    try do
      command_module.execute(params, context)
    rescue
      error ->
        Logger.error("Command execution failed: #{Exception.message(error)}")
        {:error, "Command execution failed: #{Exception.message(error)}"}
    catch
      :throw, value ->
        {:error, "Command threw: #{inspect(value)}"}
      
      :exit, reason ->
        {:error, "Command exited: #{inspect(reason)}"}
    end
  end

  defp get_timeout(request) do
    request[:timeout] || @default_timeout
  end


  defp init_stats do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      response_times: :queue.new(),
      start_time: System.monotonic_time(:millisecond)
    }
  end

  defp record_success(state, execution_time) do
    stats = state.stats
    new_response_times = add_response_time(stats.response_times, execution_time)
    
    new_stats = %{stats |
      total_requests: stats.total_requests + 1,
      successful_requests: stats.successful_requests + 1,
      response_times: new_response_times
    }
    
    %{state | stats: new_stats}
  end

  defp record_failure(state, error) do
    record_failure(state, error, 0)
  end

  defp record_failure(state, _error, execution_time) do
    stats = state.stats
    new_response_times = add_response_time(stats.response_times, execution_time)
    
    new_stats = %{stats |
      total_requests: stats.total_requests + 1,
      failed_requests: stats.failed_requests + 1,
      response_times: new_response_times
    }
    
    %{state | stats: new_stats}
  end

  defp add_response_time(response_times, execution_time) do
    new_queue = :queue.in(execution_time, response_times)
    
    # Keep only the last N response times for average calculation
    if :queue.len(new_queue) > @stats_window_size do
      {_oldest, trimmed_queue} = :queue.out(new_queue)
      trimmed_queue
    else
      new_queue
    end
  end

  defp calculate_current_stats(state) do
    stats = state.stats
    response_times_list = :queue.to_list(stats.response_times)
    
    average_response_time = if Enum.empty?(response_times_list) do
      0.0
    else
      Enum.sum(response_times_list) / length(response_times_list)
    end
    
    %{
      total_requests: stats.total_requests,
      successful_requests: stats.successful_requests,
      failed_requests: stats.failed_requests,
      average_response_time: average_response_time,
      current_load: 0
    }
  end

  defp get_current_routing_info(state) do
    available_commands = case CommandRegistry.list_commands(state.registry) do
      commands when is_list(commands) ->
        Enum.map(commands, & &1.name)
      
      {:error, _} ->
        []
    end
    
    %{
      available_commands: available_commands,
      node_load: %{Node.self() => 0},
      routing_strategy: state.strategy
    }
  end
end