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
        },
        %{
          id: "codellama",
          context_window: 8192,
          max_output: 4096
        },
        %{
          id: "llama2",
          context_window: 4096,
          max_output: 2048
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

  @impl true
  def connect(%ProviderConfig{} = config) do
    # Simulate connection behavior
    case config.options[:connection_behavior] do
      :fail ->
        {:error, :connection_refused}

      :timeout ->
        Process.sleep(5000)
        {:error, :timeout}

      _ ->
        # Successful connection
        connection_data = %{
          connected_at: DateTime.utc_now(),
          session_id: generate_id(),
          state: :connected
        }

        {:ok, connection_data}
    end
  end

  @impl true
  def disconnect(_config, connection_data) do
    # Log disconnection for testing
    if connection_data[:session_id] do
      :ok
    else
      {:error, :not_connected}
    end
  end

  @impl true
  def health_check(%ProviderConfig{} = config, connection_data) do
    cond do
      config.options[:health_status] == :unhealthy ->
        {:error, :unhealthy}

      connection_data[:state] != :connected ->
        {:error, :not_connected}

      true ->
        {:ok,
         %{
           status: :healthy,
           timestamp: DateTime.utc_now(),
           session_id: connection_data[:session_id]
         }}
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
      # Handle refactoring requests
      String.contains?(user_input, "refactor") or String.contains?(user_input, "rename") ->
        generate_refactoring_response(user_input)

      # Handle test generation requests
      String.contains?(user_input, "test") or String.contains?(user_input, "Generate comprehensive tests") ->
        generate_test_response(user_input)

      # Handle code completion requests
      String.contains?(user_input, "complete") or String.contains?(user_input, "Complete the following") ->
        generate_completion_response(user_input)

      # Handle general code generation
      String.contains?(user_input, "Generate") or String.contains?(user_input, "Create") ->
        generate_code_response(user_input)

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
  
  defp generate_refactoring_response(input) do
    cond do
      String.contains?(input, "rename") and String.contains?(input, "hello") ->
        """
        defmodule Test do
          def greet(name) do
            "Hello, \#{name}!"
          end
          
          def unused_function do
            :not_used
          end
        end
        """
        
      String.contains?(input, "documentation") ->
        """
        defmodule Test do
          @doc \"\"\"
          Greets a person by name.
          
          ## Examples
          
              iex> Test.hello("World")
              "Hello, World!"
          
          \"\"\"
          def hello(name) do
            "Hello, \#{name}!"
          end
          
          @doc \"\"\"
          This function is not used anywhere.
          \"\"\"
          def unused_function do
            :not_used
          end
        end
        """
        
      true ->
        # Default refactoring - return just the code without markdown markers
        "defmodule RefactoredModule do\n  def refactored_function do\n    :ok\n  end\nend"
    end
  end
  
  defp generate_test_response(input) do
    cond do
      String.contains?(input, "Test do") ->
        """
        defmodule TestTest do
          use ExUnit.Case
          doctest Test
          
          describe "hello/1" do
            test "greets with the given name" do
              assert Test.hello("World") == "Hello, World!"
            end
            
            test "handles empty string" do
              assert Test.hello("") == "Hello, !"
            end
          end
          
          describe "unused_function/0" do
            test "returns :not_used" do
              assert Test.unused_function() == :not_used
            end
          end
        end
        """
        
      true ->
        # Default test - return just the code without markdown markers
        """
        defmodule ModuleTest do
          use ExUnit.Case
          
          test "basic functionality" do
            assert true
          end
        end
        """
    end
  end
  
  defp generate_completion_response(_input) do
    # Return just the code without markdown markers
    """
    def completed_function(args) do
      args
      |> process_args()
      |> handle_result()
    end
    
    defp process_args(args) do
      # Process the arguments
      {:ok, args}
    end
    
    defp handle_result({:ok, result}) do
      {:ok, result}
    end
    defp handle_result({:error, reason}) do
      {:error, reason}
    end
    """
  end
  
  defp generate_code_response(input) do
    cond do
      String.contains?(input, "GenServer") or String.contains?(input, "counter") ->
        # Return just the code without markdown markers
        """
        defmodule Counter do
          use GenServer
          
          # Client API
          
          def start_link(initial_value \\\\ 0) do
            GenServer.start_link(__MODULE__, initial_value, name: __MODULE__)
          end
          
          def increment do
            GenServer.call(__MODULE__, :increment)
          end
          
          def get_value do
            GenServer.call(__MODULE__, :get_value)
          end
          
          # Server Callbacks
          
          @impl true
          def init(initial_value) do
            {:ok, initial_value}
          end
          
          @impl true
          def handle_call(:increment, _from, state) do
            new_state = state + 1
            {:reply, new_state, new_state}
          end
          
          @impl true
          def handle_call(:get_value, _from, state) do
            {:reply, state, state}
          end
        end
        """
        
      String.contains?(input, "add") and String.contains?(input, "numbers") ->
        # Return just the code without markdown markers
        "def add(a, b) when is_number(a) and is_number(b) do\n  a + b\nend"
        
      true ->
        # Default code generation - return just the code without markdown markers
        "def generated_function do\n  # Generated based on: #{String.slice(input, 0, 50)}\n  :ok\nend"
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
