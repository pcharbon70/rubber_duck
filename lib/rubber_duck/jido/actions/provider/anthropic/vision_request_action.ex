defmodule RubberDuck.Jido.Actions.Provider.Anthropic.VisionRequestAction do
  @moduledoc """
  Action for handling Anthropic vision requests with image analysis.
  
  This action processes vision requests for Claude 3 models that support
  image analysis, converting images to the proper format and routing
  through the standard provider request handling.
  """
  
  use Jido.Action,
    name: "vision_request",
    description: "Handles Anthropic vision requests with image analysis",
    schema: [
      request_id: [type: :string, required: true],
      messages: [type: :list, required: true],
      model: [type: :string, required: true],
      images: [type: :list, required: true],
      temperature: [type: :number, default: 0.7],
      max_tokens: [type: :integer, default: nil]
    ]

  alias RubberDuck.Jido.Actions.Provider.ProviderRequestAction
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  # Claude models that support vision
  @vision_models ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Validate model supports vision
    if params.model in @vision_models do
      # Process messages with images
      enhanced_messages = add_images_to_messages(params.messages, params.images)
      
      # Route through regular provider request handling
      provider_params = %{
        request_id: params.request_id,
        messages: enhanced_messages,
        model: params.model,
        provider: "anthropic",
        temperature: params.temperature,
        max_tokens: params.max_tokens
      }
      
      ProviderRequestAction.run(provider_params, context)
    else
      # Emit error for unsupported model
      signal_params = %{
        signal_type: "provider.error",
        data: %{
          request_id: params.request_id,
          error_type: "unsupported_feature",
          error: "Model #{params.model} does not support vision",
          provider: "anthropic",
          timestamp: DateTime.utc_now()
        }
      }
      
      case EmitSignalAction.run(signal_params, %{agent: agent}) do
        {:ok, signal_result, _} ->
          {:ok, %{
            vision_request_failed: true,
            request_id: params.request_id,
            error: "Model #{params.model} does not support vision",
            signal_emitted: signal_result.signal_emitted
          }, %{agent: agent}}
          
        error -> error
      end
    end
  end

  # Private functions

  defp add_images_to_messages(messages, images) do
    # Convert images to Claude's expected format
    Enum.map(messages, fn message ->
      case message do
        %{"role" => "user", "content" => content} = msg ->
          # Add images to user messages
          if images && length(images) > 0 do
            image_content = Enum.map(images, fn image ->
              %{
                "type" => "image",
                "source" => %{
                  "type" => "base64",
                  "media_type" => image["media_type"] || "image/jpeg",
                  "data" => image["data"]
                }
              }
            end)
            
            # Combine text and image content
            %{msg | "content" => [
              %{"type" => "text", "text" => content}
              | image_content
            ]}
          else
            msg
          end
          
        other -> other
      end
    end)
  end
end