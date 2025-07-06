defmodule RubberDuck.SelfCorrection.StrategyTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.SelfCorrection.Strategies.{Syntax, Semantic, Logic}
  
  describe "Syntax Strategy" do
    test "detects unmatched delimiters" do
      content = "def hello do\n  'world'"
      
      result = Syntax.analyze(content, :code, %{language: "elixir"}, %{})
      
      assert result.strategy == :syntax
      assert length(result.issues) > 0
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :unmatched_delimiter
      end)
    end
    
    test "detects syntax errors in Elixir" do
      content = """
      defmodule Test do
        def broken(x do
          x + 1
        end
      end
      """
      
      result = Syntax.analyze(content, :code, %{language: "elixir"}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :syntax_error
      end)
    end
    
    test "handles mixed content" do
      content = """
      # Code Example
      
      ```elixir
      def hello do
        "world"
      ```
      """
      
      result = Syntax.analyze(content, :mixed, %{}, %{})
      
      assert result.strategy == :syntax
      assert length(result.issues) > 0  # Missing 'end' in code block
    end
    
    test "validates corrections" do
      content = "def test, do: 1"
      correction = %{
        changes: [%{action: :replace, target: ",", replacement: ""}],
        metadata: %{language: "elixir"}
      }
      
      assert {:ok, _} = Syntax.validate_correction(content, correction)
    end
  end
  
  describe "Semantic Strategy" do
    test "detects poor variable naming" do
      content = """
      def calculate(a, b, c) do
        d = a + b
        e = d * c
        e
      end
      """
      
      result = Semantic.analyze(content, :code, %{language: "elixir"}, %{})
      
      assert result.strategy == :semantic
      assert Enum.any?(result.issues, fn issue ->
        issue.type in [:poor_variable_naming, :vague_variable_name]
      end)
    end
    
    test "detects long sentences in text" do
      content = "This is an extremely long sentence that continues on and on without any breaks or pauses making it very difficult for readers to follow the train of thought and understand what the main point is supposed to be."
      
      result = Semantic.analyze(content, :text, %{}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :long_sentences
      end)
    end
    
    test "detects excessive TODOs" do
      content = """
      # TODO: Fix this
      # TODO: Implement that
      # FIXME: Handle errors
      # TODO: Add tests
      # TODO: Refactor
      def incomplete() do
        # TODO: Actually implement
        nil
      end
      """
      
      result = Semantic.analyze(content, :code, %{}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :excessive_todos
      end)
    end
    
    test "suggests corrections for semantic issues" do
      content = "The thing does stuff."
      
      result = Semantic.analyze(content, :text, %{}, %{low_clarity: true})
      
      assert length(result.corrections) > 0
      assert result.corrections != []
    end
  end
  
  describe "Logic Strategy" do
    test "detects constant conditions" do
      content = """
      if true do
        "always"
      else
        "never"
      end
      """
      
      result = Logic.analyze(content, :code, %{language: "elixir"}, %{})
      
      assert result.strategy == :logic
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :constant_condition
      end)
    end
    
    test "detects impossible conditions" do
      content = "if x && !x, do: 'impossible'"
      
      result = Logic.analyze(content, :code, %{}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :impossible_condition
      end)
    end
    
    test "detects tautologies" do
      content = "if x || !x, do: 'always true'"
      
      result = Logic.analyze(content, :code, %{}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :tautology
      end)
    end
    
    test "detects unhandled errors in Elixir" do
      content = """
      def risky_operation(data) do
        {:error, "Something went wrong"}
      end
      
      def caller() do
        result = risky_operation("data")
        process(result)
      end
      """
      
      result = Logic.analyze(content, :code, %{language: "elixir"}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :unhandled_errors
      end)
    end
    
    test "detects weak arguments in text" do
      content = "This is obviously the best solution. Clearly, everyone agrees. It's definitely perfect."
      
      result = Logic.analyze(content, :text, %{}, %{})
      
      assert Enum.any?(result.issues, fn issue ->
        issue.type == :unsupported_claims
      end)
    end
    
    test "generates corrections for logic issues" do
      content = "if true do 'x' else 'y' end"
      
      result = Logic.analyze(content, :code, %{}, %{})
      
      assert length(result.corrections) > 0
      assert Enum.any?(result.corrections, fn correction ->
        correction.type in [:simplify_condition, :fix_impossible_condition]
      end)
    end
  end
  
  describe "Strategy priorities" do
    test "strategies have correct priorities" do
      assert Syntax.priority() == 100   # Highest - syntax first
      assert Logic.priority() == 90     # High - logic critical
      assert Semantic.priority() == 80  # Medium - semantics important
    end
  end
  
  describe "Strategy support" do
    test "strategies support correct content types" do
      assert :code in Syntax.supported_types()
      assert :mixed in Syntax.supported_types()
      
      assert :code in Semantic.supported_types()
      assert :text in Semantic.supported_types()
      assert :mixed in Semantic.supported_types()
      
      assert :code in Logic.supported_types()
      assert :text in Logic.supported_types()
      assert :mixed in Logic.supported_types()
    end
  end
end