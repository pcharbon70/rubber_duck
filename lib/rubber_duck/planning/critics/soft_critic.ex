defmodule RubberDuck.Planning.Critics.SoftCritic do
  @moduledoc """
  Soft critics for quality validation of plans and tasks.

  Soft critics assess quality aspects and provide recommendations
  for improvement. They include:
  - Code style and convention checking
  - Best practice validation
  - Performance impact analysis
  - Security consideration checking
  """

  alias RubberDuck.Planning.Critics.CriticBehaviour
  alias RubberDuck.Planning.{Plan, Task}

  require Logger

  # Sub-critic modules
  defmodule StyleChecker do
    @moduledoc "Checks code style and conventions"
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Style Checker"

    @impl true
    def type, do: :soft

    @impl true
    def priority, do: 100

    @impl true
    def validate(target, _opts) do
      checks = [
        check_naming_conventions(target),
        check_description_quality(target),
        check_documentation_completeness(target),
        check_modularity(target)
      ]

      aggregate_style_results(checks)
    end

    defp check_naming_conventions(%{name: name}) when is_binary(name) do
      cond do
        String.length(name) < 3 ->
          {:warning, "Name '#{name}' is too short (< 3 characters)"}

        String.length(name) > 100 ->
          {:warning, "Name '#{name}' is too long (> 100 characters)"}

        not String.match?(name, ~r/^[A-Z][a-zA-Z0-9\s\-_]+$/) ->
          {:info, "Name '#{name}' doesn't follow title case convention"}

        true ->
          {:ok, "Name follows conventions"}
      end
    end

    defp check_naming_conventions(_), do: {:ok, "No name to check"}

    defp check_description_quality(%{description: desc}) when is_binary(desc) do
      word_count = String.split(desc) |> length()

      cond do
        word_count < 5 ->
          {:warning, "Description is too brief (#{word_count} words)"}

        not String.ends_with?(desc, ".") ->
          {:info, "Description should end with punctuation"}

        String.length(desc) > 2000 ->
          {:info, "Consider breaking down long descriptions (#{String.length(desc)} chars)"}

        true ->
          {:ok, "Description quality is good"}
      end
    end

    defp check_description_quality(_), do: {:warning, "Missing description"}

    defp check_documentation_completeness(target) do
      required_fields = [:description, :success_criteria, :acceptance_criteria]
      missing = Enum.reject(required_fields, &Map.has_key?(target, &1))

      case length(missing) do
        0 -> {:ok, "Documentation is complete"}
        1 -> {:info, "Missing field: #{hd(missing)}"}
        _ -> {:warning, "Missing fields: #{Enum.join(missing, ", ")}"}
      end
    end

    defp check_modularity(%Task{} = task) do
      # Check if task is appropriately sized
      indicators = [
        task.complexity in [:simple, :medium],
        # Tasks don't have subtasks field currently
        true,
        is_nil(task.dependencies) or length(task.dependencies || []) < 10
      ]

      case Enum.count(indicators, & &1) do
        3 -> {:ok, "Task has good modularity"}
        2 -> {:info, "Consider breaking down complex tasks"}
        _ -> {:warning, "Task may be too complex, consider decomposition"}
      end
    end

    defp check_modularity(_), do: {:ok, "Modularity not applicable"}

    defp aggregate_style_results(checks) do
      warnings = Enum.filter(checks, &match?({:warning, _}, &1))
      infos = Enum.filter(checks, &match?({:info, _}, &1))

      cond do
        not Enum.empty?(warnings) ->
          messages = Enum.map(warnings ++ infos, fn {_, msg} -> msg end)

          {:ok,
           CriticBehaviour.validation_result(
             :warning,
             "Style improvements recommended",
             severity: :warning,
             details: %{issues: messages},
             suggestions: [
               "Follow naming conventions",
               "Improve documentation completeness",
               "Consider task modularity"
             ]
           )}

        not Enum.empty?(infos) ->
          messages = Enum.map(infos, fn {_, msg} -> msg end)

          {:ok,
           CriticBehaviour.validation_result(
             :passed,
             "Minor style suggestions",
             severity: :info,
             details: %{suggestions: messages}
           )}

        true ->
          {:ok, CriticBehaviour.validation_result(:passed, "Code style is good")}
      end
    end
  end

  defmodule BestPracticeValidator do
    @moduledoc "Validates against software engineering best practices"
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Best Practice Validator"

    @impl true
    def type, do: :soft

    @impl true
    def priority, do: 110

    @impl true
    def validate(target, _opts) do
      practices = [
        check_single_responsibility(target),
        check_clear_interfaces(target),
        check_error_handling(target),
        check_testing_strategy(target),
        check_incremental_approach(target)
      ]

      aggregate_practice_results(practices)
    end

    defp check_single_responsibility(%{description: desc, complexity: complexity})
         when is_binary(desc) do
      # Heuristic: count distinct verbs/actions in description
      action_words = ~w(create update delete fetch process handle manage coordinate)
      desc_lower = String.downcase(desc)

      action_count = Enum.count(action_words, &String.contains?(desc_lower, &1))

      cond do
        action_count > 3 and complexity in [:complex, :very_complex] ->
          {:warning, "Task may violate single responsibility principle (#{action_count} actions)"}

        action_count > 5 ->
          {:warning, "Consider splitting task into focused subtasks"}

        true ->
          {:ok, "Task has focused responsibility"}
      end
    end

    defp check_single_responsibility(_), do: {:ok, "Single responsibility check passed"}

    defp check_clear_interfaces(%{inputs: inputs, outputs: outputs})
         when is_map(inputs) and is_map(outputs) do
      if map_size(inputs) > 0 and map_size(outputs) > 0 do
        {:ok, "Clear interfaces defined"}
      else
        {:info, "Consider defining clear inputs and outputs"}
      end
    end

    defp check_clear_interfaces(_), do: {:info, "No interface definitions found"}

    defp check_error_handling(%{description: desc}) when is_binary(desc) do
      error_keywords = ~w(error fail exception handle recover retry fallback)
      desc_lower = String.downcase(desc)

      has_error_handling = Enum.any?(error_keywords, &String.contains?(desc_lower, &1))

      if has_error_handling do
        {:ok, "Error handling considered"}
      else
        {:info, "Consider documenting error handling approach"}
      end
    end

    defp check_error_handling(_), do: {:info, "Error handling not documented"}

    defp check_testing_strategy(target) do
      has_test_info =
        Map.has_key?(target, :test_strategy) or
          Map.has_key?(target, :acceptance_criteria) or
          (is_binary(Map.get(target, :description)) and
             String.contains?(String.downcase(Map.get(target, :description, "")), "test"))

      if has_test_info do
        {:ok, "Testing strategy defined"}
      else
        {:warning, "No testing strategy defined"}
      end
    end

    defp check_incremental_approach(%Plan{} = _plan) do
      # Plans should have incremental milestones
      {:info, "Consider defining incremental milestones"}
    end

    defp check_incremental_approach(%Task{complexity: :very_complex}) do
      {:warning, "Complex task should be broken into incremental steps"}
    end

    defp check_incremental_approach(_), do: {:ok, "Appropriate task size"}

    defp aggregate_practice_results(practices) do
      warnings = Enum.filter(practices, &match?({:warning, _}, &1))
      infos = Enum.filter(practices, &match?({:info, _}, &1))

      cond do
        length(warnings) >= 2 ->
          messages = Enum.map(warnings, fn {_, msg} -> msg end)

          {:ok,
           CriticBehaviour.validation_result(
             :warning,
             "Multiple best practice violations",
             severity: :warning,
             details: %{violations: messages},
             suggestions: [
               "Follow single responsibility principle",
               "Define clear interfaces",
               "Document error handling",
               "Include testing strategy"
             ]
           )}

        not Enum.empty?(warnings) or length(infos) >= 3 ->
          all_messages = Enum.map(warnings ++ infos, fn {_, msg} -> msg end)

          {:ok,
           CriticBehaviour.validation_result(
             :passed,
             "Some best practices could be improved",
             severity: :info,
             details: %{suggestions: all_messages}
           )}

        true ->
          {:ok, CriticBehaviour.validation_result(:passed, "Follows best practices")}
      end
    end
  end

  defmodule PerformanceAnalyzer do
    @moduledoc "Analyzes potential performance impacts"
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Performance Analyzer"

    @impl true
    def type, do: :soft

    @impl true
    def priority, do: 120

    @impl true
    def validate(target, _opts) do
      analyses = [
        analyze_computational_complexity(target),
        analyze_data_handling(target),
        analyze_concurrency_approach(target),
        analyze_resource_usage(target)
      ]

      aggregate_performance_results(analyses)
    end

    defp analyze_computational_complexity(%{details: %{"algorithm" => algorithm}}) do
      # Simple heuristic based on common algorithm patterns
      alg = String.downcase(algorithm)

      cond do
        String.match?(alg, ~r/nested.*(loop|iteration)/) ->
          {:warning, "Nested loops detected - O(n²) or higher complexity"}

        String.match?(alg, ~r/recursive/) ->
          {:info, "Recursive approach - ensure proper tail call optimization"}

        String.match?(alg, ~r/sort|search/) ->
          {:info, "Ensure using efficient sorting/searching algorithms"}

        true ->
          {:ok, "No obvious complexity issues"}
      end
    end

    defp analyze_computational_complexity(_), do: {:ok, "Complexity not analyzed"}

    defp analyze_data_handling(%{description: desc}) when is_binary(desc) do
      desc_lower = String.downcase(desc)

      cond do
        desc_lower =~ ~r/load.*all|fetch.*all|get.*all/ ->
          {:warning, "Consider pagination for large datasets"}

        desc_lower =~ ~r/bulk|batch/ ->
          {:ok, "Batch processing approach is good for performance"}

        desc_lower =~ ~r/stream|lazy/ ->
          {:ok, "Streaming/lazy evaluation is performance-friendly"}

        desc_lower =~ ~r/cache|memo/ ->
          {:ok, "Caching strategy improves performance"}

        true ->
          {:ok, "No specific data handling concerns"}
      end
    end

    defp analyze_data_handling(_), do: {:ok, "Data handling not analyzed"}

    defp analyze_concurrency_approach(target) do
      indicators = [
        Map.get(target, :parallel, false),
        Map.get(target, :async, false),
        is_binary(Map.get(target, :description)) and
          String.contains?(String.downcase(Map.get(target, :description, "")), "concurrent")
      ]

      if Enum.any?(indicators) do
        {:info, "Ensure proper concurrency control and error handling"}
      else
        {:ok, "Consider if task could benefit from parallelization"}
      end
    end

    defp analyze_resource_usage(%{resource_requirements: reqs}) when is_map(reqs) do
      memory = Map.get(reqs, :memory_mb, 0)
      cpu = Map.get(reqs, :cpu_percent, 0)

      cond do
        memory > 1000 ->
          {:warning, "High memory usage (#{memory}MB) - optimize if possible"}

        cpu > 80 ->
          {:warning, "High CPU usage (#{cpu}%) - consider optimization"}

        memory > 500 or cpu > 50 ->
          {:info, "Moderate resource usage - monitor in production"}

        true ->
          {:ok, "Resource usage appears reasonable"}
      end
    end

    defp analyze_resource_usage(_), do: {:ok, "Resource usage not specified"}

    defp aggregate_performance_results(analyses) do
      warnings = Enum.filter(analyses, &match?({:warning, _}, &1))
      infos = Enum.filter(analyses, &match?({:info, _}, &1))

      cond do
        not Enum.empty?(warnings) ->
          messages = Enum.map(warnings, fn {_, msg} -> msg end)

          {:ok,
           CriticBehaviour.validation_result(
             :warning,
             "Performance concerns identified",
             severity: :warning,
             details: %{concerns: messages},
             suggestions: [
               "Optimize algorithmic complexity",
               "Consider data pagination",
               "Implement caching where appropriate",
               "Monitor resource usage"
             ]
           )}

        length(infos) >= 2 ->
          messages = Enum.map(infos, fn {_, msg} -> msg end)

          {:ok,
           CriticBehaviour.validation_result(
             :passed,
             "Minor performance considerations",
             severity: :info,
             details: %{considerations: messages}
           )}

        true ->
          {:ok, CriticBehaviour.validation_result(:passed, "No performance concerns")}
      end
    end
  end

  defmodule SecurityChecker do
    @moduledoc "Checks for security considerations"
    @behaviour CriticBehaviour

    @impl true
    def name, do: "Security Checker"

    @impl true
    def type, do: :soft

    @impl true
    def priority, do: 130

    @impl true
    def validate(target, _opts) do
      checks = [
        check_authentication_requirements(target),
        check_data_sensitivity(target),
        check_input_validation(target),
        check_secure_patterns(target)
      ]

      aggregate_security_results(checks)
    end

    defp check_authentication_requirements(target) do
      desc = Map.get(target, :description, "") |> to_string() |> String.downcase()

      auth_keywords = ~w(auth authenticate permission role access user)
      needs_auth = Enum.any?(auth_keywords, &String.contains?(desc, &1))

      security_info =
        Map.get(target, :security_requirements) ||
          Map.get(target, :authentication_required)

      cond do
        needs_auth and is_nil(security_info) ->
          {:warning, "Task involves authentication but no security requirements defined"}

        needs_auth ->
          {:ok, "Authentication requirements defined"}

        true ->
          {:ok, "No authentication requirements detected"}
      end
    end

    defp check_data_sensitivity(target) do
      desc = Map.get(target, :description, "") |> to_string() |> String.downcase()

      sensitive_keywords = ~w(password secret key token credential sensitive personal pii)
      has_sensitive = Enum.any?(sensitive_keywords, &String.contains?(desc, &1))

      if has_sensitive do
        {:warning, "Task handles sensitive data - ensure proper encryption and access control"}
      else
        {:ok, "No sensitive data handling detected"}
      end
    end

    defp check_input_validation(target) do
      desc = Map.get(target, :description, "") |> to_string() |> String.downcase()

      input_keywords = ~w(input parameter arg query form upload file)
      validation_keywords = ~w(validate sanitize escape verify check)

      has_inputs = Enum.any?(input_keywords, &String.contains?(desc, &1))
      has_validation = Enum.any?(validation_keywords, &String.contains?(desc, &1))

      cond do
        has_inputs and not has_validation ->
          {:warning, "Task accepts inputs - ensure proper validation"}

        has_inputs and has_validation ->
          {:ok, "Input validation appears to be considered"}

        true ->
          {:ok, "No input validation concerns"}
      end
    end

    defp check_secure_patterns(target) do
      desc = Map.get(target, :description, "") |> to_string() |> String.downcase()

      insecure_patterns = [
        {~r/eval|execute.*string/, "Dynamic code execution detected"},
        {~r/sql.*concat|string.*query/, "Potential SQL injection risk"},
        {~r/shell|system.*command/, "Shell command execution detected"},
        {~r/disable.*ssl|skip.*verif/, "SSL/TLS verification concerns"}
      ]

      warnings =
        insecure_patterns
        |> Enum.filter(fn {pattern, _} -> desc =~ pattern end)
        |> Enum.map(fn {_, message} -> message end)

      case warnings do
        [] -> {:ok, "No insecure patterns detected"}
        [warning] -> {:warning, warning}
        multiple -> {:warning, "Multiple security concerns: #{Enum.join(multiple, "; ")}"}
      end
    end

    defp aggregate_security_results(checks) do
      warnings = Enum.filter(checks, &match?({:warning, _}, &1))

      if Enum.empty?(warnings) do
        {:ok, CriticBehaviour.validation_result(:passed, "No security concerns identified")}
      else
        messages = Enum.map(warnings, fn {_, msg} -> msg end)

        {:ok,
         CriticBehaviour.validation_result(
           :warning,
           "Security considerations needed",
           severity: :warning,
           details: %{concerns: messages},
           suggestions: [
             "Define authentication requirements",
             "Implement input validation",
             "Use parameterized queries",
             "Encrypt sensitive data",
             "Follow security best practices"
           ]
         )}
      end
    end
  end

  @doc """
  Returns all available soft critics.
  """
  def all_critics do
    [
      StyleChecker,
      BestPracticeValidator,
      PerformanceAnalyzer,
      SecurityChecker
    ]
  end

  @doc """
  Runs all soft critics against a target.
  """
  def validate_all(target, opts \\ []) do
    critics = Keyword.get(opts, :critics, all_critics())

    critics
    |> Enum.sort_by(& &1.priority())
    |> Enum.map(fn critic ->
      Logger.debug("Running soft critic: #{critic.name()}")

      result =
        try do
          critic.validate(target, opts)
        rescue
          e ->
            Logger.error("Critic #{critic.name()} failed: #{inspect(e)}")
            {:error, "Critic execution failed: #{Exception.message(e)}"}
        end

      {critic, result}
    end)
  end
end
