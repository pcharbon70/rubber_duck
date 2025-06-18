defmodule RubberDuck.CodingAssistant.Engines.ExplanationTypesTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.CodingAssistant.Engines.ExplanationTypes
  
  @sample_elixir_code """
  defmodule Calculator do
    def add(a, b) do
      a + b
    end
    
    def multiply(a, b) do
      a * b
    end
  end
  """
  
  @sample_javascript_code """
  function calculateTotal(items) {
    return items.reduce((sum, item) => sum + item.price, 0);
  }
  """
  
  describe "available_types/0" do
    test "returns all expected explanation types" do
      types = ExplanationTypes.available_types()
      
      expected_types = [:summary, :detailed, :step_by_step, :architectural, :documentation]
      
      assert Enum.sort(types) == Enum.sort(expected_types)
    end
  end
  
  describe "get_type_metadata/1" do
    test "returns metadata for valid explanation type" do
      metadata = ExplanationTypes.get_type_metadata(:summary)
      
      assert metadata.name == "Summary"
      assert metadata.description =~ "Brief overview"
      assert metadata.max_length == 500
      assert metadata.complexity == :low
      assert metadata.target_audience == :general
    end
    
    test "returns nil for invalid explanation type" do
      assert ExplanationTypes.get_type_metadata(:invalid_type) == nil
    end
    
    test "returns correct metadata for all types" do
      types = ExplanationTypes.available_types()
      
      Enum.each(types, fn type ->
        metadata = ExplanationTypes.get_type_metadata(type)
        
        assert is_map(metadata)
        assert Map.has_key?(metadata, :name)
        assert Map.has_key?(metadata, :description)
        assert Map.has_key?(metadata, :max_length)
        assert Map.has_key?(metadata, :complexity)
        assert Map.has_key?(metadata, :target_audience)
      end)
    end
  end
  
  describe "build_prompt/4" do
    test "builds summary prompt correctly" do
      prompt = ExplanationTypes.build_prompt(:summary, @sample_elixir_code, :elixir)
      
      assert String.contains?(prompt, "concise summary")
      assert String.contains?(prompt, "elixir")
      assert String.contains?(prompt, @sample_elixir_code)
      assert String.contains?(prompt, "3-4 sentences")
    end
    
    test "builds detailed prompt correctly" do
      prompt = ExplanationTypes.build_prompt(:detailed, @sample_elixir_code, :elixir)
      
      assert String.contains?(prompt, "comprehensive explanation")
      assert String.contains?(prompt, "Purpose")
      assert String.contains?(prompt, "Components")
      assert String.contains?(prompt, "Data Flow")
      assert String.contains?(prompt, @sample_elixir_code)
    end
    
    test "builds step-by-step prompt correctly" do
      prompt = ExplanationTypes.build_prompt(:step_by_step, @sample_elixir_code, :elixir)
      
      assert String.contains?(prompt, "step-by-step walkthrough")
      assert String.contains?(prompt, "line number")
      assert String.contains?(prompt, "learning elixir")
      # Should contain numbered lines
      assert String.contains?(prompt, "1:")
      assert String.contains?(prompt, "2:")
    end
    
    test "builds architectural prompt correctly" do
      prompt = ExplanationTypes.build_prompt(:architectural, @sample_elixir_code, :elixir)
      
      assert String.contains?(prompt, "architectural patterns")
      assert String.contains?(prompt, "Design Patterns")
      assert String.contains?(prompt, "Architecture")
      assert String.contains?(prompt, "Trade-offs")
    end
    
    test "builds documentation prompt correctly" do
      prompt = ExplanationTypes.build_prompt(:documentation, @sample_elixir_code, :elixir)
      
      assert String.contains?(prompt, "comprehensive documentation")
      assert String.contains?(prompt, "Overview")
      assert String.contains?(prompt, "Usage")
      assert String.contains?(prompt, "Parameters")
      assert String.contains?(prompt, "Examples")
    end
    
    test "includes context information when provided" do
      context = %{
        symbols: ["Calculator", "add", "multiply"],
        structure: %{functions: 2, modules: 1}
      }
      
      prompt = ExplanationTypes.build_prompt(:detailed, @sample_elixir_code, :elixir, context)
      
      assert String.contains?(prompt, "Calculator")
      assert String.contains?(prompt, "functions: 2")
    end
    
    test "works with different programming languages" do
      languages = [:elixir, :javascript, :python, :rust]
      
      Enum.each(languages, fn language ->
        code = case language do
          :elixir -> @sample_elixir_code
          :javascript -> @sample_javascript_code
          _ -> "// Sample #{language} code"
        end
        
        prompt = ExplanationTypes.build_prompt(:summary, code, language)
        
        assert String.contains?(prompt, to_string(language))
        assert String.contains?(prompt, code)
      end)
    end
  end
  
  describe "format_output/3" do
    test "formats summary output correctly" do
      content = "This is a calculator module with two functions."
      metadata = %{language: :elixir, confidence: 0.9}
      
      formatted = ExplanationTypes.format_output(:summary, content, metadata)
      
      assert String.contains?(formatted, "## Summary")
      assert String.contains?(formatted, content)
      assert String.contains?(formatted, "Language: Elixir")
    end
    
    test "formats detailed output correctly" do
      content = "Detailed analysis of the calculator module..."
      metadata = %{language: :elixir, confidence: 0.85}
      
      formatted = ExplanationTypes.format_output(:detailed, content, metadata)
      
      assert String.contains?(formatted, "## Detailed Code Analysis")
      assert String.contains?(formatted, content)
      assert String.contains?(formatted, "Confidence: 85%")
    end
    
    test "formats step-by-step output correctly" do
      content = "Step 1: Define module\nStep 2: Add functions"
      metadata = %{language: :elixir}
      
      formatted = ExplanationTypes.format_output(:step_by_step, content, metadata)
      
      assert String.contains?(formatted, "## Step-by-Step Walkthrough")
      assert String.contains?(formatted, content)
      assert String.contains?(formatted, "Elixir Code Walkthrough")
    end
    
    test "formats architectural output correctly" do
      content = "This code follows the module pattern..."
      metadata = %{language: :elixir, complexity: "medium"}
      
      formatted = ExplanationTypes.format_output(:architectural, content, metadata)
      
      assert String.contains?(formatted, "## Architectural Analysis")
      assert String.contains?(formatted, content)
      assert String.contains?(formatted, "Complexity: medium")
    end
    
    test "formats documentation output correctly" do
      content = "# Calculator Module\n\nA simple calculator..."
      metadata = %{language: :elixir}
      
      formatted = ExplanationTypes.format_output(:documentation, content, metadata)
      
      assert String.contains?(formatted, "# Code Documentation")
      assert String.contains?(formatted, content)
      # Should contain current date
      current_date = Date.utc_today() |> Date.to_string()
      assert String.contains?(formatted, current_date)
    end
    
    test "handles missing metadata gracefully" do
      content = "Basic explanation"
      
      formatted = ExplanationTypes.format_output(:summary, content, %{})
      
      assert String.contains?(formatted, content)
      assert String.contains?(formatted, "Language: Code")  # Default fallback
    end
  end
  
  describe "suggest_type/3" do
    test "suggests summary for short code" do
      short_code = "def add(a, b), do: a + b"
      
      suggested = ExplanationTypes.suggest_type(short_code, :elixir)
      
      assert suggested == :summary
    end
    
    test "suggests step_by_step for beginner mode" do
      context = %{beginner_mode: true}
      
      suggested = ExplanationTypes.suggest_type(@sample_elixir_code, :elixir, context)
      
      assert suggested == :step_by_step
    end
    
    test "suggests architectural for complex code" do
      long_complex_code = String.duplicate(@sample_elixir_code, 10)
      
      suggested = ExplanationTypes.suggest_type(long_complex_code, :elixir)
      
      assert suggested == :architectural
    end
    
    test "suggests documentation for documentation mode" do
      context = %{documentation_mode: true}
      
      suggested = ExplanationTypes.suggest_type(@sample_elixir_code, :elixir, context)
      
      assert suggested == :documentation
    end
    
    test "suggests detailed as default for medium code" do
      medium_code = @sample_elixir_code
      
      suggested = ExplanationTypes.suggest_type(medium_code, :elixir)
      
      assert suggested == :detailed
    end
  end
  
  describe "prompt context formatting" do
    test "formats symbol information correctly" do
      context = %{symbols: ["Calculator", "add", "multiply", "divide", "subtract", "extra"]}
      
      prompt = ExplanationTypes.build_prompt(:detailed, @sample_elixir_code, :elixir, context)
      
      # Should include symbols but limit to 5
      assert String.contains?(prompt, "Calculator")
      assert String.contains?(prompt, "add")
      assert String.contains?(prompt, "multiply")
      # Should not exceed 5 symbols in the list
      symbol_lines = prompt |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "- "))
      assert length(symbol_lines) <= 5
    end
    
    test "formats structure information correctly" do
      context = %{
        structure: %{functions: 3, classes: 1, modules: 2}
      }
      
      prompt = ExplanationTypes.build_prompt(:detailed, @sample_elixir_code, :elixir, context)
      
      assert String.contains?(prompt, "functions: 3")
      assert String.contains?(prompt, "classes: 1")
      assert String.contains?(prompt, "modules: 2")
    end
    
    test "handles empty context gracefully" do
      prompt = ExplanationTypes.build_prompt(:detailed, @sample_elixir_code, :elixir, %{})
      
      assert is_binary(prompt)
      assert String.contains?(prompt, @sample_elixir_code)
      # Should not crash or include empty sections
      refute String.contains?(prompt, "Key Symbols Found:")
      refute String.contains?(prompt, "Code Structure:")
    end
  end
  
  describe "complexity estimation" do
    test "estimates low complexity for short code" do
      short_code = "def simple, do: :ok"
      
      # Test through suggest_type which uses complexity estimation
      suggested = ExplanationTypes.suggest_type(short_code, :elixir)
      
      assert suggested == :summary
    end
    
    test "estimates medium complexity for moderate code" do
      suggested = ExplanationTypes.suggest_type(@sample_elixir_code, :elixir)
      
      # Should not suggest architectural (high complexity) or summary (low complexity)
      assert suggested == :detailed
    end
    
    test "estimates high complexity for long code" do
      long_code = String.duplicate(@sample_elixir_code <> "\n", 10)
      
      suggested = ExplanationTypes.suggest_type(long_code, :elixir)
      
      assert suggested == :architectural
    end
  end
  
  describe "main purpose inference" do
    test "infers GenServer purpose for Elixir GenServer code" do
      genserver_code = """
      defmodule MyServer do
        use GenServer
        
        def start_link do
          GenServer.start_link(__MODULE__, [])
        end
      end
      """
      
      context = %{symbols: ["MyServer", "GenServer", "start_link"]}
      prompt = ExplanationTypes.build_prompt(:summary, genserver_code, :elixir, context)
      
      assert String.contains?(prompt, "GenServer implementation")
    end
    
    test "infers module purpose for Elixir module code" do
      context = %{symbols: ["Calculator", "defmodule"]}
      prompt = ExplanationTypes.build_prompt(:summary, @sample_elixir_code, :elixir, context)
      
      assert String.contains?(prompt, "Module definition")
    end
    
    test "infers test purpose for test code" do
      test_code = """
      defmodule CalculatorTest do
        use ExUnit.Case
        
        test "addition works" do
          assert Calculator.add(1, 2) == 3
        end
      end
      """
      
      context = %{symbols: ["test", "CalculatorTest"]}
      prompt = ExplanationTypes.build_prompt(:summary, test_code, :elixir, context)
      
      assert String.contains?(prompt, "Test implementation")
    end
    
    test "handles no specific purpose found" do
      generic_code = "x = 1 + 2"
      context = %{symbols: ["x"]}
      
      prompt = ExplanationTypes.build_prompt(:summary, generic_code, :elixir, context)
      
      # Should not crash and should include the code
      assert String.contains?(prompt, generic_code)
    end
  end
end