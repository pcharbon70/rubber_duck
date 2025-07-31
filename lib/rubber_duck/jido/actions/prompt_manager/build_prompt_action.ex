defmodule RubberDuck.Jido.Actions.PromptManager.BuildPromptAction do
  @moduledoc """
  Action for building a prompt from a template with context and options.
  
  This action retrieves a template, builds a prompt using the provided context
  and options, handles caching, and updates usage statistics.
  """
  
  use Jido.Action,
    name: "build_prompt",
    description: "Builds a prompt from template with context and options",
    schema: [
      template_id: [type: :string, required: true, description: "Template ID to use for building"],
      context: [type: :map, default: %{}, description: "Context variables for template"],
      options: [type: :map, default: %{}, description: "Build options"]
    ]

  alias RubberDuck.Agents.Prompt.Builder
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(%{template_id: template_id, context: context, options: options}, context_data) do
    agent = context_data.agent
    
    case Map.get(agent.state.templates, template_id) do
      nil ->
        signal_data = %{
          template_id: template_id,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "prompt.template.not_found", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:error, :template_not_found, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      template ->
        # Check cache first
        cache_key = build_cache_key(template_id, context, options)
        
        case get_from_cache(agent, cache_key) do
          {:hit, cached_result} ->
            signal_data = Map.merge(cached_result, %{
              cache_hit: true,
              timestamp: DateTime.utc_now()
            })
            
            case EmitSignalAction.run(
              %{signal_type: "prompt.built", data: signal_data},
              %{agent: agent}
            ) do
              {:ok, _result, %{agent: updated_agent}} ->
                {:ok, signal_data, %{agent: updated_agent}}
              {:error, reason} ->
                {:error, {:signal_emission_failed, reason}}
            end
            
          :miss ->
            case Builder.build(template, context, options) do
              {:ok, built_prompt} ->
                result = %{
                  "template_id" => template_id,
                  "prompt" => built_prompt,
                  "metadata" => %{
                    "built_at" => DateTime.utc_now(),
                    "template_version" => template.version,
                    "context_size" => map_size(context)
                  }
                }
                
                # Cache the result and update usage statistics
                agent_with_cache = put_in_cache(agent, cache_key, result)
                agent_with_stats = update_template_usage(agent_with_cache, template_id, :success)
                
                signal_data = Map.merge(result, %{
                  timestamp: DateTime.utc_now()
                })
                
                case EmitSignalAction.run(
                  %{signal_type: "prompt.built", data: signal_data},
                  %{agent: agent_with_stats}
                ) do
                  {:ok, _result, %{agent: final_agent}} ->
                    {:ok, signal_data, %{agent: final_agent}}
                  {:error, reason} ->
                    {:error, {:signal_emission_failed, reason}}
                end
                
              {:error, reason} ->
                agent_with_error_stats = update_template_usage(agent, template_id, :error)
                
                signal_data = %{
                  template_id: template_id,
                  error: reason,
                  context: context,
                  timestamp: DateTime.utc_now()
                }
                
                case EmitSignalAction.run(
                  %{signal_type: "prompt.build.failed", data: signal_data},
                  %{agent: agent_with_error_stats}
                ) do
                  {:ok, _result, %{agent: updated_agent}} ->
                    {:error, reason, %{agent: updated_agent}}
                  {:error, emit_reason} ->
                    {:error, {:signal_emission_failed, emit_reason}}
                end
            end
        end
    end
  end

  # Private helper functions

  defp build_cache_key(template_id, context, options) do
    data = %{template_id: template_id, context: context, options: options}
    :crypto.hash(:md5, :erlang.term_to_binary(data)) |> Base.encode16()
  end

  defp get_from_cache(agent, cache_key) do
    case Map.get(agent.state.cache, cache_key) do
      nil -> :miss
      %{expires_at: expires_at} = entry ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:hit, Map.get(entry, :data)}
        else
          :miss
        end
    end
  end

  defp put_in_cache(agent, cache_key, data) do
    expires_at = DateTime.add(DateTime.utc_now(), agent.state.config.cache_ttl, :second)
    
    cache_entry = %{
      data: data,
      expires_at: expires_at,
      created_at: DateTime.utc_now()
    }
    
    put_in(agent.state.cache[cache_key], cache_entry)
  end

  defp update_template_usage(agent, template_id, status) do
    update_in(agent.state.templates[template_id].metadata, fn metadata ->
      current_count = Map.get(metadata, :usage_count, 0)
      error_count = Map.get(metadata, :error_count, 0)
      
      updated_metadata = metadata
      |> Map.put(:usage_count, current_count + 1)
      |> Map.put(:last_used, DateTime.utc_now())
      
      if status == :error do
        Map.put(updated_metadata, :error_count, error_count + 1)
      else
        updated_metadata
      end
    end)
  end
end