defmodule RubberDuck.LLM.Providers.Mock do
  @moduledoc """
  Mock provider for testing and development.

  This provider returns predetermined responses without making
  actual API calls. Useful for:
  - Unit testing
  - Development without API keys
  - Simulating various response scenarios
  """

  @behaviour RubberDuck.LLM.Provider

  alias RubberDuck.LLM.{Request, Response, ProviderConfig}

  @impl true
  def execute(%Request{} = request, %ProviderConfig{} = config) do
    # Simulate some processing time
    if config.options[:simulate_delay] do
      Process.sleep(Enum.random(100..500))
    end

    # Check if we should simulate an error
    case config.options[:simulate_error] do
      nil ->
        generate_success_response(request, config)

      error_type ->
        {:error, error_type}
    end
  end

  @impl true
  def validate_config(%ProviderConfig{} = _config) do
    # Mock provider doesn't need any specific configuration
    :ok
  end

  @impl true
  def info do
    %{
      name: "Mock Provider",
      models: [
        %{
          id: "mock-fast",
          context_window: 4096,
          max_output: 1024
        },
        %{
          id: "mock-smart",
          context_window: 8192,
          max_output: 2048
        },
        %{
          id: "mock-vision",
          context_window: 4096,
          max_output: 1024,
          supports_vision: true
        }
      ],
      features: [:streaming, :function_calling, :system_messages, :json_mode, :vision]
    }
  end

  @impl true
  def supports_feature?(_feature) do
    # Mock provider "supports" all features
    true
  end

  @impl true
  def count_tokens(text, _model) when is_binary(text) do
    # Simple word-based estimation
    words = String.split(text, ~r/\s+/)
    {:ok, length(words)}
  end

  def count_tokens(messages, model) when is_list(messages) do
    total =
      Enum.reduce(messages, 0, fn message, acc ->
        content = message["content"] || ""
        {:ok, tokens} = count_tokens(content, model)
        acc + tokens
      end)

    {:ok, total}
  end

  @impl true
  def health_check(%ProviderConfig{} = config) do
    if config.options[:health_status] == :unhealthy do
      {:error, :unhealthy}
    else
      {:ok, %{status: :healthy, timestamp: DateTime.utc_now()}}
    end
  end

  # Private functions

  defp generate_success_response(request, config) do
    response_content =
      case config.options[:response_template] do
        nil ->
          generate_default_response(request)

        template when is_function(template) ->
          template.(request)

        template when is_binary(template) ->
          template
      end

    response = %{
      "id" => "mock_" <> generate_id(),
      "object" => "chat.completion",
      "created" => DateTime.to_unix(DateTime.utc_now()),
      "model" => request.model,
      "choices" => [
        %{
          "index" => 0,
          "message" => %{
            "role" => "assistant",
            "content" => response_content
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => %{
        "prompt_tokens" => Enum.random(10..100),
        "completion_tokens" => Enum.random(10..50),
        "total_tokens" => Enum.random(20..150)
      }
    }

    {:ok, Response.from_provider(:mock, response)}
  end

  defp generate_default_response(request) do
    last_message = List.last(request.messages)
    user_input = last_message["content"] || last_message[:content] || ""

    cond do
      String.contains?(user_input, "hello") ->
        "Hello! I'm a mock LLM provider. How can I help you today?"

      String.contains?(user_input, "code") ->
        """
        Here's a simple function:

        ```elixir
        def example_function(input) do
          # This is a mock response
          {:ok, "Processed: \#{input}"}
        end
        ```
        """

      String.contains?(user_input, "error") ->
        "I understand you're asking about errors. This is a mock response for testing purposes."

      true ->
        "This is a mock response to: #{String.slice(user_input, 0, 50)}..."
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
