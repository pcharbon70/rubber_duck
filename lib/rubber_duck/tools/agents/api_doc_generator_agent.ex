defmodule RubberDuck.Tools.Agents.APIDocGeneratorAgent do
  @moduledoc """
  Agent for the APIDocGenerator tool.
  
  Generates comprehensive API documentation from various sources including
  source code, OpenAPI specs, and existing documentation.
  """
  
  use RubberDuck.Tools.Agents.BaseToolAgent,
    tool: :api_doc_generator,
    name: "api_doc_generator_agent",
    description: "Generates comprehensive API documentation from various sources",
    schema: [
      # Documentation templates and themes
      templates: [type: :map, default: %{
        rest_api: "default_rest_template",
        graphql: "default_graphql_template", 
        library: "default_library_template"
      }],
      themes: [type: :map, default: %{
        modern: %{colors: %{primary: "#2563eb", secondary: "#64748b"}},
        dark: %{colors: %{primary: "#06b6d4", secondary: "#475569"}},
        minimal: %{colors: %{primary: "#000000", secondary: "#666666"}}
      }],
      
      # Generation history and caching
      doc_cache: [type: :map, default: %{}],
      generation_history: [type: {:list, :map}, default: []],
      max_history: [type: :integer, default: 50],
      
      # Configuration presets
      presets: [type: :map, default: %{
        quick: %{include_examples: true, include_schemas: false, format: :markdown},
        comprehensive: %{include_examples: true, include_schemas: true, format: :html},
        minimal: %{include_examples: false, include_schemas: false, format: :text}
      }]
    ]
  
  # Define additional actions for this agent
  @impl true
  def additional_actions do
    [
      __MODULE__.GenerateFromOpenAPIAction,
      __MODULE__.GenerateFromCodeAction,
      __MODULE__.ValidateDocumentationAction,
      __MODULE__.MergeDocumentationAction,
      __MODULE__.PublishDocumentationAction
    ]
  end
  
  # Action modules
  defmodule GenerateFromOpenAPIAction do
    @moduledoc false
    use Jido.Action,
      name: "generate_from_openapi",
      description: "Generate documentation from OpenAPI specification",
      schema: [
        spec_source: [
          type: :string,
          required: true,
          doc: "Path to OpenAPI spec file or URL"
        ],
        format: [type: :atom, values: [:html, :markdown, :pdf], default: :html],
        theme: [type: :atom, values: [:modern, :dark, :minimal], default: :modern],
        include_examples: [type: :boolean, default: true],
        include_schemas: [type: :boolean, default: true],
        output_path: [type: :string, required: false]
      ]
    
    alias RubberDuck.ToolSystem.Executor
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Get theme configuration
      theme_config = get_theme_config(agent, params.theme)
      
      # Prepare tool parameters
      tool_params = %{
        spec_source: params.spec_source,
        format: params.format,
        theme: theme_config,
        include_examples: params.include_examples,
        include_schemas: params.include_schemas,
        output_path: params.output_path
      }
      
      case Executor.execute(:api_doc_generator, tool_params) do
        {:ok, result} ->
          {:ok, %{
            format: params.format,
            theme: params.theme,
            spec_source: params.spec_source,
            documentation: result.documentation,
            metadata: result.metadata || %{},
            generated_at: DateTime.utc_now()
          }}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp get_theme_config(agent, theme_name) do
      agent.state.themes[theme_name] || agent.state.themes[:modern]
    end
  end
  
  defmodule GenerateFromCodeAction do
    @moduledoc false
    use Jido.Action,
      name: "generate_from_code",
      description: "Generate documentation from source code analysis",
      schema: [
        source_paths: [
          type: {:list, :string},
          required: true,
          doc: "List of source code paths to analyze"
        ],
        language: [type: :atom, required: true],
        doc_type: [
          type: :atom,
          values: [:api, :library, :module],
          default: :library
        ],
        format: [type: :atom, values: [:html, :markdown, :json], default: :markdown],
        include_private: [type: :boolean, default: false],
        include_tests: [type: :boolean, default: false],
        template: [type: :string, required: false]
      ]
    
    alias RubberDuck.ToolSystem.Executor
    
    @impl true
    def run(params, context) do
      agent = context.agent
      
      # Get template configuration
      template_config = get_template_config(agent, params.doc_type, params.template)
      
      # Prepare tool parameters
      tool_params = %{
        source_paths: params.source_paths,
        language: params.language,
        doc_type: params.doc_type,
        format: params.format,
        include_private: params.include_private,
        include_tests: params.include_tests,
        template: template_config
      }
      
      case Executor.execute(:api_doc_generator, tool_params) do
        {:ok, result} ->
          {:ok, %{
            doc_type: params.doc_type,
            language: params.language,
            format: params.format,
            source_paths: params.source_paths,
            documentation: result.documentation,
            metadata: %{
              functions_documented: result.functions_documented || 0,
              modules_processed: result.modules_processed || 0,
              coverage: result.coverage || %{}
            },
            generated_at: DateTime.utc_now()
          }}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
    
    defp get_template_config(agent, doc_type, custom_template) do
      if custom_template do
        custom_template
      else
        agent.state.templates[doc_type] || agent.state.templates[:library]
      end
    end
  end
  
  defmodule ValidateDocumentationAction do
    @moduledoc false
    use Jido.Action,
      name: "validate_documentation",
      description: "Validate generated documentation for completeness and accuracy",
      schema: [
        documentation: [type: :map, required: true],
        validation_rules: [
          type: {:list, :atom},
          default: [:completeness, :accuracy, :consistency, :examples]
        ],
        strict_mode: [type: :boolean, default: false]
      ]
    
    @impl true
    def run(params, _context) do
      documentation = params.documentation
      rules = params.validation_rules
      strict = params.strict_mode
      
      results = Enum.map(rules, fn rule ->
        {rule, validate_rule(documentation, rule, strict)}
      end) |> Map.new()
      
      # Calculate overall score
      passed = Enum.count(results, fn {_, result} -> result.passed end)
      total = length(rules)
      score = if total > 0, do: (passed / total) * 100, else: 0
      
      overall_passed = if strict do
        score == 100
      else
        score >= 80
      end
      
      {:ok, %{
        validation_results: results,
        overall_score: score,
        overall_passed: overall_passed,
        validated_at: DateTime.utc_now()
      }}
    end
    
    defp validate_rule(documentation, :completeness, strict) do
      # Check if all required sections are present
      required_sections = [:title, :description, :endpoints]
      present_sections = Map.keys(documentation)
      
      missing = required_sections -- present_sections
      coverage = (length(present_sections) / length(required_sections)) * 100
      
      passed = if strict do
        length(missing) == 0
      else
        coverage >= 75
      end
      
      %{
        rule: :completeness,
        passed: passed,
        score: coverage,
        issues: if(length(missing) > 0, do: ["Missing sections: #{inspect(missing)}"], else: [])
      }
    end
    
    defp validate_rule(documentation, :accuracy, _strict) do
      # Basic accuracy checks - in real implementation would be more sophisticated
      issues = []
      
      # Check for placeholder text
      issues = if has_placeholder_text?(documentation) do
        ["Contains placeholder text" | issues]
      else
        issues
      end
      
      # Check for broken links (simplified)
      issues = if has_broken_links?(documentation) do
        ["May contain broken links" | issues]
      else
        issues
      end
      
      %{
        rule: :accuracy,
        passed: length(issues) == 0,
        score: if(length(issues) == 0, do: 100, else: 50),
        issues: issues
      }
    end
    
    defp validate_rule(documentation, :consistency, _strict) do
      # Check for consistent formatting and naming
      issues = []
      
      # Check endpoint naming consistency
      issues = if inconsistent_naming?(documentation) do
        ["Inconsistent naming patterns detected" | issues]      
      else
        issues
      end
      
      %{
        rule: :consistency,
        passed: length(issues) == 0,
        score: if(length(issues) == 0, do: 100, else: 70),
        issues: issues
      }
    end
    
    defp validate_rule(documentation, :examples, strict) do
      # Check if examples are provided
      endpoints = documentation[:endpoints] || []
      with_examples = Enum.count(endpoints, &has_examples?/1)
      total = length(endpoints)
      
      coverage = if total > 0, do: (with_examples / total) * 100, else: 100
      
      passed = if strict do
        coverage == 100
      else
        coverage >= 60
      end
      
      issues = if coverage < 100 do
        ["#{total - with_examples} endpoints missing examples"]
      else
        []
      end
      
      %{
        rule: :examples,
        passed: passed,
        score: coverage,
        issues: issues
      }
    end
    
    defp validate_rule(_documentation, _rule, _strict) do
      %{
        rule: :unknown,
        passed: true,
        score: 100,
        issues: []
      }
    end
    
    # Helper validation functions
    defp has_placeholder_text?(documentation) do
      content = inspect(documentation)
      placeholder_patterns = ["TODO", "FIXME", "placeholder", "example.com"]
      
      Enum.any?(placeholder_patterns, fn pattern ->
        String.contains?(String.downcase(content), String.downcase(pattern))
      end)
    end
    
    defp has_broken_links?(documentation) do
      # Simplified check - in real implementation would validate URLs
      content = inspect(documentation)
      String.contains?(content, "http://localhost") || String.contains?(content, "broken-link")
    end
    
    defp inconsistent_naming?(documentation) do
      endpoints = documentation[:endpoints] || []
      
      if length(endpoints) < 2 do
        false
      else
        # Check if endpoint names follow consistent patterns
        names = Enum.map(endpoints, &(&1[:name] || ""))
        
        # Simple heuristic: check if all names use same case convention
        snake_case = Enum.count(names, &String.contains?(&1, "_"))
        camel_case = Enum.count(names, &Regex.match?(~r/[a-z][A-Z]/, &1))
        
        # Inconsistent if we have both patterns
        snake_case > 0 && camel_case > 0
      end
    end
    
    defp has_examples?(endpoint) do
      examples = endpoint[:examples] || endpoint[:example] || []
      length(examples) > 0 || endpoint[:request_example] || endpoint[:response_example]
    end
  end
  
  defmodule MergeDocumentationAction do
    @moduledoc false
    use Jido.Action,
      name: "merge_documentation",
      description: "Merge multiple documentation sources into unified docs",
      schema: [
        sources: [
          type: {:list, :map},
          required: true,
          doc: "List of documentation sources to merge"
        ],
        merge_strategy: [
          type: :atom,
          values: [:union, :intersection, :priority],
          default: :union
        ],
        conflict_resolution: [
          type: :atom,
          values: [:first_wins, :last_wins, :manual],
          default: :last_wins
        ],
        output_format: [type: :atom, values: [:html, :markdown, :json], default: :html]
      ]
    
    @impl true
    def run(params, _context) do
      sources = params.sources
      strategy = params.merge_strategy
      conflict_resolution = params.conflict_resolution
      
      merged = case strategy do
        :union -> merge_union(sources, conflict_resolution)
        :intersection -> merge_intersection(sources, conflict_resolution)
        :priority -> merge_priority(sources, conflict_resolution)
      end
      
      {:ok, %{
        merge_strategy: strategy,
        conflict_resolution: conflict_resolution,
        sources_count: length(sources),
        merged_documentation: merged,
        conflicts_resolved: count_conflicts_resolved(sources),
        merged_at: DateTime.utc_now()
      }}
    end
    
    defp merge_union(sources, conflict_resolution) do
      # Combine all sources, resolving conflicts
      Enum.reduce(sources, %{}, fn source, acc ->
        merge_two_docs(acc, source, conflict_resolution)
      end)
    end
    
    defp merge_intersection(sources, conflict_resolution) do
      # Only include elements present in all sources
      if length(sources) == 0 do
        %{}
      else
        [first | rest] = sources
        
        Enum.reduce(rest, first, fn source, acc ->
          intersect_docs(acc, source, conflict_resolution)
        end)
      end
    end
    
    defp merge_priority(sources, _conflict_resolution) do
      # Sources are in priority order, later sources override earlier ones
      Enum.reduce(sources, %{}, fn source, acc ->
        Map.merge(acc, source)
      end)
    end
    
    defp merge_two_docs(doc1, doc2, conflict_resolution) do
      Map.merge(doc1, doc2, fn _key, val1, val2 ->
        resolve_conflict(val1, val2, conflict_resolution)
      end)
    end
    
    defp intersect_docs(doc1, doc2, conflict_resolution) do
      common_keys = MapSet.intersection(MapSet.new(Map.keys(doc1)), MapSet.new(Map.keys(doc2)))
      
      common_keys
      |> Enum.map(fn key ->
        val1 = doc1[key]
        val2 = doc2[key]
        {key, resolve_conflict(val1, val2, conflict_resolution)}
      end)
      |> Map.new()
    end
    
    defp resolve_conflict(val1, val2, :first_wins), do: val1
    defp resolve_conflict(_val1, val2, :last_wins), do: val2
    defp resolve_conflict(val1, val2, :manual) do
      # In real implementation, this would trigger manual resolution
      # For now, we'll combine them
      if is_list(val1) && is_list(val2) do
        val1 ++ val2
      else
        val2
      end
    end
    
    defp count_conflicts_resolved(sources) do
      # Simplified conflict counting
      if length(sources) <= 1 do
        0
      else
        all_keys = sources
        |> Enum.flat_map(&Map.keys/1)
        |> Enum.frequencies()
        
        Enum.count(all_keys, fn {_key, count} -> count > 1 end)
      end
    end
  end
  
  defmodule PublishDocumentationAction do
    @moduledoc false
    use Jido.Action,
      name: "publish_documentation",
      description: "Publish documentation to various platforms and formats",
      schema: [
        documentation: [type: :map, required: true],
        platforms: [
          type: {:list, :atom},
          values: [:file_system, :github_pages, :confluence, :static_site],
          default: [:file_system]
        ],
        publish_config: [type: :map, default: %{}],
        version: [type: :string, required: false],
        changelog: [type: :string, required: false]
      ]
    
    @impl true
    def run(params, _context) do
      documentation = params.documentation
      platforms = params.platforms
      config = params.publish_config
      
      results = Enum.map(platforms, fn platform ->
        {platform, publish_to_platform(documentation, platform, config)}
      end) |> Map.new()
      
      successful = Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end)
      failed = Enum.count(results, fn {_, result} -> match?({:error, _}, result) end)
      
      {:ok, %{
        platforms: platforms,
        results: results,
        successful_publishes: successful,
        failed_publishes: failed,
        version: params.version,
        published_at: DateTime.utc_now()
      }}
    end
    
    defp publish_to_platform(documentation, :file_system, config) do
      output_path = config[:output_path] || "./docs"
      
      # In real implementation, would write files to filesystem
      {:ok, %{
        platform: :file_system,
        location: output_path,
        files_written: count_files_to_write(documentation)
      }}
    end
    
    defp publish_to_platform(documentation, :github_pages, config) do
      repo = config[:repository] || "unknown/repo"
      branch = config[:branch] || "gh-pages"
      
      # In real implementation, would push to GitHub Pages
      {:ok, %{
        platform: :github_pages,
        repository: repo,
        branch: branch,
        url: "https://#{String.replace(repo, "/", ".github.io/")}"
      }}
    end
    
    defp publish_to_platform(documentation, :confluence, config) do
      space = config[:space] || "DOCS"
      
      # In real implementation, would publish to Confluence
      if config[:confluence_token] do
        {:ok, %{
          platform: :confluence,
          space: space,
          pages_created: count_pages_to_create(documentation)
        }}
      else
        {:error, "Confluence token required"}
      end
    end
    
    defp publish_to_platform(documentation, :static_site, config) do
      generator = config[:generator] || "hugo"
      
      # In real implementation, would generate static site
      {:ok, %{
        platform: :static_site,
        generator: generator,
        pages_generated: count_pages_to_create(documentation)
      }}
    end
    
    defp publish_to_platform(_documentation, platform, _config) do
      {:error, "Unsupported platform: #{platform}"}
    end
    
    defp count_files_to_write(documentation) do
      # Estimate based on documentation structure
      base_files = 1 # index file
      endpoint_files = length(documentation[:endpoints] || [])
      schema_files = length(documentation[:schemas] || [])
      
      base_files + endpoint_files + schema_files
    end
    
    defp count_pages_to_create(documentation) do
      # Similar to files but for page-based platforms
      count_files_to_write(documentation)
    end
  end
  
  # Tool-specific signal handlers using the new action system
  
  @impl true
  def handle_tool_signal(agent, %{"type" => "generate_from_openapi"} = signal) do
    spec_source = get_in(signal, ["data", "spec_source"])
    format = get_in(signal, ["data", "format"]) || :html
    theme = get_in(signal, ["data", "theme"]) || :modern
    include_examples = get_in(signal, ["data", "include_examples"]) || true
    include_schemas = get_in(signal, ["data", "include_schemas"]) || true
    output_path = get_in(signal, ["data", "output_path"])
    
    # Execute OpenAPI generation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, GenerateFromOpenAPIAction, %{
      spec_source: spec_source,
      format: format,
      theme: theme,
      include_examples: include_examples,
      include_schemas: include_schemas,
      output_path: output_path
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "generate_from_code"} = signal) do
    source_paths = get_in(signal, ["data", "source_paths"]) || []
    language = get_in(signal, ["data", "language"])
    doc_type = get_in(signal, ["data", "doc_type"]) || :library
    format = get_in(signal, ["data", "format"]) || :markdown
    include_private = get_in(signal, ["data", "include_private"]) || false
    include_tests = get_in(signal, ["data", "include_tests"]) || false
    template = get_in(signal, ["data", "template"])
    
    # Execute code generation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, GenerateFromCodeAction, %{
      source_paths: source_paths,
      language: language,
      doc_type: doc_type,
      format: format,
      include_private: include_private,
      include_tests: include_tests,
      template: template
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "validate_documentation"} = signal) do
    documentation = get_in(signal, ["data", "documentation"]) || %{}
    validation_rules = get_in(signal, ["data", "validation_rules"]) || [:completeness, :accuracy, :consistency, :examples]
    strict_mode = get_in(signal, ["data", "strict_mode"]) || false
    
    # Execute validation action
    {:ok, _ref} = __MODULE__.cmd_async(agent, ValidateDocumentationAction, %{
      documentation: documentation,
      validation_rules: validation_rules,
      strict_mode: strict_mode
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "merge_documentation"} = signal) do
    sources = get_in(signal, ["data", "sources"]) || []
    merge_strategy = get_in(signal, ["data", "merge_strategy"]) || :union
    conflict_resolution = get_in(signal, ["data", "conflict_resolution"]) || :last_wins
    output_format = get_in(signal, ["data", "output_format"]) || :html
    
    # Execute merge action
    {:ok, _ref} = __MODULE__.cmd_async(agent, MergeDocumentationAction, %{
      sources: sources,
      merge_strategy: merge_strategy,
      conflict_resolution: conflict_resolution,
      output_format: output_format
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, %{"type" => "publish_documentation"} = signal) do
    documentation = get_in(signal, ["data", "documentation"]) || %{}
    platforms = get_in(signal, ["data", "platforms"]) || [:file_system]
    publish_config = get_in(signal, ["data", "publish_config"]) || %{}
    version = get_in(signal, ["data", "version"])
    changelog = get_in(signal, ["data", "changelog"])
    
    # Execute publish action
    {:ok, _ref} = __MODULE__.cmd_async(agent, PublishDocumentationAction, %{
      documentation: documentation,
      platforms: platforms,
      publish_config: publish_config,
      version: version,
      changelog: changelog
    }, context: %{agent: agent})
    
    {:ok, agent}
  end
  
  def handle_tool_signal(agent, _signal), do: super(agent, _signal)
  
  # Process generation results to update cache and history
  @impl true
  def process_result(result, _context) do
    # Add generation timestamp
    Map.put(result, :generated_at, DateTime.utc_now())
  end
  
  # Override action result handler to update cache and history
  @impl true
  def handle_action_result(agent, ExecuteToolAction, {:ok, result}, metadata) do
    # Let parent handle the standard processing
    {:ok, agent} = super(agent, ExecuteToolAction, {:ok, result}, metadata)
    
    # Update documentation cache and history if successful and not from cache
    if result[:from_cache] == false && result[:result] do
      # Generate cache key based on parameters
      cache_key = generate_doc_cache_key(result[:result])
      
      # Update cache
      agent = put_in(agent.state.doc_cache[cache_key], %{
        documentation: result[:result],
        generated_at: DateTime.utc_now(),
        metadata: metadata
      })
      
      # Update generation history
      history_entry = %{
        type: :api_doc_generation,
        parameters: metadata[:original_params] || %{},
        result_summary: extract_result_summary(result[:result]),
        generated_at: DateTime.utc_now()
      }
      
      agent = update_in(agent.state.generation_history, fn history ->
        [history_entry | history]
        |> Enum.take(agent.state.max_history)
      end)
      
      {:ok, agent}
    else
      {:ok, agent}
    end
  end
  
  def handle_action_result(agent, action, result, metadata) when action in [
    GenerateFromOpenAPIAction, 
    GenerateFromCodeAction
  ] do
    # Update history for specific generation actions
    if match?({:ok, _}, result) do
      {:ok, result_data} = result
      
      history_entry = %{
        type: action_to_history_type(action),
        parameters: extract_action_params(result_data),
        result_summary: extract_result_summary(result_data),
        generated_at: DateTime.utc_now()
      }
      
      agent = update_in(agent.state.generation_history, fn history ->
        [history_entry | history]
        |> Enum.take(agent.state.max_history)
      end)
      
      # Emit completion signal
      signal = Jido.Signal.new!(%{
        type: "tool.doc_generation.completed",
        source: "agent:#{agent.id}",
        data: result_data
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
  
  defp generate_doc_cache_key(result) do
    # Create a cache key based on the type and source of documentation
    source = result[:spec_source] || result[:source_paths] || "unknown"
    doc_type = result[:doc_type] || result[:format] || "unknown"
    
    "#{doc_type}_#{:crypto.hash(:md5, inspect(source)) |> Base.encode16(case: :lower)}"
  end
  
  defp extract_result_summary(result) do
    %{
      format: result[:format],
      doc_type: result[:doc_type] || result[:type],
      pages_generated: result[:metadata][:functions_documented] || result[:metadata][:endpoints_count] || 0,
      size_estimate: String.length(inspect(result[:documentation] || "")) div 100 # Rough size in KB
    }
  end
  
  defp action_to_history_type(GenerateFromOpenAPIAction), do: :openapi_generation
  defp action_to_history_type(GenerateFromCodeAction), do: :code_generation
  defp action_to_history_type(_), do: :unknown_generation
  
  defp extract_action_params(result_data) do
    %{
      format: result_data[:format],
      source: result_data[:spec_source] || result_data[:source_paths],
      language: result_data[:language],
      theme: result_data[:theme]
    }
  end
end