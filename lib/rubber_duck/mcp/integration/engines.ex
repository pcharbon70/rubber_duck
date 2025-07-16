defmodule RubberDuck.MCP.Integration.Engines do
  @moduledoc """
  Engine system integration for MCP.
  
  This module exposes RubberDuck's engine system through MCP,
  allowing AI assistants to discover and execute engines.
  """
  
  use Hermes.Server.Component, type: :resource
  
  alias RubberDuck.Engines
  alias RubberDuck.MCP.Server.State
  alias Hermes.Server.Frame
  
  @category :engines
  @tags [:engines, :execution, :processing]
  @capabilities [:workflow_execution, :async, :monitoring]
  
  schema do
    field :engine_id, :string, description: "Engine identifier"
    field :operation, {:enum, ["list", "get", "status", "capabilities"]}, 
      description: "Engine operation type",
      default: "list"
    field :include_stats, :boolean, description: "Include engine statistics", default: false
  end
  
  @impl true
  def uri do
    "engines://"
  end
  
  @impl true
  def read(%{engine_id: engine_id, operation: operation} = params, frame) do
    case operation do
      "list" -> list_engines(params, frame)
      "get" -> get_engine(engine_id, params, frame)
      "status" -> get_engine_status(engine_id, params, frame)
      "capabilities" -> get_engine_capabilities(engine_id, params, frame)
      _ -> {:error, %{"code" => "invalid_operation", "message" => "Unknown operation: #{operation}"}}
    end
  end
  
  @impl true
  def list(frame) do
    engines = Engines.list_engines()
    
    resources = Enum.map(engines, fn engine ->
      %{
        "uri" => "engines://#{engine.id}",
        "name" => engine.name,
        "description" => "Engine: #{engine.description}",
        "mime_type" => "application/json",
        "metadata" => %{
          "engine_type" => engine.type,
          "status" => Engines.get_status(engine.id),
          "created_at" => engine.created_at,
          "version" => engine.version
        }
      }
    end)
    
    {:ok, resources, frame}
  end
  
  # Private functions
  
  defp list_engines(params, frame) do
    engines = Engines.list_engines()
    include_stats = params[:include_stats] || false
    
    engine_data = Enum.map(engines, fn engine ->
      base_data = %{
        "id" => engine.id,
        "name" => engine.name,
        "description" => engine.description,
        "type" => engine.type,
        "version" => engine.version,
        "status" => Engines.get_status(engine.id),
        "capabilities" => Engines.get_capabilities(engine.id)
      }
      
      if include_stats do
        Map.put(base_data, "stats", Engines.get_stats(engine.id))
      else
        base_data
      end
    end)
    
    result = %{
      "operation" => "list",
      "engines" => engine_data,
      "count" => length(engine_data),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    {:ok, %{
      "content" => Jason.encode!(result, pretty: true),
      "mime_type" => "application/json"
    }, frame}
  end
  
  defp get_engine(engine_id, params, frame) do
    case Engines.get_engine(engine_id) do
      {:ok, engine} ->
        include_stats = params[:include_stats] || false
        
        engine_data = %{
          "id" => engine.id,
          "name" => engine.name,
          "description" => engine.description,
          "type" => engine.type,
          "version" => engine.version,
          "status" => Engines.get_status(engine.id),
          "capabilities" => Engines.get_capabilities(engine.id),
          "configuration" => engine.configuration,
          "metadata" => engine.metadata
        }
        
        engine_data = if include_stats do
          Map.put(engine_data, "stats", Engines.get_stats(engine.id))
        else
          engine_data
        end
        
        result = %{
          "operation" => "get",
          "engine" => engine_data,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        
        {:ok, %{
          "content" => Jason.encode!(result, pretty: true),
          "mime_type" => "application/json"
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "engine_not_found",
          "message" => "Engine not found: #{engine_id}",
          "reason" => inspect(reason)
        }}
    end
  end
  
  defp get_engine_status(engine_id, _params, frame) do
    case Engines.get_status(engine_id) do
      {:ok, status} ->
        result = %{
          "operation" => "status",
          "engine_id" => engine_id,
          "status" => status,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        
        {:ok, %{
          "content" => Jason.encode!(result, pretty: true),
          "mime_type" => "application/json"
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "engine_not_found",
          "message" => "Engine not found: #{engine_id}",
          "reason" => inspect(reason)
        }}
    end
  end
  
  defp get_engine_capabilities(engine_id, _params, frame) do
    case Engines.get_capabilities(engine_id) do
      {:ok, capabilities} ->
        result = %{
          "operation" => "capabilities",
          "engine_id" => engine_id,
          "capabilities" => capabilities,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        
        {:ok, %{
          "content" => Jason.encode!(result, pretty: true),
          "mime_type" => "application/json"
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "engine_not_found",
          "message" => "Engine not found: #{engine_id}",
          "reason" => inspect(reason)
        }}
    end
  end
end

defmodule RubberDuck.MCP.Integration.Engines.Tools do
  @moduledoc """
  Engine execution tools for MCP.
  """
  
  defmodule EngineExecute do
    @moduledoc """
    Tool for executing engines.
    """
    
    use Hermes.Server.Component, type: :tool
    
    @category :engines
    @tags [:engines, :execution, :processing]
    @capabilities [:workflow_execution, :async, :monitoring]
    
    schema do
      field :engine_id, {:required, :string}, description: "Engine identifier"
      field :input, {:required, :any}, description: "Input data for the engine"
      field :async, :boolean, description: "Execute asynchronously", default: false
      field :timeout, :integer, description: "Execution timeout in milliseconds", default: 30_000
      field :context, :map, description: "Additional context for execution", default: %{}
    end
    
    @impl true
    def execute(%{engine_id: engine_id, input: input} = params, frame) do
      case Engines.get_engine(engine_id) do
        {:ok, engine} ->
          # Prepare execution options
          opts = [
            timeout: params[:timeout] || 30_000,
            context: params[:context] || %{}
          ]
          
          if params[:async] do
            execute_async(engine, input, opts, frame)
          else
            execute_sync(engine, input, opts, frame)
          end
          
        {:error, reason} ->
          {:error, %{
            "code" => "engine_not_found",
            "message" => "Engine not found: #{engine_id}",
            "reason" => inspect(reason)
          }}
      end
    end
    
    defp execute_sync(engine, input, opts, frame) do
      start_time = System.monotonic_time(:millisecond)
      
      case Engines.execute(engine, input, opts) do
        {:ok, result} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time
          
          # Update server state
          state = frame.assigns[:server_state] || %State{}
          updated_state = State.record_request(state)
          frame = Frame.assign(frame, :server_state, updated_state)
          
          response = %{
            "status" => "completed",
            "engine_id" => engine.id,
            "result" => result,
            "execution_time_ms" => duration,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          {:ok, response, frame}
          
        {:error, reason} ->
          {:error, %{
            "code" => "execution_failed",
            "message" => "Engine execution failed",
            "engine_id" => engine.id,
            "reason" => inspect(reason)
          }}
      end
    end
    
    defp execute_async(engine, input, opts, frame) do
      case Engines.execute_async(engine, input, opts) do
        {:ok, execution_id} ->
          # Update server state
          state = frame.assigns[:server_state] || %State{}
          updated_state = State.record_request(state)
          frame = Frame.assign(frame, :server_state, updated_state)
          
          response = %{
            "status" => "started",
            "engine_id" => engine.id,
            "execution_id" => execution_id,
            "message" => "Engine execution started asynchronously",
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          {:ok, response, frame}
          
        {:error, reason} ->
          {:error, %{
            "code" => "execution_failed",
            "message" => "Failed to start async engine execution",
            "engine_id" => engine.id,
            "reason" => inspect(reason)
          }}
      end
    end
  end
  
  defmodule EngineGetResult do
    @moduledoc """
    Tool for retrieving async engine execution results.
    """
    
    use Hermes.Server.Component, type: :tool
    
    @category :engines
    @tags [:engines, :execution, :results]
    @capabilities [:workflow_execution, :async, :monitoring]
    
    schema do
      field :execution_id, {:required, :string}, description: "Execution identifier"
      field :wait, :boolean, description: "Wait for completion if still running", default: false
      field :timeout, :integer, description: "Wait timeout in milliseconds", default: 5_000
    end
    
    @impl true
    def execute(%{execution_id: execution_id} = params, frame) do
      case Engines.get_execution_result(execution_id) do
        {:ok, result} ->
          # Update server state
          state = frame.assigns[:server_state] || %State{}
          updated_state = State.record_request(state)
          frame = Frame.assign(frame, :server_state, updated_state)
          
          response = %{
            "execution_id" => execution_id,
            "result" => result,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          {:ok, response, frame}
          
        {:error, :not_found} ->
          {:error, %{
            "code" => "execution_not_found",
            "message" => "Execution not found: #{execution_id}"
          }}
          
        {:error, :running} ->
          if params[:wait] do
            wait_for_result(execution_id, params[:timeout] || 5_000, frame)
          else
            response = %{
              "execution_id" => execution_id,
              "status" => "running",
              "message" => "Execution still in progress",
              "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
            
            {:ok, response, frame}
          end
          
        {:error, reason} ->
          {:error, %{
            "code" => "get_result_failed",
            "message" => "Failed to get execution result",
            "execution_id" => execution_id,
            "reason" => inspect(reason)
          }}
      end
    end
    
    defp wait_for_result(execution_id, timeout, frame) do
      case Engines.wait_for_result(execution_id, timeout) do
        {:ok, result} ->
          # Update server state
          state = frame.assigns[:server_state] || %State{}
          updated_state = State.record_request(state)
          frame = Frame.assign(frame, :server_state, updated_state)
          
          response = %{
            "execution_id" => execution_id,
            "result" => result,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          {:ok, response, frame}
          
        {:error, :timeout} ->
          {:error, %{
            "code" => "wait_timeout",
            "message" => "Timeout waiting for execution result",
            "execution_id" => execution_id
          }}
          
        {:error, reason} ->
          {:error, %{
            "code" => "wait_failed",
            "message" => "Failed to wait for execution result",
            "execution_id" => execution_id,
            "reason" => inspect(reason)
          }}
      end
    end
  end
  
  defmodule EngineCancel do
    @moduledoc """
    Tool for cancelling engine executions.
    """
    
    use Hermes.Server.Component, type: :tool
    
    @category :engines
    @tags [:engines, :execution, :cancellation]
    @capabilities [:workflow_execution, :async, :monitoring]
    
    schema do
      field :execution_id, {:required, :string}, description: "Execution identifier to cancel"
      field :reason, :string, description: "Cancellation reason", default: "user_requested"
    end
    
    @impl true
    def execute(%{execution_id: execution_id} = params, frame) do
      reason = params[:reason] || "user_requested"
      
      case Engines.cancel_execution(execution_id, reason) do
        :ok ->
          # Update server state
          state = frame.assigns[:server_state] || %State{}
          updated_state = State.record_request(state)
          frame = Frame.assign(frame, :server_state, updated_state)
          
          response = %{
            "status" => "cancelled",
            "execution_id" => execution_id,
            "reason" => reason,
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          {:ok, response, frame}
          
        {:error, :not_found} ->
          {:error, %{
            "code" => "execution_not_found",
            "message" => "Execution not found: #{execution_id}"
          }}
          
        {:error, :not_running} ->
          {:error, %{
            "code" => "execution_not_running",
            "message" => "Execution is not running: #{execution_id}"
          }}
          
        {:error, reason} ->
          {:error, %{
            "code" => "cancel_failed",
            "message" => "Failed to cancel execution",
            "execution_id" => execution_id,
            "reason" => inspect(reason)
          }}
      end
    end
  end
end