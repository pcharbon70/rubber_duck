defmodule RubberDuck.Tools.CodeFormatterTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.CodeFormatter
  
  describe "tool definition" do
    test "has correct metadata" do
      assert CodeFormatter.name() == :code_formatter
      
      metadata = CodeFormatter.metadata()
      assert metadata.name == :code_formatter
      assert metadata.description == "Formats Elixir code using standard formatter rules"
      assert metadata.category == :code_quality
      assert metadata.version == "1.0.0"
      assert :formatting in metadata.tags
      assert :quality in metadata.tags
    end
    
    test "has required parameters" do
      params = CodeFormatter.parameters()
      
      code_param = Enum.find(params, &(&1.name == :code))
      assert code_param.required == true
      assert code_param.type == :string
      
      line_length_param = Enum.find(params, &(&1.name == :line_length))
      assert line_length_param.default == 98
      assert line_length_param.constraints[:min] == 40
      assert line_length_param.constraints[:max] == 200
    end
    
    test "has formatting options" do
      params = CodeFormatter.parameters()
      
      assert Enum.find(params, &(&1.name == :locals_without_parens))
      assert Enum.find(params, &(&1.name == :force_do_end_blocks))
      assert Enum.find(params, &(&1.name == :normalize_bitstring_modifiers))
      assert Enum.find(params, &(&1.name == :normalize_charlists))
    end
  end
  
  describe "basic formatting" do
    test "formats simple function" do
      code = """
      def hello( name ) do
      "Hello, " <> name
      end
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.changed == true
      assert result.formatted_code =~ ~r/def hello\(name\) do/
    end
    
    test "preserves semantics" do
      code = """
      def   add(a,b),   do:   a+b
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.changed == true
      assert result.formatted_code =~ ~r/def add\(a, b\), do: a \+ b/
    end
    
    test "handles already formatted code" do
      code = """
      def hello(name) do
        "Hello, " <> name
      end
      """
      
      params = %{
        code: String.trim(code),
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.changed == false
    end
  end
  
  describe "line length" do
    test "respects custom line length" do
      code = """
      def very_long_function_name_that_exceeds_line_length(first_parameter, second_parameter, third_parameter) do
        :ok
      end
      """
      
      params = %{
        code: code,
        line_length: 80,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.changed == true
      # Function signature should be split across lines
      assert String.split(result.formatted_code, "\n") |> length() > 3
    end
  end
  
  describe "locals without parens" do
    test "formats specified locals without parentheses" do
      code = """
      defmodule Test do
        my_dsl(:foo)
        my_dsl(:bar, :baz)
      end
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: ["my_dsl:1", "my_dsl:2"],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.formatted_code =~ ~r/my_dsl :foo/
      assert result.formatted_code =~ ~r/my_dsl :bar, :baz/
    end
  end
  
  describe "charlists normalization" do
    test "normalizes charlists to sigils" do
      code = """
      list = 'hello'
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.formatted_code =~ ~r/~c"hello"/
    end
    
    test "preserves charlists when normalization disabled" do
      code = """
      list = 'hello'
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: false,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.formatted_code =~ ~r/'hello'/
    end
  end
  
  describe "error handling" do
    test "handles syntax errors" do
      code = """
      def broken(
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:error, message} = CodeFormatter.execute(params, %{})
      assert message =~ ~r/Syntax error/
    end
  end
  
  describe "analysis" do
    test "detects formatting issues" do
      code = """
      def hello( name )  do\t
        "Hello, " <>name  
      end
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert :tabs_used in result.analysis.formatting_issues
      assert :trailing_whitespace in result.analysis.formatting_issues
      assert :inconsistent_parentheses_spacing in result.analysis.formatting_issues
    end
    
    test "tracks improvements" do
      code = """
      def hello( name )  do  
        "Hello, " <>name  
      end  
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert :removed_trailing_whitespace in result.analysis.improvements
    end
    
    test "counts changed lines" do
      code = """
      def hello( name ) do
      "Hello, " <> name
      end
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      assert result.analysis.lines_changed > 0
      assert result.analysis.original_line_count == 3
    end
  end
  
  describe "equivalence checking" do
    test "verifies semantic equivalence" do
      code = """
      def calculate(x, y) do
        x * y + 10
      end
      """
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: true,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, result} = CodeFormatter.execute(params, %{})
      # Should succeed as formatting preserves semantics
      assert result.formatted_code
    end
    
    test "skips equivalence check when disabled" do
      code = "def test, do: :ok"
      
      params = %{
        code: code,
        line_length: 98,
        locals_without_parens: [],
        force_do_end_blocks: false,
        normalize_bitstring_modifiers: true,
        normalize_charlists: true,
        check_equivalent: false,
        file_path: nil,
        use_project_formatter: false
      }
      
      {:ok, _result} = CodeFormatter.execute(params, %{})
      # Should succeed without checking
    end
  end
end