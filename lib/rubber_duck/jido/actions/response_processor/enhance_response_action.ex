defmodule RubberDuck.Jido.Actions.ResponseProcessor.EnhanceResponseAction do
  @moduledoc """
  Action for enhancing response content quality and readability.
  
  This action applies a series of content enhancers to improve formatting,
  readability, link processing, and content cleanup.
  """
  
  use Jido.Action,
    name: "enhance_response",
    description: "Enhances response content with formatting, cleanup, and readability improvements",
    schema: [
      content: [
        type: :string,
        required: true,
        doc: "The content to enhance"
      ],
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the request"
      ],
      options: [
        type: :map,
        default: %{},
        doc: "Enhancement options and configuration"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    %{
      content: content,
      request_id: request_id,
      options: enhancement_options
    } = params
    
    case enhance_content(content, enhancement_options, agent) do
      {:ok, enhanced_content, enhancement_log} ->
        signal_data = %{
          request_id: request_id,
          enhanced_content: enhanced_content,
          enhancement_log: enhancement_log,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.enhanced", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:ok, signal_data, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      {:error, reason} ->
        signal_data = %{
          request_id: request_id,
          error: reason,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.enhancement.failed", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:error, reason, %{agent: updated_agent}}
          {:error, emit_error} ->
            Logger.error("Failed to emit enhancement failure signal: #{inspect(emit_error)}")
            {:error, reason}
        end
    end
  end

  # Private functions

  defp enhance_content(content, enhancement_options, agent) do
    try do
      enhancers = agent.state.enhancers
      enhancement_log = []
      
      # Apply enhancers in sequence
      {enhanced_content, final_log} = Enum.reduce(enhancers, {content, enhancement_log}, fn enhancer, {current_content, log} ->
        case apply_enhancer(enhancer, current_content, enhancement_options) do
          {:ok, improved_content, enhancer_log} ->
            {improved_content, [enhancer_log | log]}
            
          {:error, _reason} ->
            # Enhancement failed, keep current content
            {current_content, log}
        end
      end)
      
      {:ok, enhanced_content, Enum.reverse(final_log)}
      
    rescue
      error ->
        Logger.warning("Content enhancement failed: #{inspect(error)}")
        {:error, "Enhancement failed: #{Exception.message(error)}"}
    end
  end

  defp apply_enhancer(:format_beautification, content, _options) do
    # Basic formatting improvements
    enhanced = content
    |> String.replace(~r/\s+/, " ")  # Normalize whitespace
    |> String.replace(~r/\n\s*\n\s*\n+/, "\n\n")  # Normalize line breaks
    |> String.trim()
    
    log = %{
      type: :format_beautification,
      applied_at: DateTime.utc_now(),
      changes: ["whitespace_normalized", "line_breaks_cleaned"]
    }
    
    {:ok, enhanced, log}
  end

  defp apply_enhancer(:link_enrichment, content, _options) do
    # Find and validate URLs
    enhanced = Regex.replace(~r/(https?:\/\/[^\s]+)/, content, fn full_match, _url ->
      # In production, would validate URL and possibly expand
      full_match
    end)
    
    log = %{
      type: :link_enrichment,
      applied_at: DateTime.utc_now(),
      changes: ["urls_processed"]
    }
    
    {:ok, enhanced, log}
  end

  defp apply_enhancer(:content_cleanup, content, _options) do
    # Remove unwanted artifacts
    enhanced = content
    |> String.replace(~r/\s*\n\s*$/, "")  # Trailing whitespace
    |> String.replace(~r/^\s*\n\s*/, "")  # Leading whitespace
    
    log = %{
      type: :content_cleanup,
      applied_at: DateTime.utc_now(),
      changes: ["artifacts_removed"]
    }
    
    {:ok, enhanced, log}
  end

  defp apply_enhancer(:readability_improvement, content, _options) do
    # Basic readability improvements
    # This is a simplified version - real implementation would be more sophisticated
    log = %{
      type: :readability_improvement,
      applied_at: DateTime.utc_now(),
      changes: ["readability_analyzed"]
    }
    
    {:ok, content, log}  # No changes for now
  end
end