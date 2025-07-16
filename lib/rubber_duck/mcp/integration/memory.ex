defmodule RubberDuck.MCP.Integration.Memory do
  @moduledoc """
  Memory system integration for MCP.
  
  This module provides MCP resources and tools for interacting with
  RubberDuck's memory system, enabling AI assistants to store and
  retrieve information across conversations.
  """
  
  use Hermes.Server.Component, type: :resource
  
  alias RubberDuck.Memory
  alias RubberDuck.MCP.Server.State
  alias Hermes.Server.Frame
  
  @category :memory
  @tags [:memory, :storage, :persistence, :context]
  @capabilities [:memory_storage, :search, :indexing]
  
  schema do
    field :store_id, :string, description: "Memory store identifier"
    field :operation, {:enum, ["list", "get", "search", "stats"]}, 
      description: "Memory operation type",
      default: "list"
    field :key, :string, description: "Memory key for get operations"
    field :query, :string, description: "Search query for search operations"
    field :limit, :integer, description: "Maximum results to return", default: 10
  end
  
  @impl true
  def uri do
    "memory://"
  end
  
  @impl true
  def read(%{store_id: store_id, operation: operation} = params, frame) do
    case operation do
      "list" -> list_memory_keys(store_id, params, frame)
      "get" -> get_memory_value(store_id, params, frame)
      "search" -> search_memory(store_id, params, frame)
      "stats" -> get_memory_stats(store_id, params, frame)
      _ -> {:error, %{"code" => "invalid_operation", "message" => "Unknown operation: #{operation}"}}
    end
  end
  
  @impl true
  def list(frame) do
    stores = Memory.list_stores()
    
    resources = Enum.map(stores, fn store ->
      %{
        "uri" => "memory://#{store.id}",
        "name" => store.name,
        "description" => "Memory store: #{store.description}",
        "mime_type" => "application/json",
        "metadata" => %{
          "store_type" => store.type,
          "created_at" => store.created_at,
          "size" => Memory.get_store_size(store.id)
        }
      }
    end)
    
    {:ok, resources, frame}
  end
  
  # Private functions
  
  defp list_memory_keys(store_id, params, frame) do
    case Memory.get_store(store_id) do
      {:ok, store} ->
        limit = params[:limit] || 10
        keys = Memory.list_keys(store, limit: limit)
        
        result = %{
          "store_id" => store_id,
          "operation" => "list",
          "keys" => keys,
          "count" => length(keys),
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        
        {:ok, %{
          "content" => Jason.encode!(result, pretty: true),
          "mime_type" => "application/json"
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "store_not_found",
          "message" => "Memory store not found: #{store_id}",
          "reason" => inspect(reason)
        }}
    end
  end
  
  defp get_memory_value(store_id, params, frame) do
    key = params[:key]
    
    if key do
      case Memory.get_store(store_id) do
        {:ok, store} ->
          case Memory.get(store, key) do
            {:ok, value} ->
              result = %{
                "store_id" => store_id,
                "operation" => "get",
                "key" => key,
                "value" => value,
                "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
              
              {:ok, %{
                "content" => Jason.encode!(result, pretty: true),
                "mime_type" => "application/json"
              }, frame}
              
            {:error, :not_found} ->
              {:error, %{
                "code" => "key_not_found",
                "message" => "Key not found: #{key}"
              }}
              
            {:error, reason} ->
              {:error, %{
                "code" => "get_failed",
                "message" => "Failed to get value for key: #{key}",
                "reason" => inspect(reason)
              }}
          end
          
        {:error, reason} ->
          {:error, %{
            "code" => "store_not_found",
            "message" => "Memory store not found: #{store_id}",
            "reason" => inspect(reason)
          }}
      end
    else
      {:error, %{
        "code" => "missing_key",
        "message" => "Key parameter is required for get operations"
      }}
    end
  end
  
  defp search_memory(store_id, params, frame) do
    query = params[:query]
    
    if query do
      case Memory.get_store(store_id) do
        {:ok, store} ->
          limit = params[:limit] || 10
          
          case Memory.search(store, query, limit: limit) do
            {:ok, results} ->
              result = %{
                "store_id" => store_id,
                "operation" => "search",
                "query" => query,
                "results" => results,
                "count" => length(results),
                "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
              
              {:ok, %{
                "content" => Jason.encode!(result, pretty: true),
                "mime_type" => "application/json"
              }, frame}
              
            {:error, reason} ->
              {:error, %{
                "code" => "search_failed",
                "message" => "Search failed in store: #{store_id}",
                "reason" => inspect(reason)
              }}
          end
          
        {:error, reason} ->
          {:error, %{
            "code" => "store_not_found",
            "message" => "Memory store not found: #{store_id}",
            "reason" => inspect(reason)
          }}
      end
    else
      {:error, %{
        "code" => "missing_query",
        "message" => "Query parameter is required for search operations"
      }}
    end
  end
  
  defp get_memory_stats(store_id, params, frame) do
    case Memory.get_store(store_id) do
      {:ok, store} ->
        stats = Memory.get_stats(store)
        
        result = %{
          "store_id" => store_id,
          "operation" => "stats",
          "stats" => stats,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        
        {:ok, %{
          "content" => Jason.encode!(result, pretty: true),
          "mime_type" => "application/json"
        }, frame}
        
      {:error, reason} ->
        {:error, %{
          "code" => "store_not_found",
          "message" => "Memory store not found: #{store_id}",
          "reason" => inspect(reason)
        }}
    end
  end
end

defmodule RubberDuck.MCP.Integration.Memory.Tools do
  @moduledoc """
  Memory manipulation tools for MCP.
  """
  
  defmodule MemoryPut do
    @moduledoc """
    Tool for storing data in memory.
    """
    
    use Hermes.Server.Component, type: :tool
    
    @category :memory
    @tags [:memory, :storage, :write]
    @capabilities [:memory_storage, :data_persistence]
    
    schema do
      field :store_id, {:required, :string}, description: "Memory store identifier"
      field :key, {:required, :string}, description: "Memory key"
      field :value, {:required, :any}, description: "Value to store"
      field :ttl, :integer, description: "Time to live in seconds"
      field :tags, {:list, :string}, description: "Tags for the stored value"
    end
    
    @impl true
    def execute(%{store_id: store_id, key: key, value: value} = params, frame) do
      case Memory.get_store(store_id) do
        {:ok, store} ->
          # Prepare options
          opts = []
          opts = if ttl = params[:ttl], do: [{:ttl, ttl} | opts], else: opts
          opts = if tags = params[:tags], do: [{:tags, tags} | opts], else: opts
          
          case Memory.put(store, key, value, opts) do
            :ok ->
              # Update server state
              state = frame.assigns[:server_state] || %State{}
              updated_state = State.record_request(state)
              frame = Frame.assign(frame, :server_state, updated_state)
              
              result = %{
                "status" => "success",
                "store_id" => store_id,
                "key" => key,
                "operation" => "put",
                "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
              
              {:ok, result, frame}
              
            {:error, reason} ->
              {:error, %{
                "code" => "put_failed",
                "message" => "Failed to store value",
                "reason" => inspect(reason)
              }}
          end
          
        {:error, reason} ->
          {:error, %{
            "code" => "store_not_found",
            "message" => "Memory store not found: #{store_id}",
            "reason" => inspect(reason)
          }}
      end
    end
  end
  
  defmodule MemoryDelete do
    @moduledoc """
    Tool for deleting data from memory.
    """
    
    use Hermes.Server.Component, type: :tool
    
    @category :memory
    @tags [:memory, :storage, :delete]
    @capabilities [:memory_storage, :data_cleanup]
    
    schema do
      field :store_id, {:required, :string}, description: "Memory store identifier"
      field :key, {:required, :string}, description: "Memory key to delete"
    end
    
    @impl true
    def execute(%{store_id: store_id, key: key}, frame) do
      case Memory.get_store(store_id) do
        {:ok, store} ->
          case Memory.delete(store, key) do
            :ok ->
              # Update server state
              state = frame.assigns[:server_state] || %State{}
              updated_state = State.record_request(state)
              frame = Frame.assign(frame, :server_state, updated_state)
              
              result = %{
                "status" => "success",
                "store_id" => store_id,
                "key" => key,
                "operation" => "delete",
                "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
              }
              
              {:ok, result, frame}
              
            {:error, :not_found} ->
              {:error, %{
                "code" => "key_not_found",
                "message" => "Key not found: #{key}"
              }}
              
            {:error, reason} ->
              {:error, %{
                "code" => "delete_failed",
                "message" => "Failed to delete key",
                "reason" => inspect(reason)
              }}
          end
          
        {:error, reason} ->
          {:error, %{
            "code" => "store_not_found",
            "message" => "Memory store not found: #{store_id}",
            "reason" => inspect(reason)
          }}
      end
    end
  end
  
  defmodule MemoryBatch do
    @moduledoc """
    Tool for batch operations on memory.
    """
    
    use Hermes.Server.Component, type: :tool
    
    @category :memory
    @tags [:memory, :storage, :batch]
    @capabilities [:memory_storage, :batch_operations]
    
    schema do
      field :store_id, {:required, :string}, description: "Memory store identifier"
      field :operations, {:required, {:list, :map}}, description: "List of operations to perform"
    end
    
    @impl true
    def execute(%{store_id: store_id, operations: operations}, frame) do
      case Memory.get_store(store_id) do
        {:ok, store} ->
          results = Enum.map(operations, fn op ->
            execute_batch_operation(store, op)
          end)
          
          # Update server state
          state = frame.assigns[:server_state] || %State{}
          updated_state = State.record_request(state)
          frame = Frame.assign(frame, :server_state, updated_state)
          
          result = %{
            "status" => "success",
            "store_id" => store_id,
            "operation" => "batch",
            "results" => results,
            "count" => length(results),
            "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
          
          {:ok, result, frame}
          
        {:error, reason} ->
          {:error, %{
            "code" => "store_not_found",
            "message" => "Memory store not found: #{store_id}",
            "reason" => inspect(reason)
          }}
      end
    end
    
    defp execute_batch_operation(store, %{"operation" => "get", "key" => key}) do
      case Memory.get(store, key) do
        {:ok, value} -> %{"operation" => "get", "key" => key, "status" => "success", "value" => value}
        {:error, reason} -> %{"operation" => "get", "key" => key, "status" => "error", "reason" => inspect(reason)}
      end
    end
    
    defp execute_batch_operation(store, %{"operation" => "put", "key" => key, "value" => value}) do
      case Memory.put(store, key, value) do
        :ok -> %{"operation" => "put", "key" => key, "status" => "success"}
        {:error, reason} -> %{"operation" => "put", "key" => key, "status" => "error", "reason" => inspect(reason)}
      end
    end
    
    defp execute_batch_operation(store, %{"operation" => "delete", "key" => key}) do
      case Memory.delete(store, key) do
        :ok -> %{"operation" => "delete", "key" => key, "status" => "success"}
        {:error, reason} -> %{"operation" => "delete", "key" => key, "status" => "error", "reason" => inspect(reason)}
      end
    end
    
    defp execute_batch_operation(_store, operation) do
      %{"operation" => "unknown", "status" => "error", "reason" => "Unknown operation: #{inspect(operation)}"}
    end
  end
end