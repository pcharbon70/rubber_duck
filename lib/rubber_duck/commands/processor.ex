defmodule RubberDuck.Commands.Processor do
  @moduledoc """
  Central command processing engine that executes commands 
  and formats responses for different client types.
  
  This GenServer maintains a registry of command handlers and provides
  both synchronous and asynchronous command execution with progress tracking.
  """

  use GenServer
  
  # No aliases needed - Command and Context are only used in type specs

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :handlers,
      :validators,
      :formatters,
      :async_requests,
      :request_counter
    ]
  end

  defmodule AsyncRequest do
    @moduledoc false
    defstruct [
      :id,
      :command,
      :pid,
      :status,
      :started_at,
      :progress,
      :result
    ]
  end

  # Client API

  @doc """
  Starts the command processor.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a command synchronously.
  """
  def execute(command, timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:execute, command}, timeout)
  end

  @doc """
  Executes a command asynchronously and returns a request ID for tracking.
  """
  def execute_async(command) do
    GenServer.call(__MODULE__, {:execute_async, command})
  end

  @doc """
  Gets the status of an async request.
  """
  def get_status(request_id) do
    GenServer.call(__MODULE__, {:get_status, request_id})
  end

  @doc """
  Cancels an async request.
  """
  def cancel(request_id) do
    GenServer.call(__MODULE__, {:cancel, request_id})
  end

  @doc """
  Lists all registered handlers.
  """
  def list_handlers do
    GenServer.call(__MODULE__, :list_handlers)
  end

  # Server Implementation

  @impl true
  def init(_opts) do
    state = %State{
      handlers: load_command_handlers(),
      validators: load_validators(),
      formatters: load_formatters(),
      async_requests: %{},
      request_counter: 0
    }

    Logger.info("Command processor started with #{map_size(state.handlers)} handlers")
    {:ok, state}
  end

  @impl true
  def handle_call({:execute, command}, _from, state) do
    result = command
    |> validate_command(state.validators)
    |> authorize_command()
    |> execute_with_handler(state.handlers)
    |> format_response(command.format, command.client_type, state.formatters)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:execute_async, command}, _from, state) do
    request_id = generate_request_id(state.request_counter)
    
    # Start async task
    pid = Task.start_link(fn ->
      result = command
      |> validate_command(state.validators)
      |> authorize_command()
      |> execute_with_handler(state.handlers)
      |> format_response(command.format, command.client_type, state.formatters)
      
      # Notify processor of completion
      GenServer.cast(__MODULE__, {:async_complete, request_id, result})
    end)

    async_request = %AsyncRequest{
      id: request_id,
      command: command,
      pid: elem(pid, 1),
      status: :running,
      started_at: DateTime.utc_now(),
      progress: 0
    }

    new_state = %{state | 
      async_requests: Map.put(state.async_requests, request_id, async_request),
      request_counter: state.request_counter + 1
    }

    {:reply, {:ok, %{request_id: request_id}}, new_state}
  end

  @impl true
  def handle_call({:get_status, request_id}, _from, state) do
    case Map.get(state.async_requests, request_id) do
      nil -> {:reply, {:error, "Request not found"}, state}
      request -> {:reply, {:ok, %{
        status: request.status,
        progress: request.progress,
        started_at: request.started_at,
        result: request.result
      }}, state}
    end
  end

  @impl true
  def handle_call({:cancel, request_id}, _from, state) do
    case Map.get(state.async_requests, request_id) do
      nil -> {:reply, {:error, "Request not found"}, state}
      request ->
        # Kill the task
        if Process.alive?(request.pid) do
          Process.exit(request.pid, :kill)
        end
        
        # Update request status
        updated_request = %{request | status: :cancelled}
        new_state = %{state | 
          async_requests: Map.put(state.async_requests, request_id, updated_request)
        }
        
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_handlers, _from, state) do
    {:reply, state.handlers, state}
  end

  @impl true
  def handle_cast({:async_complete, request_id, result}, state) do
    case Map.get(state.async_requests, request_id) do
      nil -> 
        {:noreply, state}
      request ->
        updated_request = %{request | 
          status: if(match?({:ok, _}, result), do: :completed, else: :failed),
          result: result,
          progress: 100
        }
        
        new_state = %{state | 
          async_requests: Map.put(state.async_requests, request_id, updated_request)
        }
        
        {:noreply, new_state}
    end
  end

  # Private functions

  defp validate_command(command, validators) do
    case Map.get(validators, command.name) do
      nil -> {:error, "Unknown command: #{command.name}"}
      validator -> validator.validate.(command)
    end
  end

  defp authorize_command({:ok, command}) do
    # Basic permission checking
    required_permissions = get_required_permissions(command.name)
    
    if has_required_permissions?(command.context, required_permissions) do
      {:ok, command}
    else
      {:error, "Unauthorized: missing permissions #{inspect(required_permissions)}"}
    end
  end
  defp authorize_command(error), do: error

  defp execute_with_handler({:ok, command}, handlers) do
    case Map.get(handlers, command.name) do
      nil -> {:error, "No handler for command: #{command.name}"}
      handler_module -> 
        try do
          handler_module.execute(command)
        catch
          kind, reason ->
            Logger.error("Handler execution failed: #{inspect({kind, reason})}")
            {:error, "Handler execution failed: #{inspect(reason)}"}
        end
    end
  end
  defp execute_with_handler(error, _), do: error

  defp format_response({:ok, result}, format, client_type, formatters) do
    case get_formatter(format, client_type, formatters) do
      nil -> {:ok, result}  # Return raw result if no formatter
      formatter -> 
        try do
          {:ok, formatter.format(result)}
        catch
          kind, reason ->
            Logger.error("Formatting failed: #{inspect({kind, reason})}")
            {:ok, result}  # Fallback to raw result
        end
    end
  end
  defp format_response(error, _, _, _), do: error

  defp get_formatter(format, client_type, formatters) do
    Map.get(formatters, {format, client_type}) || Map.get(formatters, format)
  end

  defp get_required_permissions(:analyze), do: [:read]
  defp get_required_permissions(:generate), do: [:write]
  defp get_required_permissions(:refactor), do: [:write]
  defp get_required_permissions(:test), do: [:write]
  defp get_required_permissions(:complete), do: [:read]
  defp get_required_permissions(:llm), do: [:read]
  defp get_required_permissions(:conversation), do: [:read, :write]
  defp get_required_permissions(:health), do: []
  defp get_required_permissions(_), do: [:read]

  defp has_required_permissions?(_context, []), do: true
  defp has_required_permissions?(context, required) do
    Enum.all?(required, fn perm -> perm in context.permissions end)
  end

  defp generate_request_id(counter) do
    "req_#{System.system_time(:millisecond)}_#{counter}"
  end

  # Load registry functions (stub implementations for now)
  defp load_command_handlers do
    %{
      health: RubberDuck.Commands.Handlers.Health,
      analyze: RubberDuck.Commands.Handlers.Analyze,
      generate: RubberDuck.Commands.Handlers.Generate,
      complete: RubberDuck.Commands.Handlers.Complete,
      refactor: RubberDuck.Commands.Handlers.Refactor,
      test: RubberDuck.Commands.Handlers.Test,
      llm: RubberDuck.Commands.Handlers.LLM,
      conversation: RubberDuck.Commands.Handlers.Conversation
    }
  end

  defp load_validators do
    # Basic validator that always passes for now
    basic_validator = %{validate: fn command -> {:ok, command} end}
    
    %{
      health: basic_validator,
      analyze: basic_validator,
      generate: basic_validator,
      complete: basic_validator,
      refactor: basic_validator,
      test: basic_validator,
      llm: basic_validator,
      conversation: basic_validator
    }
  end

  defp load_formatters do
    RubberDuck.Commands.Formatters.load_formatters()
  end
end