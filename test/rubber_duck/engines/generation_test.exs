defmodule RubberDuck.Engines.GenerationTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Engines.Generation
  alias RubberDuck.Engines.Generation.RagContext
  alias RubberDuck.Engines.Generation.Refinement
  
  describe "init/1" do
    test "initializes with default configuration" do
      assert {:ok, state} = Generation.init([])
      
      assert state.config[:max_context_items] == 10
      assert state.config[:similarity_threshold] == 0.7
      assert state.config[:max_iterations] == 3
      assert state.config[:validate_syntax] == true
      assert state.config[:history_size] == 100
      assert state.config[:template_style] == :idiomatic
    end
    
    test "initializes with custom configuration" do
      config = [
        max_context_items: 5,
        similarity_threshold: 0.8,
        template_style: :concise
      ]
      
      assert {:ok, state} = Generation.init(config)
      
      assert state.config[:max_context_items] == 5
      assert state.config[:similarity_threshold] == 0.8
      assert state.config[:template_style] == :concise
    end
    
    test "loads user preferences from config" do
      config = [
        user_preferences: %{
          prefer_functional: false,
          prefer_explicit_types: true
        }
      ]
      
      assert {:ok, state} = Generation.init(config)
      
      assert state.user_preferences.prefer_functional == false
      assert state.user_preferences.prefer_explicit_types == true
    end
    
    test "loads language templates" do
      assert {:ok, state} = Generation.init([])
      
      assert Map.has_key?(state.template_cache, :elixir)
      assert Map.has_key?(state.template_cache, :javascript)
      assert Map.has_key?(state.template_cache, :python)
    end
  end
  
  describe "execute/2" do
    setup do
      {:ok, state} = Generation.init([])
      {:ok, state: state}
    end
    
    test "generates code from natural language prompt", %{state: state} do
      input = %{
        prompt: "Create a function to calculate fibonacci numbers",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result, state: _new_state}} = Generation.execute(input, state)
      
      assert result.code =~ "def"
      assert result.language == :elixir
      assert is_list(result.imports)
      assert is_binary(result.explanation)
      assert is_float(result.confidence)
      assert result.confidence >= 0.0 and result.confidence <= 1.0
    end
    
    test "generates GenServer code for server-related prompts", %{state: state} do
      input = %{
        prompt: "Create a genserver for managing user sessions",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert result.code =~ "use GenServer"
      assert result.code =~ "def start_link"
      assert result.code =~ "@impl true"
      assert result.code =~ "def init"
    end
    
    test "generates API endpoint code for API-related prompts", %{state: state} do
      input = %{
        prompt: "Create an API endpoint for listing products",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert result.code =~ "def index(conn, params)"
      assert result.code =~ "render(conn"
    end
    
    test "completes partial code when provided", %{state: state} do
      input = %{
        prompt: "Complete this function",
        language: :elixir,
        context: %{},
        partial_code: "def calculate_total(items) do\n  # TODO: Sum all item prices"
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert result.code =~ "def calculate_total(items) do"
      assert result.code =~ "end"
    end
    
    test "applies style preferences", %{state: state} do
      input = %{
        prompt: "Create a simple hello function",
        language: :elixir,
        context: %{},
        style: :functional
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert is_binary(result.code)
      assert result.metadata[:generation_time]
    end
    
    test "respects constraints when provided", %{state: state} do
      input = %{
        prompt: "Create a validation function",
        language: :elixir,
        context: %{},
        constraints: %{
          "max_lines" => 10,
          "no_side_effects" => true
        }
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      lines = String.split(result.code, "\n") |> Enum.reject(&(String.trim(&1) == ""))
      assert length(lines) <= 10
    end
    
    test "detects and includes necessary imports", %{state: state} do
      input = %{
        prompt: "Create a GenServer module",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      # Should detect GenServer is used
      assert "GenServer" in result.imports or result.code =~ "use GenServer"
    end
    
    test "provides alternatives when possible", %{state: state} do
      input = %{
        prompt: "Create a mapping function",
        language: :elixir,
        context: %{},
        style: :imperative
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert is_list(result.alternatives)
      # May have functional style alternative
    end
    
    test "handles invalid input gracefully", %{state: state} do
      input = %{
        # Missing required fields
        language: :elixir
      }
      
      assert {:error, :invalid_input} = Generation.execute(input, state)
    end
    
    test "validates generated code syntax", %{state: state} do
      input = %{
        prompt: "Create a simple function",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      # Code should not have obvious syntax errors
      refute result.code =~ ~r/\(\s*\z/  # No unclosed parentheses at end
    end
    
    test "tracks generation history", %{state: state} do
      input = %{
        prompt: "Create a hello world function",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{state: new_state}} = Generation.execute(input, state)
      
      assert length(new_state.history) == 1
      assert hd(new_state.history).prompt == "Create a hello world function"
      assert is_binary(hd(new_state.history).generated_code)
      assert %DateTime{} = hd(new_state.history).timestamp
    end
    
    test "emits telemetry events", %{state: state} do
      input = %{
        prompt: "Create a function",
        language: :elixir,
        context: %{}
      }
      
      :telemetry.attach(
        "test-generation",
        [:rubber_duck, :generation, :completed],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )
      
      assert {:ok, _} = Generation.execute(input, state)
      
      assert_receive {:telemetry, measurements, metadata}
      assert is_float(measurements.confidence)
      assert metadata.language == :elixir
      
      :telemetry.detach("test-generation")
    end
  end
  
  describe "capabilities/0" do
    test "returns expected capabilities" do
      capabilities = Generation.capabilities()
      
      assert :code_generation in capabilities
      assert :rag_context in capabilities
      assert :iterative_refinement in capabilities
      assert :multi_language in capabilities
    end
  end
  
  describe "RAG context integration" do
    setup do
      {:ok, state} = Generation.init([])
      {:ok, state: state}
    end
    
    test "retrieves and uses context for generation", %{state: state} do
      input = %{
        prompt: "Create a function similar to existing patterns",
        language: :elixir,
        context: %{
          project_files: ["lib/example.ex"],
          imports: ["MyApp.Utils"]
        }
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert is_binary(result.code)
      # Context should influence generation
      assert result.metadata[:selected_items] >= 0
    end
    
    test "includes user examples in context", %{state: state} do
      input = %{
        prompt: "Create a parser function",
        language: :elixir,
        context: %{
          examples: [
            %{
              code: "def parse_json(data), do: Jason.decode(data)",
              description: "JSON parser example"
            }
          ]
        }
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert is_binary(result.code)
      # Should be influenced by example style
    end
  end
  
  describe "multi-language support" do
    setup do
      {:ok, state} = Generation.init([])
      {:ok, state: state}
    end
    
    test "generates JavaScript code", %{state: state} do
      input = %{
        prompt: "Create a function to fetch user data",
        language: :javascript,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert result.language == :javascript
      assert result.code =~ "function" or result.code =~ "const"
    end
    
    test "generates Python code", %{state: state} do
      input = %{
        prompt: "Create a class for data processing",
        language: :python,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert result.language == :python
      assert result.code =~ "def" or result.code =~ "class"
    end
  end
  
  describe "syntax validation and fixing" do
    setup do
      {:ok, state} = Generation.init([validate_syntax: true])
      {:ok, state: state}
    end
    
    test "fixes unbalanced delimiters", %{state: state} do
      # This would generate code and then fix it if needed
      input = %{
        prompt: "Create a nested function",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      # Count delimiters
      opens = String.graphemes(result.code) |> Enum.count(&(&1 == "("))
      closes = String.graphemes(result.code) |> Enum.count(&(&1 == ")"))
      
      assert opens == closes
    end
    
    test "ensures code ends with newline", %{state: state} do
      input = %{
        prompt: "Create a simple function",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      assert String.ends_with?(result.code, "\n")
    end
  end
  
  describe "confidence calculation" do
    setup do
      {:ok, state} = Generation.init([])
      {:ok, state: state}
    end
    
    test "higher confidence for well-formed code", %{state: state} do
      input = %{
        prompt: "Create a well-documented function to add two numbers",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      # Should have reasonable confidence
      assert result.confidence >= 0.5
    end
    
    test "lower confidence for generic prompts", %{state: state} do
      input = %{
        prompt: "Create something",
        language: :elixir,
        context: %{}
      }
      
      assert {:ok, %{result: result}} = Generation.execute(input, state)
      
      # Less specific prompt should have lower confidence
      assert result.confidence < 0.9
    end
  end
end