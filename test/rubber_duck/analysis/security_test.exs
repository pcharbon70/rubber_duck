defmodule RubberDuck.Analysis.SecurityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analysis.Security

  setup do
    ast_info = %{
      type: :module,
      name: TestModule,
      functions: [
        %{name: :process_input, arity: 1, line: 5, private: false},
        %{name: :admin_only, arity: 0, line: 10, private: false}
      ],
      aliases: [],
      imports: [],
      requires: [],
      calls: [
        %{from: {TestModule, :process_input, 1}, to: {String, :to_atom, 1}, line: 6},
        %{from: {TestModule, :admin_only, 0}, to: {Code, :eval_string, 1}, line: 11},
        %{from: {TestModule, :process_input, 1}, to: {System, :cmd, 2}, line: 7}
      ],
      metadata: %{}
    }

    {:ok, ast_info: ast_info}
  end

  describe "analyze/2" do
    test "detects dynamic atom creation", %{ast_info: ast_info} do
      {:ok, result} = Security.analyze(ast_info)

      atom_issues = Enum.filter(result.issues, &(&1.type == :dynamic_atom_creation))
      assert length(atom_issues) == 1

      issue = hd(atom_issues)
      assert issue.severity == :high
      assert issue.message =~ "memory exhaustion"
      assert issue.category == :security
    end

    test "detects unsafe operations", %{ast_info: ast_info} do
      {:ok, result} = Security.analyze(ast_info)

      unsafe_issues = Enum.filter(result.issues, &(&1.type == :unsafe_operation))
      # eval_string and System.cmd
      assert length(unsafe_issues) == 2

      # Check for critical eval_string
      eval_issue =
        Enum.find(unsafe_issues, fn issue ->
          issue.metadata.function == :eval_string
        end)

      assert eval_issue.severity == :critical

      # Check for high System.cmd
      cmd_issue =
        Enum.find(unsafe_issues, fn issue ->
          issue.metadata.function == :cmd
        end)

      assert cmd_issue.severity == :high
    end

    test "detects unsupervised processes" do
      ast_with_spawn = %{
        type: :module,
        name: SpawnModule,
        functions: [],
        aliases: [],
        imports: [],
        requires: [],
        calls: [
          %{from: {SpawnModule, :start, 0}, to: {Kernel, :spawn, 1}, line: 5},
          %{from: {SpawnModule, :start, 0}, to: {Task, :async, 1}, line: 10}
        ],
        metadata: %{}
      }

      {:ok, result} = Security.analyze(ast_with_spawn)

      process_issues = Enum.filter(result.issues, &(&1.type == :unsupervised_process))
      assert length(process_issues) == 2

      # Task.async is less severe
      task_issue =
        Enum.find(process_issues, fn issue ->
          issue.metadata.spawn_function =~ "Task"
        end)

      assert task_issue.severity == :low
    end

    test "calculates security metrics", %{ast_info: ast_info} do
      {:ok, result} = Security.analyze(ast_info)

      assert result.metrics.total_issues > 0
      assert result.metrics.critical_issues >= 1
      assert result.metrics.high_risk_calls >= 2
      assert result.metrics.security_score < 100
      assert result.metrics.uses_unsafe_functions == true
    end

    test "generates security suggestions", %{ast_info: ast_info} do
      {:ok, result} = Security.analyze(ast_info)

      assert map_size(result.suggestions) > 0

      # Check dynamic atom suggestions
      atom_suggestions = result.suggestions[:dynamic_atom_creation]
      assert length(atom_suggestions) >= 1
      assert Enum.any?(atom_suggestions, &(&1.description =~ "to_existing_atom"))
    end
  end

  describe "analyze_source/3" do
    test "detects hardcoded secrets" do
      source = """
      defmodule Config do
        @api_key "sk_live_123456789abcdef"
        @password "super_secret_password"
        
        def get_token do
          "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        end
      end
      """

      {:ok, result} = Security.analyze_source(source, :elixir, [])

      secret_issues = Enum.filter(result.issues, &(&1.type == :hardcoded_secret))
      assert length(secret_issues) >= 2
      assert Enum.all?(secret_issues, &(&1.severity == :critical))
    end

    test "detects unsafe patterns in source" do
      source = """
      defmodule Unsafe do
        def execute(code) do
          Code.eval_string(code)
        end
        
        def run_command(cmd) do
          System.cmd(cmd, [])
        end
      end
      """

      {:ok, result} = Security.analyze_source(source, :elixir, [])

      unsafe_patterns = Enum.filter(result.issues, &(&1.type == :unsafe_pattern))
      assert length(unsafe_patterns) >= 2
    end

    test "detects security-related comments" do
      source = """
      defmodule Example do
        # SECURITY: This needs review
        def process(input) do
          # TODO: Add security validation
          # FIXME: Potential vulnerability here
          input
        end
      end
      """

      {:ok, result} = Security.analyze_source(source, :elixir, [])

      comment_issues = Enum.filter(result.issues, &(&1.type == :security_comment))
      assert length(comment_issues) >= 2
      assert Enum.all?(comment_issues, &(&1.severity == :low))
    end
  end

  describe "SQL injection detection" do
    test "flags Ecto query operations for review" do
      ast_info = %{
        type: :module,
        name: QueryModule,
        functions: [],
        aliases: [],
        imports: [],
        requires: [],
        calls: [
          %{from: {QueryModule, :search, 1}, to: {Ecto.Query, :from, 2}, line: 5},
          %{from: {QueryModule, :search, 1}, to: {Ecto.Adapters.SQL, :query, 3}, line: 10}
        ],
        metadata: %{}
      }

      {:ok, result} = Security.analyze(ast_info)

      sql_issues = Enum.filter(result.issues, &(&1.type == :potential_sql_injection))
      assert length(sql_issues) == 2
      assert Enum.all?(sql_issues, &(&1.severity == :medium))
    end
  end

  describe "XSS detection" do
    test "detects Phoenix.HTML.raw usage" do
      ast_info = %{
        type: :module,
        name: ViewModel,
        functions: [],
        aliases: [],
        imports: [],
        requires: [],
        calls: [
          %{from: {ViewModel, :render, 1}, to: {Phoenix.HTML, :raw, 1}, line: 5}
        ],
        metadata: %{}
      }

      {:ok, result} = Security.analyze(ast_info)

      xss_issues = Enum.filter(result.issues, &(&1.type == :potential_xss))
      assert length(xss_issues) == 1
      assert hd(xss_issues).severity == :high
    end
  end

  describe "configuration" do
    test "respects configuration options", %{ast_info: ast_info} do
      config = %{
        detect_dynamic_atoms: false,
        detect_unsafe_operations: false
      }

      {:ok, result} = Security.analyze(ast_info, config: config)

      # Should not detect disabled checks
      atom_issues = Enum.filter(result.issues, &(&1.type == :dynamic_atom_creation))
      unsafe_issues = Enum.filter(result.issues, &(&1.type == :unsafe_operation))

      assert Enum.empty?(atom_issues)
      assert Enum.empty?(unsafe_issues)
    end
  end
end
