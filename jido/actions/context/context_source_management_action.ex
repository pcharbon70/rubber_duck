defmodule RubberDuck.Jido.Actions.Context.ContextSourceManagementAction do
  @moduledoc """
  Action for managing context sources including registration, updates, and health monitoring.

  This action handles all aspects of context source lifecycle including registration,
  configuration updates, health monitoring, and removal. It ensures that context
  sources are properly managed and available for context assembly operations.

  ## Parameters

  - `operation` - Source operation to perform (required: :register, :update, :remove, :status, :list, :health_check)
  - `source_id` - Source identifier for operations (required for most operations)
  - `source_data` - Source configuration data (required for :register operation)
  - `updates` - Update data for source modification (required for :update operation)
  - `include_config` - Whether to include full configuration in responses (default: false)
  - `health_check_timeout` - Timeout for health checks in milliseconds (default: 5000)

  ## Returns

  - `{:ok, result}` - Source operation completed successfully
  - `{:error, reason}` - Source operation failed

  ## Example

      # Register new source
      params = %{
        operation: :register,
        source_data: %{
          id: "memory_source",
          name: "Memory Context Source",
          type: :memory,
          weight: 1.0,
          config: %{max_entries: 100}
        }
      }

      {:ok, result} = ContextSourceManagementAction.run(params, context)

      # Get source status
      params = %{
        operation: :status,
        source_id: "memory_source",
        include_config: true
      }

      {:ok, result} = ContextSourceManagementAction.run(params, context)
  """

  use Jido.Action,
    name: "context_source_management",
    description: "Manage context sources including registration, updates, and health monitoring",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Source operation to perform (register, update, remove, status, list, health_check)"
      ],
      source_id: [
        type: :string,
        default: nil,
        doc: "Source identifier for operations"
      ],
      source_data: [
        type: :map,
        default: %{},
        doc: "Source configuration data (for register operation)"
      ],
      updates: [
        type: :map,
        default: %{},
        doc: "Update data for source modification"
      ],
      include_config: [
        type: :boolean,
        default: false,
        doc: "Whether to include full configuration in responses"
      ],
      health_check_timeout: [
        type: :integer,
        default: 5000,
        doc: "Timeout for health checks in milliseconds"
      ],
      source_type_filter: [
        type: :atom,
        default: nil,
        doc: "Filter sources by type (for list operation)"
      ],
      include_inactive: [
        type: :boolean,
        default: false,
        doc: "Include inactive sources in list operations"
      ]
    ]

  require Logger

  alias RubberDuck.Context.ContextSource

  @valid_source_types [:memory, :code_analysis, :documentation, :conversation, :planning, :custom]

  @impl true
  def run(params, context) do
    Logger.info("Executing source management operation: #{params.operation}")

    case params.operation do
      :register -> register_source(params, context)
      :update -> update_source(params, context)
      :remove -> remove_source(params, context)
      :status -> get_source_status(params, context)
      :list -> list_sources(params, context)
      :health_check -> health_check_source(params, context)
      :bulk_health_check -> bulk_health_check(params, context)
      _ -> {:error, {:invalid_operation, params.operation}}
    end
  end

  # Source registration

  defp register_source(params, context) do
    with {:ok, validated_data} <- validate_source_data(params.source_data),
         {:ok, source} <- create_source(validated_data),
         {:ok, _} <- store_source(source, context) do
      
      result = %{
        source_id: source.id,
        name: source.name,
        type: source.type,
        status: source.status,
        registered_at: DateTime.utc_now(),
        metadata: %{
          weight: source.weight,
          transformer: source.transformer,
          config_keys: Map.keys(source.config)
        }
      }

      emit_source_registered_signal(source)
      Logger.info("Registered context source: #{source.id} (#{source.type})")
      
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Source registration failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp validate_source_data(source_data) do
    required_fields = ["name", "type"]
    
    # Check required fields
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(source_data, field) or is_nil(source_data[field])
    end)
    
    if Enum.empty?(missing_fields) do
      # Validate source type
      source_type = case source_data["type"] do
        type when is_atom(type) -> type
        type when is_binary(type) -> String.to_atom(type)
        _ -> :invalid
      end
      
      if source_type in @valid_source_types do
        validated = %{
          id: source_data["id"] || generate_source_id(),
          name: source_data["name"],
          type: source_type,
          weight: source_data["weight"] || 1.0,
          config: source_data["config"] || %{},
          transformer: source_data["transformer"]
        }
        
        {:ok, validated}
      else
        {:error, {:invalid_source_type, source_type, @valid_source_types}}
      end
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp create_source(validated_data) do
    source = ContextSource.new(validated_data)
    {:ok, source}
  rescue
    e -> {:error, {:source_creation_failed, Exception.message(e)}}
  end

  # Source updates

  defp update_source(params, context) do
    if params.source_id do
      case get_source_from_context(params.source_id, context) do
        {:ok, existing_source} ->
          with {:ok, validated_updates} <- validate_source_updates(params.updates),
               {:ok, updated_source} <- apply_source_updates(existing_source, validated_updates),
               {:ok, _} <- store_source(updated_source, context) do
            
            result = %{
              source_id: updated_source.id,
              updated_fields: Map.keys(validated_updates),
              updated_at: DateTime.utc_now(),
              new_status: updated_source.status,
              metadata: build_source_metadata(updated_source, params.include_config)
            }

            emit_source_updated_signal(updated_source, validated_updates)
            {:ok, result}
          else
            {:error, reason} -> {:error, reason}
          end
          
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:missing_parameter, :source_id}}
    end
  end

  defp validate_source_updates(updates) do
    # Validate that only allowed fields are being updated
    allowed_fields = ["name", "weight", "config", "transformer", "status"]
    
    invalid_fields = Map.keys(updates) -- allowed_fields
    
    if Enum.empty?(invalid_fields) do
      validated = Map.take(updates, allowed_fields)
      {:ok, validated}
    else
      {:error, {:invalid_update_fields, invalid_fields}}
    end
  end

  defp apply_source_updates(source, updates) do
    updated_source = ContextSource.update(source, updates)
    {:ok, updated_source}
  rescue
    e -> {:error, {:update_failed, Exception.message(e)}}
  end

  # Source removal

  defp remove_source(params, context) do
    if params.source_id do
      case get_source_from_context(params.source_id, context) do
        {:ok, source} ->
          case remove_source_from_context(params.source_id, context) do
            :ok ->
              result = %{
                source_id: params.source_id,
                removed_at: DateTime.utc_now(),
                was_active: source.status == :active,
                cleanup_performed: true
              }

              emit_source_removed_signal(source)
              # TODO: Trigger cache invalidation for this source
              
              {:ok, result}
              
            {:error, reason} ->
              {:error, {:removal_failed, reason}}
          end
          
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:missing_parameter, :source_id}}
    end
  end

  # Source status

  defp get_source_status(params, context) do
    if params.source_id do
      case get_source_from_context(params.source_id, context) do
        {:ok, source} ->
          result = %{
            source_id: source.id,
            name: source.name,
            type: source.type,
            status: source.status,
            weight: source.weight,
            last_fetch: source.last_fetch,
            last_health_check: source.last_health_check,
            failure_count: source.failure_count,
            created_at: source.created_at,
            updated_at: source.updated_at,
            metadata: build_source_metadata(source, params.include_config)
          }
          
          {:ok, result}
          
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:missing_parameter, :source_id}}
    end
  end

  # Source listing

  defp list_sources(params, context) do
    case get_all_sources_from_context(context) do
      {:ok, sources} ->
        filtered_sources = sources
        |> filter_by_type(params.source_type_filter)
        |> filter_by_active_status(params.include_inactive)
        
        source_summaries = Enum.map(filtered_sources, fn source ->
          %{
            source_id: source.id,
            name: source.name,
            type: source.type,
            status: source.status,
            weight: source.weight,
            last_fetch: source.last_fetch,
            failure_count: source.failure_count,
            metadata: if(params.include_config, do: build_source_metadata(source, true), else: %{})
          }
        end)
        
        result = %{
          sources: source_summaries,
          total_count: length(source_summaries),
          active_count: Enum.count(source_summaries, &(&1.status == :active)),
          type_distribution: calculate_type_distribution(filtered_sources),
          retrieved_at: DateTime.utc_now()
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter_by_type(sources, nil), do: sources
  defp filter_by_type(sources, type_filter) do
    Enum.filter(sources, &(&1.type == type_filter))
  end

  defp filter_by_active_status(sources, true), do: sources
  defp filter_by_active_status(sources, false) do
    Enum.filter(sources, &(&1.status == :active))
  end

  # Health checking

  defp health_check_source(params, context) do
    if params.source_id do
      case get_source_from_context(params.source_id, context) do
        {:ok, source} ->
          case perform_health_check(source, params.health_check_timeout) do
            {:ok, health_result} ->
              # Update source with health check results
              updated_source = update_source_health(source, health_result)
              store_source(updated_source, context)
              
              result = %{
                source_id: source.id,
                health_status: health_result.status,
                response_time_ms: health_result.response_time_ms,
                last_error: health_result.error,
                checked_at: health_result.checked_at,
                details: health_result.details
              }
              
              {:ok, result}
              
            {:error, reason} ->
              {:error, {:health_check_failed, reason}}
          end
          
        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:missing_parameter, :source_id}}
    end
  end

  defp bulk_health_check(params, context) do
    case get_all_sources_from_context(context) do
      {:ok, sources} ->
        health_results = sources
        |> filter_by_type(params.source_type_filter)
        |> filter_by_active_status(params.include_inactive)
        |> Enum.map(fn source ->
          case perform_health_check(source, params.health_check_timeout) do
            {:ok, health_result} ->
              update_source_health(source, health_result)
              store_source(source, context)
              
              %{
                source_id: source.id,
                health_status: health_result.status,
                response_time_ms: health_result.response_time_ms,
                error: health_result.error
              }
              
            {:error, reason} ->
              %{
                source_id: source.id,
                health_status: :error,
                response_time_ms: params.health_check_timeout,
                error: inspect(reason)
              }
          end
        end)
        
        healthy_count = Enum.count(health_results, &(&1.health_status == :healthy))
        
        result = %{
          health_results: health_results,
          total_checked: length(health_results),
          healthy_count: healthy_count,
          unhealthy_count: length(health_results) - healthy_count,
          average_response_time: calculate_average_response_time(health_results),
          checked_at: DateTime.utc_now()
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_health_check(source, timeout) do
    start_time = System.monotonic_time(:millisecond)
    
    # TODO: Implement actual health check based on source type
    # For now, simulate a health check
    Process.sleep(10)  # Simulate some work
    
    response_time = System.monotonic_time(:millisecond) - start_time
    
    health_result = %{
      status: :healthy,
      response_time_ms: response_time,
      error: nil,
      checked_at: DateTime.utc_now(),
      details: %{
        source_type: source.type,
        configuration_valid: true,
        connectivity: :ok
      }
    }
    
    {:ok, health_result}
  rescue
    e -> 
      response_time = System.monotonic_time(:millisecond) - start_time
      {:error, %{
        status: :unhealthy,
        response_time_ms: response_time,
        error: Exception.message(e),
        checked_at: DateTime.utc_now()
      }}
  end

  defp update_source_health(source, health_result) do
    %{source |
      last_health_check: health_result.checked_at,
      status: if(health_result.status == :healthy, do: :active, else: :inactive),
      failure_count: if(health_result.status == :healthy, do: 0, else: source.failure_count + 1)
    }
  end

  # Context interface (would integrate with actual agent state)

  defp store_source(_source, _context) do
    # TODO: Integrate with actual agent state storage
    {:ok, :stored}
  end

  defp get_source_from_context(source_id, _context) do
    # TODO: Retrieve from actual agent state
    {:error, {:source_not_found, source_id}}
  end

  defp get_all_sources_from_context(_context) do
    # TODO: Retrieve all sources from actual agent state
    {:ok, []}
  end

  defp remove_source_from_context(source_id, _context) do
    # TODO: Remove from actual agent state
    Logger.info("Would remove source #{source_id} from context")
    :ok
  end

  # Helper functions

  defp build_source_metadata(source, include_config) do
    base_metadata = %{
      has_transformer: not is_nil(source.transformer),
      config_size: map_size(source.config),
      is_custom_type: source.type == :custom
    }
    
    if include_config do
      Map.put(base_metadata, :config, source.config)
    else
      base_metadata
    end
  end

  defp calculate_type_distribution(sources) do
    sources
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, sources} -> {type, length(sources)} end)
  end

  defp calculate_average_response_time(health_results) do
    if Enum.empty?(health_results) do
      0.0
    else
      total_time = Enum.sum(Enum.map(health_results, & &1.response_time_ms))
      total_time / length(health_results)
    end
  end

  defp generate_source_id do
    "src_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  # Signal emission

  defp emit_source_registered_signal(source) do
    # TODO: Emit actual signal
    Logger.debug("Source registered: #{source.id}")
  end

  defp emit_source_updated_signal(source, updates) do
    # TODO: Emit actual signal
    Logger.debug("Source updated: #{source.id}, fields: #{inspect(Map.keys(updates))}")
  end

  defp emit_source_removed_signal(source) do
    # TODO: Emit actual signal
    Logger.debug("Source removed: #{source.id}")
  end
end