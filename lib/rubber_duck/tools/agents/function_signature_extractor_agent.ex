defmodule RubberDuck.Tools.Agents.FunctionSignatureExtractorAgent do
  @moduledoc """
  Agent for the FunctionSignatureExtractor tool.
  
  Extracts and analyzes function signatures from code files,
  providing signature analysis, documentation generation, and API discovery.
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :function_signature_extractor,
    name: "function_signature_extractor_agent",
    description: "Extracts and analyzes function signatures from source code",
    schema: [
      # Signature database
      signature_database: [type: :map, default: %{}],
      max_signatures: [type: :integer, default: 1000],
      
      # Analysis results
      analysis_cache: [type: :map, default: %{}],
      
      # Language-specific configs
      language_configs: [type: :map, default: %{
        elixir: %{
          public_only: false,
          include_specs: true,
          include_docs: true
        },
        javascript: %{
          include_arrow_functions: true,
          include_async: true,
          include_generators: true
        },
        python: %{
          include_decorators: true,
          include_type_hints: true,
          include_docstrings: true
        }
      }]
    ]
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.BatchExtractAction,
      __MODULE__.AnalyzeSignaturesAction,
      __MODULE__.GenerateAPIDocsAction,
      __MODULE__.CompareSignaturesAction
    ]
  end
  
  # Action modules
  defmodule BatchExtractAction do
    @moduledoc false
    use Jido.Action,
      name: "batch_extract",
      description: "Extract signatures from multiple files",
      schema: [
        files: [
          type: {:list, :string},
          required: true,
          doc: "List of file paths to process"
        ],
        language: [type: :atom, required: false],
        options: [type: :map, default: %{}],
        parallel: [type: :boolean, default: true]
      ]
    
    alias RubberDuck.ToolSystem.Executor
    
    @impl true
    def run(params, context) do
      files = params.files
      language = params.language
      options = params.options
      
      results = if params.parallel do
        files
        |> Task.async_stream(fn file ->
          extract_file_signatures(file, language, options, context)
        end, timeout: 30_000)
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, reason} -> {:error, reason}
        end)
      else
        Enum.map(files, &extract_file_signatures(&1, language, options, context))
      end
      
      successful = Enum.filter(results, &match?({:ok, _}, &1))
      failed = Enum.filter(results, &match?({:error, _}, &1))
      
      all_signatures = successful
      |> Enum.flat_map(fn {:ok, %{signatures: sigs}} -> sigs end)
      
      {:ok, %{
        total_files: length(files),
        successful_files: length(successful),
        failed_files: length(failed),
        total_signatures: length(all_signatures),
        signatures: all_signatures,
        results: results
      }}
    end
    
    defp extract_file_signatures(file, language, options, _context) do
      params = Map.merge(options, %{
        file: file,
        language: language
      })
      
      Executor.execute(:function_signature_extractor, params)
    end
  end
  
  defmodule AnalyzeSignaturesAction do
    @moduledoc false
    use Jido.Action,
      name: "analyze_signatures",
      description: "Analyze extracted signatures for patterns and insights",
      schema: [
        signatures: [type: {:list, :map}, required: false],
        analysis_type: [
          type: :atom,
          values: [:complexity, :patterns, :duplicates, :coverage, :all],
          default: :all
        ],
        language: [type: :atom, required: false]
      ]
    
    @impl true
    def run(params, context) do
      # Use provided signatures or get from agent state
      signatures = params.signatures || get_cached_signatures(context.agent)
      
      analysis = case params.analysis_type do
        :complexity -> analyze_complexity(signatures)
        :patterns -> analyze_patterns(signatures)
        :duplicates -> find_duplicates(signatures)
        :coverage -> analyze_coverage(signatures)
        :all -> %{
          complexity: analyze_complexity(signatures),
          patterns: analyze_patterns(signatures),
          duplicates: find_duplicates(signatures),
          coverage: analyze_coverage(signatures)
        }
      end
      
      {:ok, %{
        analysis_type: params.analysis_type,
        signatures_analyzed: length(signatures),
        analysis: analysis,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp get_cached_signatures(agent) do
      agent.state.signature_database
      |> Map.values()
      |> List.flatten()
    end
    
    defp analyze_complexity(signatures) do
      %{
        total_functions: length(signatures),
        avg_parameters: avg_parameter_count(signatures),
        complex_functions: count_complex_functions(signatures),
        simple_functions: count_simple_functions(signatures)
      }
    end
    
    defp analyze_patterns(signatures) do
      %{
        naming_patterns: find_naming_patterns(signatures),
        parameter_patterns: find_parameter_patterns(signatures),
        return_type_patterns: find_return_type_patterns(signatures)
      }
    end
    
    defp find_duplicates(signatures) do
      signatures
      |> Enum.group_by(&signature_key/1)
      |> Enum.filter(fn {_, group} -> length(group) > 1 end)
      |> Enum.map(fn {key, duplicates} ->
        %{
          signature: key,
          count: length(duplicates),
          locations: Enum.map(duplicates, &(&1[:location] || "unknown"))
        }
      end)
    end
    
    defp analyze_coverage(signatures) do
      %{
        documented_functions: count_documented(signatures),
        typed_functions: count_typed(signatures),
        public_functions: count_public(signatures),
        private_functions: count_private(signatures)
      }
    end
    
    # Helper functions for analysis
    defp avg_parameter_count(signatures) do
      if length(signatures) == 0 do
        0
      else
        signatures
        |> Enum.map(&(length(&1[:parameters] || [])))
        |> Enum.sum()
        |> div(length(signatures))
      end
    end
    
    defp count_complex_functions(signatures) do
      Enum.count(signatures, fn sig ->
        params = length(sig[:parameters] || [])
        params > 5 || has_complex_types?(sig)
      end)
    end
    
    defp count_simple_functions(signatures) do
      Enum.count(signatures, fn sig ->
        params = length(sig[:parameters] || [])
        params <= 2 && !has_complex_types?(sig)
      end)
    end
    
    defp has_complex_types?(signature) do
      # Simple heuristic for complex types
      type_info = signature[:return_type] || ""
      String.contains?(type_info, ["->", "|", "when", "struct"])
    end
    
    defp find_naming_patterns(signatures) do
      signatures
      |> Enum.map(&(&1[:name] || ""))
      |> Enum.reduce(%{}, fn name, acc ->
        cond do
          String.starts_with?(name, "get_") ->
            Map.update(acc, :getters, 1, &(&1 + 1))
          String.starts_with?(name, "set_") ->
            Map.update(acc, :setters, 1, &(&1 + 1))
          String.starts_with?(name, "is_") ->
            Map.update(acc, :predicates, 1, &(&1 + 1))
          String.ends_with?(name, "?") ->
            Map.update(acc, :questions, 1, &(&1 + 1))
          String.ends_with?(name, "!") ->
            Map.update(acc, :bangs, 1, &(&1 + 1))
          true ->
            Map.update(acc, :other, 1, &(&1 + 1))
        end
      end)
    end
    
    defp find_parameter_patterns(signatures) do
      param_counts = signatures
      |> Enum.map(&(length(&1[:parameters] || [])))
      |> Enum.frequencies()
      
      %{
        parameter_distribution: param_counts,
        most_common_param_count: param_counts |> Enum.max_by(&elem(&1, 1)) |> elem(0)
      }
    end
    
    defp find_return_type_patterns(signatures) do
      signatures
      |> Enum.map(&(&1[:return_type] || "unknown"))
      |> Enum.frequencies()
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(10)
    end
    
    defp signature_key(signature) do
      %{
        name: signature[:name],
        arity: length(signature[:parameters] || []),
        return_type: signature[:return_type]
      }
    end
    
    defp count_documented(signatures) do
      Enum.count(signatures, &(&1["documentation"] not in [nil, ""]))
    end
    
    defp count_typed(signatures) do
      Enum.count(signatures, &(&1[:return_type] not in [nil, "", "unknown"]))
    end
    
    defp count_public(signatures) do
      Enum.count(signatures, &(&1[:visibility] == :public))
    end
    
    defp count_private(signatures) do
      Enum.count(signatures, &(&1[:visibility] == :private))
    end
  end
  
  defmodule GenerateAPIDocsAction do
    @moduledoc false
    use Jido.Action,
      name: "generate_api_docs",
      description: "Generate API documentation from signatures",
      schema: [
        signatures: [type: {:list, :map}, required: false],
        format: [type: :atom, values: [:markdown, :html, :json], default: :markdown],
        include_private: [type: :boolean, default: false],
        group_by: [type: :atom, values: [:module, :file, :type], default: :module]
      ]
    
    @impl true
    def run(params, context) do
      signatures = params.signatures || get_cached_signatures(context.agent)
      
      # Filter signatures based on visibility
      filtered_signatures = if params.include_private do
        signatures
      else
        Enum.filter(signatures, &(&1[:visibility] != :private))
      end
      
      # Group signatures
      grouped = group_signatures(filtered_signatures, params.group_by)
      
      # Generate documentation
      docs = case params.format do
        :markdown -> generate_markdown_docs(grouped)
        :html -> generate_html_docs(grouped)
        :json -> generate_json_docs(grouped)
      end
      
      {:ok, %{
        format: params.format,
        signatures_documented: length(filtered_signatures),
        groups: map_size(grouped),
        documentation: docs,
        generated_at: DateTime.utc_now()
      }}
    end
    
    defp get_cached_signatures(agent) do
      agent.state.signature_database
      |> Map.values()
      |> List.flatten()
    end
    
    defp group_signatures(signatures, :module) do
      Enum.group_by(signatures, &(&1[:module] || "Unknown"))
    end
    
    defp group_signatures(signatures, :file) do
      Enum.group_by(signatures, &(&1[:file] || "Unknown"))
    end
    
    defp group_signatures(signatures, :type) do
      Enum.group_by(signatures, &classify_function_type/1)
    end
    
    defp classify_function_type(signature) do
      name = signature[:name] || ""
      
      cond do
        String.ends_with?(name, "?") -> "Predicates"
        String.ends_with?(name, "!") -> "Mutating Functions"
        String.starts_with?(name, "get_") -> "Getters"
        String.starts_with?(name, "set_") -> "Setters"
        true -> "Other Functions"
      end
    end
    
    defp generate_markdown_docs(grouped) do
      grouped
      |> Enum.map(fn {group_name, signatures} ->
        """
        ## #{group_name}
        
        #{Enum.map(signatures, &format_signature_markdown/1) |> Enum.join("\n\n")}
        """
      end)
      |> Enum.join("\n\n")
    end
    
    defp format_signature_markdown(signature) do
      name = signature[:name] || "unknown"
      params = format_parameters(signature[:parameters] || [])
      return_type = signature[:return_type] || "unknown"
      doc = signature["documentation"] || "No documentation available."
      
      """
      ### `#{name}(#{params}) :: #{return_type}`
      
      #{doc}
      """
    end
    
    defp generate_html_docs(grouped) do
      """
      <html>
      <head><title>API Documentation</title></head>
      <body>
      <h1>API Documentation</h1>
      #{Enum.map(grouped, &format_group_html/1) |> Enum.join("\n")}
      </body>
      </html>
      """
    end
    
    defp format_group_html({group_name, signatures}) do
      """
      <h2>#{group_name}</h2>
      #{Enum.map(signatures, &format_signature_html/1) |> Enum.join("\n")}
      """
    end
    
    defp format_signature_html(signature) do
      name = signature[:name] || "unknown"
      params = format_parameters(signature[:parameters] || [])
      return_type = signature[:return_type] || "unknown"
      doc = signature["documentation"] || "No documentation available."
      
      """
      <h3><code>#{name}(#{params}) :: #{return_type}</code></h3>
      <p>#{doc}</p>
      """
    end
    
    defp generate_json_docs(grouped) do
      grouped
      |> Enum.map(fn {group_name, signatures} ->
        {group_name, Enum.map(signatures, &format_signature_json/1)}
      end)
      |> Map.new()
    end
    
    defp format_signature_json(signature) do
      %{
        name: signature[:name],
        parameters: signature[:parameters] || [],
        return_type: signature[:return_type],
        documentation: signature["documentation"],
        visibility: signature[:visibility],
        file: signature[:file],
        line: signature[:line]
      }
    end
    
    defp format_parameters(params) when is_list(params) do
      params
      |> Enum.map(&format_parameter/1)
      |> Enum.join(", ")
    end
    
    defp format_parameter(param) when is_map(param) do
      name = param[:name] || "arg"
      type = param[:type] || "any"
      "#{name} :: #{type}"
    end
    
    defp format_parameter(param) when is_binary(param), do: param
    defp format_parameter(_), do: "unknown"
  end
  
  defmodule CompareSignaturesAction do
    @moduledoc false
    use Jido.Action,
      name: "compare_signatures",
      description: "Compare signatures between versions or implementations",
      schema: [
        signatures1: [type: {:list, :map}, required: true],
        signatures2: [type: {:list, :map}, required: true],
        comparison_type: [
          type: :atom,
          values: [:api_changes, :compatibility, :coverage],
          default: :api_changes
        ]
      ]
    
    @impl true
    def run(params, _context) do
      sigs1 = params.signatures1
      sigs2 = params.signatures2
      
      comparison = case params.comparison_type do
        :api_changes -> compare_api_changes(sigs1, sigs2)
        :compatibility -> check_compatibility(sigs1, sigs2)
        :coverage -> compare_coverage(sigs1, sigs2)
      end
      
      {:ok, %{
        comparison_type: params.comparison_type,
        signatures1_count: length(sigs1),
        signatures2_count: length(sigs2),
        comparison: comparison,
        compared_at: DateTime.utc_now()
      }}
    end
    
    defp compare_api_changes(sigs1, sigs2) do
      sig1_keys = MapSet.new(sigs1, &signature_key/1)
      sig2_keys = MapSet.new(sigs2, &signature_key/1)
      
      added = MapSet.difference(sig2_keys, sig1_keys) |> MapSet.to_list()
      removed = MapSet.difference(sig1_keys, sig2_keys) |> MapSet.to_list()
      common = MapSet.intersection(sig1_keys, sig2_keys) |> MapSet.to_list()
      
      modified = find_modified_signatures(sigs1, sigs2, common)
      
      %{
        added: added,
        removed: removed,
        modified: modified,
        unchanged: length(common) - length(modified),
        summary: %{
          total_changes: length(added) + length(removed) + length(modified),
          breaking_changes: length(removed) + count_breaking_changes(modified)
        }
      }
    end
    
    defp check_compatibility(sigs1, sigs2) do
      changes = compare_api_changes(sigs1, sigs2)
      
      %{
        is_compatible: changes.summary.breaking_changes == 0,
        breaking_changes: changes.summary.breaking_changes,
        compatibility_issues: identify_compatibility_issues(changes),
        recommendations: generate_compatibility_recommendations(changes)
      }
    end
    
    defp compare_coverage(sigs1, sigs2) do
      coverage1 = calculate_coverage_metrics(sigs1)
      coverage2 = calculate_coverage_metrics(sigs2)
      
      %{
        version1: coverage1,
        version2: coverage2,
        improvements: find_coverage_improvements(coverage1, coverage2),
        regressions: find_coverage_regressions(coverage1, coverage2)
      }
    end
    
    defp signature_key(signature) do
      "#{signature[:name]}/#{length(signature[:parameters] || [])}"
    end
    
    defp find_modified_signatures(sigs1, sigs2, common_keys) do
      sig1_map = Map.new(sigs1, fn sig -> {signature_key(sig), sig} end)
      sig2_map = Map.new(sigs2, fn sig -> {signature_key(sig), sig} end)
      
      common_keys
      |> Enum.filter(fn key ->
        sig1 = sig1_map[key]
        sig2 = sig2_map[key]
        signatures_differ?(sig1, sig2)
      end)
      |> Enum.map(fn key ->
        %{
          signature: key,
          old: sig1_map[key],
          new: sig2_map[key],
          changes: detect_signature_changes(sig1_map[key], sig2_map[key])
        }
      end)
    end
    
    defp signatures_differ?(sig1, sig2) do
      sig1[:return_type] != sig2[:return_type] ||
      sig1["documentation"] != sig2["documentation"] ||
      sig1[:visibility] != sig2[:visibility]
    end
    
    defp detect_signature_changes(old_sig, new_sig) do
      changes = []
      
      changes = if old_sig[:return_type] != new_sig[:return_type] do
        [%{type: :return_type, old: old_sig[:return_type], new: new_sig[:return_type]} | changes]
      else
        changes
      end
      
      changes = if old_sig[:visibility] != new_sig[:visibility] do
        [%{type: :visibility, old: old_sig[:visibility], new: new_sig[:visibility]} | changes]
      else
        changes
      end
      
      changes = if old_sig["documentation"] != new_sig["documentation"] do
        [%{type: "documentation", old: old_sig["documentation"], new: new_sig["documentation"]} | changes]
      else
        changes
      end
      
      changes
    end
    
    defp count_breaking_changes(modified) do
      Enum.count(modified, fn mod ->
        Enum.any?(mod.changes, &breaking_change?/1)
      end)
    end
    
    defp breaking_change?(change) do
      change.type in [:return_type, :visibility] ||
      (change.type == :visibility && change.old == :public && change.new == :private)
    end
    
    defp identify_compatibility_issues(changes) do
      issues = []
      
      issues = if length(changes.removed) > 0 do
        ["Removed functions: #{inspect(changes.removed)}" | issues]
      else
        issues
      end
      
      breaking_mods = Enum.filter(changes.modified, fn mod ->
        Enum.any?(mod.changes, &breaking_change?/1)
      end)
      
      if length(breaking_mods) > 0 do
        ["Modified function signatures: #{length(breaking_mods)} functions" | issues]
      else
        issues
      end
    end
    
    defp generate_compatibility_recommendations(changes) do
      recommendations = []
      
      recommendations = if length(changes.removed) > 0 do
        ["Consider deprecating functions instead of removing them" | recommendations]
      else
        recommendations
      end
      
      recommendations = if changes.summary.breaking_changes > 0 do
        ["Increment major version number due to breaking changes" | recommendations]
      else
        recommendations
      end
      
      if length(recommendations) == 0 do
        ["No compatibility issues found - safe to deploy"]
      else
        recommendations
      end
    end
    
    defp calculate_coverage_metrics(signatures) do
      total = length(signatures)
      
      %{
        total_functions: total,
        documented: Enum.count(signatures, &(&1["documentation"] not in [nil, ""])),
        typed: Enum.count(signatures, &(&1[:return_type] not in [nil, "", "unknown"])),
        public: Enum.count(signatures, &(&1[:visibility] == :public))
      }
    end
    
    defp find_coverage_improvements(old_coverage, new_coverage) do
      improvements = []
      
      improvements = if new_coverage.documented > old_coverage.documented do
        ["Documentation coverage improved: #{new_coverage.documented - old_coverage.documented} more functions documented" | improvements]
      else
        improvements
      end
      
      improvements = if new_coverage.typed > old_coverage.typed do
        ["Type coverage improved: #{new_coverage.typed - old_coverage.typed} more functions typed" | improvements]
      else
        improvements
      end
      
      improvements
    end
    
    defp find_coverage_regressions(old_coverage, new_coverage) do
      regressions = []
      
      regressions = if new_coverage.documented < old_coverage.documented do
        ["Documentation coverage decreased: #{old_coverage.documented - new_coverage.documented} fewer functions documented" | regressions]
      else
        regressions
      end
      
      regressions = if new_coverage.typed < old_coverage.typed do
        ["Type coverage decreased: #{old_coverage.typed - new_coverage.typed} fewer functions typed" | regressions]
      else
        regressions
      end
      
      regressions
    end
  end
  
  # Tool-specific signal handlers using the new action system
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "batch_extract"} = signal) do
    files = get_in(signal, ["data", "files"]) || []
    language = get_in(signal, ["data", "language"])
    options = get_in(signal, ["data", "options"]) || %{}
    parallel = get_in(signal, ["data", "parallel"]) || true
    
    # Execute batch extract action
    {:ok, _ref} = __MODULE__.cmd_async(agent, BatchExtractAction, %{
      files: files,
      language: language,
      options: options,
      parallel: parallel
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "analyze_signatures"} = signal) do
    signatures = get_in(signal, ["data", "signatures"])
    analysis_type = get_in(signal, ["data", "analysis_type"]) || :all
    language = get_in(signal, ["data", "language"])
    
    # Execute signature analysis action
    {:ok, _ref} = __MODULE__.cmd_async(agent, AnalyzeSignaturesAction, %{
      signatures: signatures,
      analysis_type: analysis_type,
      language: language
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_api_docs"} = signal) do
    signatures = get_in(signal, ["data", "signatures"])
    format = get_in(signal, ["data", "format"]) || :markdown
    include_private = get_in(signal, ["data", "include_private"]) || false
    group_by = get_in(signal, ["data", "group_by"]) || :module
    
    # Execute API docs generation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, GenerateAPIDocsAction, %{
      signatures: signatures,
      format: format,
      include_private: include_private,
      group_by: group_by
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "compare_signatures"} = signal) do
    signatures1 = get_in(signal, ["data", "signatures1"]) || []
    signatures2 = get_in(signal, ["data", "signatures2"]) || []
    comparison_type = get_in(signal, ["data", "comparison_type"]) || :api_changes
    
    # Execute signature comparison action
    {:ok, _ref} = __MODULE__.cmd_async(agent, CompareSignaturesAction, %{
      signatures1: signatures1,
      signatures2: signatures2,
      comparison_type: comparison_type
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, _signal), do: super(agent, _signal)
  
  # Process extraction results to update signature database
  @impl true
  def process_result(result, _context) do
    # Add extraction timestamp
    Map.put(result, :extracted_at, DateTime.utc_now())
  end
  
  # Override action result handler to update signature database
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Let parent handle the standard processing
    {:ok, agent} = super(agent, ExecuteToolAction, {:ok, result}, metadata)
    
    # Update signature database if we got signatures and it's not from cache
    if result[:from_cache] == false && result[:result][:signatures] do
      file = result[:result][:file] || "unknown"
      signatures = result[:result][:signatures] || []
      
      # Store signatures by file
      agent = put_in(agent.state.signature_database[file], signatures)
      
      # Prune database if it gets too large
      agent = prune_signature_database(agent)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, BatchExtractAction, {:ok, result}, _metadata) do
    # Update signature database with batch results
    if result[:signatures] do
      # Group signatures by file and update database
      signatures_by_file = Enum.group_by(result.signatures, &(&1[:file] || "unknown"))
      
      agent = Enum.reduce(signatures_by_file, agent, fn {file, sigs}, acc ->
        put_in(acc.state.signature_database[file], sigs)
      end)
      
      agent = prune_signature_database(agent)
      
      # Emit result signal
      signal = Jido.Signal.new!(%{
        type: "tool.batch_extract.completed",
        source: "agent:#{agent.id}",
        data: result
      })
      emit_signal(agent, signal)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, action, result, metadata) do
    # Let parent handle other actions
    super(agent, action, result, metadata)
  end
  
  # Helper functions
  
  defp prune_signature_database(agent) do
    database = agent.state.signature_database
    max_signatures = agent.state.max_signatures
    
    total_signatures = database
    |> Map.values()
    |> Enum.map(&length/1)
    |> Enum.sum()
    
    if total_signatures > max_signatures do
      # Keep most recently updated files
      pruned_database = database
      |> Enum.sort_by(fn {_file, signatures} ->
        # Get most recent timestamp from signatures
        signatures
        |> Enum.map(&(&1[:extracted_at] || DateTime.utc_now()))
        |> Enum.max(DateTime)
      end, {:desc, DateTime})
      |> Enum.take(div(max_signatures, 10)) # Keep roughly max_signatures/10 files
      |> Map.new()
      
      put_in(agent.state.signature_database, pruned_database)
    else
      agent
    end
  end
end