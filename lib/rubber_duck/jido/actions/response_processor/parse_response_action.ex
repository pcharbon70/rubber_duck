defmodule RubberDuck.Jido.Actions.ResponseProcessor.ParseResponseAction do
  @moduledoc """
  Action for parsing response content in specific formats.
  
  This action handles response parsing with automatic format detection
  or forced format parsing, providing structured output and metadata.
  """
  
  use Jido.Action,
    name: "parse_response",
    description: "Parses response content with format detection or forced format",
    schema: [
      content: [
        type: :string,
        required: true,
        doc: "The raw content to parse"
      ],
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the request"
      ],
      format: [
        type: :atom,
        default: nil,
        doc: "Optional forced format (json, markdown, text, etc.)"
      ],
      options: [
        type: :map,
        default: %{},
        doc: "Parsing options and configuration"
      ]
    ]

  alias RubberDuck.Agents.Response.Parser
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    %{
      content: content,
      request_id: request_id,
      format: format,
      options: options
    } = params
    
    case parse_content(content, format, options) do
      {:ok, parsed_content, detected_format, metadata} ->
        signal_data = %{
          request_id: request_id,
          parsed_content: parsed_content,
          format: detected_format,
          metadata: metadata,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.parsed", data: signal_data},
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
          content: content,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.parsing.failed", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:error, reason, %{agent: updated_agent}}
          {:error, emit_error} ->
            Logger.error("Failed to emit parsing failure signal: #{inspect(emit_error)}")
            {:error, reason}
        end
    end
  end

  # Private functions

  defp parse_content(content, forced_format, options) do
    case forced_format do
      nil ->
        # Auto-detect format
        Parser.parse(content, options)
        
      format when is_atom(format) ->
        # Use specified format
        case Parser.parse_with_format(content, format, options) do
          {:ok, parsed_content} ->
            {:ok, parsed_content, format, %{forced_format: true}}
          error ->
            error
        end
        
      format when is_binary(format) ->
        # Convert string to atom and retry
        parse_content(content, String.to_atom(format), options)
    end
  end
end