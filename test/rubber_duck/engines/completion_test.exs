defmodule RubberDuck.Engines.CompletionTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Engines.Completion
  alias RubberDuck.Engines.Completion.Incremental

  setup do
    {:ok, state} = Completion.init([])
    %{state: state}
  end

  describe "init/1" do
    test "initializes with default configuration" do
      {:ok, state} = Completion.init([])

      assert state.config[:max_suggestions] == 5
      assert state.config[:cache_ttl] == 300_000
      assert state.config[:min_confidence] == 0.5
      assert state.config[:context_window] == 50
      assert state.cache == %{}
      assert state.cache_expiry == %{}
    end

    test "initializes with custom configuration" do
      config = [
        max_suggestions: 10,
        cache_ttl: 600_000,
        min_confidence: 0.7
      ]

      {:ok, state} = Completion.init(config)

      assert state.config[:max_suggestions] == 10
      assert state.config[:cache_ttl] == 600_000
      assert state.config[:min_confidence] == 0.7
    end

    test "loads language rules" do
      {:ok, state} = Completion.init([])

      assert Map.has_key?(state.language_rules, :elixir)
      assert Map.has_key?(state.language_rules, :javascript)
      assert Map.has_key?(state.language_rules, :python)
    end
  end

  describe "capabilities/0" do
    test "returns expected capabilities" do
      capabilities = Completion.capabilities()

      assert :code_completion in capabilities
      assert :incremental_completion in capabilities
      assert :multi_suggestion in capabilities
    end
  end

  describe "execute/2 - basic completion" do
    test "generates completions for valid input", %{state: state} do
      input = %{
        prefix: "def get_",
        suffix: "\nend",
        language: :elixir,
        cursor_position: {1, 8}
      }

      {:ok, result} = Completion.execute(input, state)

      assert Map.has_key?(result, :completions)
      assert Map.has_key?(result, :state)
      assert is_list(result.completions)
      assert length(result.completions) > 0

      # Check completion structure
      [first | _] = result.completions
      assert Map.has_key?(first, :text)
      assert Map.has_key?(first, :score)
      assert Map.has_key?(first, :type)
      assert Map.has_key?(first, :metadata)
    end

    test "returns error for invalid input", %{state: state} do
      input = %{prefix: 123, suffix: nil}

      assert {:error, :invalid_input} = Completion.execute(input, state)
    end

    test "respects max_suggestions configuration" do
      {:ok, custom_state} = Completion.init(max_suggestions: 2)

      input = %{
        prefix: "def ",
        suffix: "\nend",
        language: :elixir,
        cursor_position: {1, 4}
      }

      {:ok, result} = Completion.execute(input, custom_state)

      assert length(result.completions) <= 2
    end

    test "filters by minimum confidence" do
      {:ok, custom_state} = Completion.init(min_confidence: 0.8)

      input = %{
        prefix: "def generic_",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 12}
      }

      {:ok, result} = Completion.execute(input, custom_state)

      # All completions should meet minimum confidence
      Enum.each(result.completions, fn completion ->
        assert completion.score >= 0.8
      end)
    end
  end

  describe "execute/2 - FIM context building" do
    test "builds FIM context correctly", %{state: state} do
      prefix = """
      defmodule Example do
        def hello(name) do
          IO.puts("Hello, \#{name}")
        end
        
        def get_users
      """

      suffix = """
        
        end
      end
      """

      input = %{
        prefix: prefix,
        suffix: suffix,
        language: :elixir,
        cursor_position: {6, 10}
      }

      {:ok, result} = Completion.execute(input, state)

      # Should generate function completions
      assert Enum.any?(result.completions, fn c -> c.type == :function end)
    end

    test "extracts cursor context properly", %{state: state} do
      input = %{
        prefix: "  def calculate_",
        suffix: "\n  end",
        language: :elixir,
        cursor_position: {1, 16}
      }

      {:ok, result} = Completion.execute(input, state)

      # Should have completions
      assert length(result.completions) > 0

      # Check indentation is considered
      completion = List.first(result.completions)
      assert completion.metadata != nil
    end
  end

  describe "execute/2 - language-specific completions" do
    test "generates Elixir-specific completions", %{state: state} do
      test_cases = [
        # Function completions
        %{
          prefix: "def get_",
          expected_texts: ["get_by_id(id)", "get_all()", "get_by(filters)"],
          expected_type: :function
        },
        # Pattern matching - with empty line after case do
        %{
          prefix: "case result do\n",
          expected_texts: ["{:ok, result} ->", "{:error, reason} ->", "_ ->"],
          expected_type: :pattern
        },
        # Module completions
        %{
          prefix: "MyApp.",
          expected_texts: ["MyApp.Module", "MyApp.Server"],
          expected_type: :module
        }
      ]

      Enum.each(test_cases, fn %{prefix: prefix, expected_texts: expected, expected_type: type} ->
        lines = String.split(prefix, "\n")
        line_count = length(lines)
        last_line_length = String.length(List.last(lines) || "")

        input = %{
          prefix: prefix,
          suffix: "",
          language: :elixir,
          cursor_position: {line_count, last_line_length}
        }

        {:ok, result} = Completion.execute(input, state)

        completion_texts = Enum.map(result.completions, & &1.text)

        # Check that at least one expected completion is present
        assert Enum.any?(expected, fn text -> text in completion_texts end)

        # Check type
        assert Enum.any?(result.completions, fn c -> c.type == type end)
      end)
    end

    test "applies Elixir language rules", %{state: state} do
      input = %{
        prefix: "def is_valid",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 12}
      }

      {:ok, result} = Completion.execute(input, state)

      # Should suggest predicate function pattern
      assert Enum.any?(result.completions, fn c ->
               String.contains?(c.text, "?")
             end)
    end
  end

  describe "execute/2 - caching" do
    test "caches completions for identical input", %{state: state} do
      input = %{
        prefix: "def test_",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 9}
      }

      # First execution
      {:ok, result1} = Completion.execute(input, state)
      updated_state = result1.state

      # Second execution with same input
      {:ok, result2} = Completion.execute(input, updated_state)

      # Should return same completion texts (scores might differ due to caching)
      texts1 = Enum.map(result1.completions, & &1.text)
      texts2 = Enum.map(result2.completions, & &1.text)
      assert texts1 == texts2

      # Cache should be used (check cache size)
      assert map_size(result2.state.cache) > 0
    end

    test "cache expires after TTL" do
      # Create state with very short TTL
      {:ok, custom_state} = Completion.init(cache_ttl: 1)

      input = %{
        prefix: "def expired_",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 12}
      }

      {:ok, result1} = Completion.execute(input, custom_state)

      # Wait for cache to expire
      Process.sleep(10)

      # Should regenerate completions
      {:ok, result2} = Completion.execute(input, result1.state)

      # Both should have completions but cache should be refreshed
      assert length(result2.completions) > 0
    end
  end

  describe "execute/2 - completion ranking" do
    test "ranks completions by score", %{state: state} do
      input = %{
        prefix: "def create_",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 11}
      }

      {:ok, result} = Completion.execute(input, state)

      # Check scores are in descending order
      scores = Enum.map(result.completions, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "adjusts scores based on context", %{state: state} do
      # Input that should boost function completions
      input = %{
        prefix: "defmodule Test do\n  def ",
        suffix: "\n  end\nend",
        language: :elixir,
        cursor_position: {2, 6}
      }

      {:ok, result} = Completion.execute(input, state)

      # Function completions should score higher
      function_completions = Enum.filter(result.completions, &(&1.type == :function))
      other_completions = Enum.reject(result.completions, &(&1.type == :function))

      if length(function_completions) > 0 and length(other_completions) > 0 do
        avg_function_score = Enum.sum(Enum.map(function_completions, & &1.score)) / length(function_completions)
        avg_other_score = Enum.sum(Enum.map(other_completions, & &1.score)) / length(other_completions)

        assert avg_function_score > avg_other_score
      end
    end
  end

  describe "execute/2 - telemetry" do
    test "emits telemetry events on completion", %{state: state} do
      handler_id = "test-completion-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:rubber_duck, :completion, :generated],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )

      input = %{
        prefix: "def telemetry_",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 14}
      }

      {:ok, _result} = Completion.execute(input, state)

      assert_receive {:telemetry, measurements, metadata}
      assert measurements[:count] >= 0
      assert metadata[:language] == :elixir

      :telemetry.detach(handler_id)
    end
  end

  describe "incremental completions" do
    setup %{state: state} do
      input = %{
        prefix: "def get_",
        suffix: "",
        language: :elixir,
        cursor_position: {1, 8}
      }

      {:ok, result} = Completion.execute(input, state)
      session = Incremental.start_session(result.completions, "get_")

      %{session: session, completions: result.completions}
    end

    test "starts a new session", %{completions: completions} do
      session = Incremental.start_session(completions, "get_")

      assert session.id != nil
      assert session.original_completions == completions
      assert session.current_completions == completions
      assert session.original_prefix == "get_"
      assert session.current_prefix == "get_"
      assert session.metadata.fuzzy_matching == true
    end

    test "updates session on character append", %{session: session} do
      updated = Incremental.update_session(session, "get_b", :append)

      assert updated.current_prefix == "get_b"
      # Should filter completions starting with 'b'
      assert length(updated.current_completions) <= length(session.original_completions)

      # All remaining completions should match the new prefix
      Enum.each(updated.current_completions, fn completion ->
        assert String.starts_with?(String.downcase(completion.text), "b")
      end)
    end

    test "updates session on character delete", %{session: session} do
      # First narrow down
      session = Incremental.update_session(session, "get_by", :append)
      narrowed_count = length(session.current_completions)

      # Then delete
      updated = Incremental.update_session(session, "get_b", :delete)

      assert updated.current_prefix == "get_b"
      # Should have more completions after delete
      assert length(updated.current_completions) >= narrowed_count
    end

    test "handles session replacement", %{session: session} do
      updated = Incremental.update_session(session, "create_", :replace)

      assert updated.current_prefix == "create_"
      # Should return empty as context changed
      assert updated.current_completions == []
    end

    test "validates session age", %{session: session} do
      assert Incremental.session_valid?(session)

      # Test with very short max age
      assert not Incremental.session_valid?(session, max_age_seconds: 0)
    end

    test "accepts partial completion", %{session: session} do
      # Accept "by"
      updated = Incremental.accept_partial(session, "by")

      assert updated.current_prefix == "get_by"

      # Completions should be updated
      Enum.each(updated.current_completions, fn completion ->
        assert not String.starts_with?(completion.text, "by")
      end)
    end

    test "fuzzy matching in incremental updates", %{completions: completions} do
      session =
        Incremental.start_session(completions, "get_",
          fuzzy_matching: true,
          max_typos: 2
        )

      # Typo: "bi" instead of "by"
      updated = Incremental.update_session(session, "get_bi", :append)

      # Should still find "by" completions due to fuzzy matching
      by_completions =
        Enum.filter(updated.current_completions, fn c ->
          String.contains?(String.downcase(c.text), "by")
        end)

      assert length(by_completions) > 0
    end

    test "get suggestions respects limits", %{session: session} do
      suggestions = Incremental.get_suggestions(session, limit: 3)

      assert length(suggestions) <= 3

      # Should be highest scored
      all_suggestions = Incremental.get_suggestions(session, limit: 100)
      top_scores = all_suggestions |> Enum.take(3) |> Enum.map(& &1.score)
      suggestion_scores = Enum.map(suggestions, & &1.score)

      assert suggestion_scores == top_scores
    end
  end

  describe "edge cases" do
    test "handles empty prefix", %{state: state} do
      input = %{
        prefix: "",
        suffix: "end",
        language: :elixir,
        cursor_position: {1, 0}
      }

      {:ok, result} = Completion.execute(input, state)

      # Should still work but might have fewer completions
      assert is_list(result.completions)
    end

    test "handles very long prefix", %{state: state} do
      long_prefix = String.duplicate("a", 1000)

      input = %{
        prefix: long_prefix,
        suffix: "",
        language: :elixir,
        cursor_position: {1, 1000}
      }

      {:ok, result} = Completion.execute(input, state)

      # Should handle gracefully
      assert is_list(result.completions)
    end

    test "handles unknown language", %{state: state} do
      input = %{
        prefix: "function unknown",
        suffix: "",
        language: :unknown_lang,
        cursor_position: {1, 16}
      }

      {:ok, result} = Completion.execute(input, state)

      # Should fall back to generic completions
      assert is_list(result.completions)
    end
  end
end
