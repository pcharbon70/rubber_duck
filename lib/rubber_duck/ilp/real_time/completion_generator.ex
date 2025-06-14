defmodule RubberDuck.ILP.RealTime.CompletionGenerator do
  @moduledoc """
  GenStage consumer for generating intelligent completions based on semantic analysis.
  Final stage in the real-time processing pipeline.
  """
  use GenStage
  require Logger

  defstruct [:completion_cache, :template_store, :metrics]

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting ILP RealTime CompletionGenerator")
    subscribe_to = Keyword.get(opts, :subscribe_to, [])
    
    state = %__MODULE__{
      completion_cache: %{},
      template_store: load_completion_templates(),
      metrics: %{
        completions_generated: 0,
        avg_generation_time: 0,
        template_usage: %{}
      }
    }
    
    {:consumer, state, subscribe_to: subscribe_to}
  end

  @impl true
  def handle_events(events, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    processed_events = 
      events
      |> Enum.map(&generate_completion/1)
      |> Enum.filter(&(&1 != nil))
    
    # Send completions to clients
    Enum.each(processed_events, &send_completion_to_client/1)
    
    end_time = System.monotonic_time(:microsecond)
    processing_time = end_time - start_time
    
    new_state = update_metrics(state, processing_time, length(processed_events))
    
    {:noreply, [], new_state}
  end

  defp generate_completion(%{type: :completion, semantic_info: semantic_info} = request) do
    completion_items = case semantic_info.completion_type do
      :function_call ->
        generate_function_completions(semantic_info, request)
      
      :module_attribute ->
        generate_attribute_completions(semantic_info, request)
      
      :variable ->
        generate_variable_completions(semantic_info, request)
      
      :keyword ->
        generate_keyword_completions(semantic_info, request)
      
      :import ->
        generate_import_completions(semantic_info, request)
      
      _ ->
        generate_generic_completions(semantic_info, request)
    end
    
    Map.put(request, :completion_items, completion_items)
  end

  defp generate_completion(%{type: type} = request) when type != :completion do
    # Pass through non-completion requests
    request
  end

  defp generate_completion(_request), do: nil

  defp generate_function_completions(semantic_info, request) do
    available_functions = semantic_info.available_symbols.local ++ 
                         semantic_info.available_symbols.imported ++
                         semantic_info.available_symbols.builtin
    
    available_functions
    |> filter_by_context(semantic_info)
    |> sort_by_relevance(semantic_info.confidence_scores)
    |> Enum.map(&create_function_completion_item/1)
    |> add_snippet_completions(semantic_info.snippet_suggestions)
  end

  defp generate_attribute_completions(semantic_info, request) do
    module_attributes = [
      "@moduledoc", "@doc", "@spec", "@type", "@typep",
      "@behaviour", "@callback", "@impl", "@deprecated",
      "@since", "@vsn", "@author"
    ]
    
    module_attributes
    |> Enum.map(&create_attribute_completion_item/1)
    |> sort_by_usage_frequency(semantic_info)
  end

  defp generate_variable_completions(semantic_info, request) do
    semantic_info.scope_context.local_variables
    |> Enum.map(&create_variable_completion_item/1)
    |> sort_by_scope_distance(request.position)
  end

  defp generate_keyword_completions(semantic_info, request) do
    elixir_keywords = [
      "case", "cond", "if", "unless", "with", "for", "receive",
      "try", "rescue", "catch", "after", "else", "do", "end",
      "def", "defp", "defmodule", "defstruct", "defprotocol",
      "defimpl", "defmacro", "defmacrop", "defguard", "defguardp"
    ]
    
    elixir_keywords
    |> filter_contextual_keywords(semantic_info)
    |> Enum.map(&create_keyword_completion_item/1)
  end

  defp generate_import_completions(semantic_info, request) do
    semantic_info.import_suggestions
    |> Enum.map(&create_import_completion_item/1)
    |> sort_by_import_frequency()
  end

  defp generate_generic_completions(semantic_info, request) do
    # Fallback completions when context is unclear
    []
  end

  defp create_function_completion_item(%{name: name, arity: arity, documentation: doc}) do
    %{
      label: "#{name}/#{arity}",
      kind: :function,
      detail: build_function_signature(name, arity),
      documentation: doc,
      insert_text: generate_function_snippet(name, arity),
      sort_text: "0#{name}",  # High priority
      filter_text: name
    }
  end

  defp create_function_completion_item(name) when is_atom(name) do
    %{
      label: Atom.to_string(name),
      kind: :function,
      detail: "function",
      insert_text: Atom.to_string(name),
      sort_text: "1#{name}",
      filter_text: Atom.to_string(name)
    }
  end

  defp create_attribute_completion_item(attribute) do
    %{
      label: attribute,
      kind: :property,
      detail: "module attribute",
      insert_text: attribute <> " ",
      sort_text: "0#{attribute}",
      filter_text: attribute
    }
  end

  defp create_variable_completion_item(%{name: name, type: type}) do
    %{
      label: name,
      kind: :variable,
      detail: "#{type} variable",
      insert_text: name,
      sort_text: "0#{name}",
      filter_text: name
    }
  end

  defp create_variable_completion_item(name) when is_binary(name) do
    %{
      label: name,
      kind: :variable,
      detail: "variable",
      insert_text: name,
      sort_text: "1#{name}",
      filter_text: name
    }
  end

  defp create_keyword_completion_item(keyword) do
    snippet = get_keyword_snippet(keyword)
    
    %{
      label: keyword,
      kind: :keyword,
      detail: "Elixir keyword",
      insert_text: snippet,
      sort_text: "0#{keyword}",
      filter_text: keyword
    }
  end

  defp create_import_completion_item(%{module: module, suggestion: suggestion}) do
    %{
      label: "import #{module}",
      kind: :module,
      detail: suggestion,
      insert_text: "import #{module}",
      sort_text: "2import_#{module}",
      filter_text: "import #{module}"
    }
  end

  defp filter_by_context(functions, semantic_info) do
    # Filter functions based on current context and expected types
    Enum.filter(functions, fn func ->
      is_contextually_relevant?(func, semantic_info)
    end)
  end

  defp sort_by_relevance(items, confidence_scores) do
    Enum.sort_by(items, fn item ->
      -calculate_item_relevance(item, confidence_scores)
    end)
  end

  defp add_snippet_completions(items, snippet_suggestions) do
    snippet_items = Enum.map(snippet_suggestions, &create_snippet_completion_item/1)
    items ++ snippet_items
  end

  defp create_snippet_completion_item(%{name: name, template: template, description: desc}) do
    %{
      label: name,
      kind: :snippet,
      detail: desc,
      insert_text: template,
      sort_text: "9#{name}",  # Lower priority than exact matches
      filter_text: name
    }
  end

  defp sort_by_usage_frequency(items, semantic_info) do
    # Sort by how frequently each item is used in similar contexts
    Enum.sort_by(items, fn item ->
      -get_usage_frequency(item.label, semantic_info)
    end)
  end

  defp sort_by_scope_distance(variables, position) do
    # Sort variables by scope distance (closer scopes first)
    Enum.sort_by(variables, fn var ->
      calculate_scope_distance(var, position)
    end)
  end

  defp filter_contextual_keywords(keywords, semantic_info) do
    # Filter keywords based on current syntactic context
    Enum.filter(keywords, fn keyword ->
      is_keyword_applicable?(keyword, semantic_info)
    end)
  end

  defp sort_by_import_frequency(imports) do
    # Sort by how commonly these modules are imported
    Enum.sort_by(imports, fn import ->
      -get_import_frequency(import.label)
    end)
  end

  defp build_function_signature(name, arity) do
    params = 1..arity |> Enum.map(fn i -> "arg#{i}" end) |> Enum.join(", ")
    "#{name}(#{params})"
  end

  defp generate_function_snippet(name, 0) do
    "#{name}()"
  end

  defp generate_function_snippet(name, arity) do
    params = 1..arity 
    |> Enum.map(fn i -> "${#{i}:arg#{i}}" end) 
    |> Enum.join(", ")
    
    "#{name}(#{params})"
  end

  defp get_keyword_snippet("case") do
    """
    case ${1:expression} do
      ${2:pattern} -> ${3:result}
    end
    """
  end

  defp get_keyword_snippet("if") do
    """
    if ${1:condition} do
      ${2:true_branch}
    else
      ${3:false_branch}
    end
    """
  end

  defp get_keyword_snippet("def") do
    """
    def ${1:function_name}(${2:params}) do
      ${3:body}
    end
    """
  end

  defp get_keyword_snippet("defmodule") do
    """
    defmodule ${1:ModuleName} do
      ${2:body}
    end
    """
  end

  defp get_keyword_snippet(keyword), do: keyword

  defp send_completion_to_client(%{id: request_id, completion_items: items} = request) do
    # Send completion response back to LSP client
    response = %{
      id: request_id,
      result: %{
        is_incomplete: false,
        items: items
      },
      response_time: System.monotonic_time(:millisecond) - request.timestamp
    }
    
    # In a real implementation, this would send via LSP protocol
    Logger.debug("Generated #{length(items)} completions for request #{request_id}")
    response
  end

  defp send_completion_to_client(request) do
    Logger.debug("No completions generated for request #{request.id}")
    nil
  end

  # Helper function implementations
  defp is_contextually_relevant?(_func, _semantic_info), do: true
  defp calculate_item_relevance(_item, _confidence_scores), do: 0.8
  defp get_usage_frequency(_label, _semantic_info), do: 0.5
  defp calculate_scope_distance(_var, _position), do: 1
  defp is_keyword_applicable?(_keyword, _semantic_info), do: true
  defp get_import_frequency(_label), do: 0.3

  defp load_completion_templates do
    %{
      function_templates: load_function_templates(),
      module_templates: load_module_templates(),
      test_templates: load_test_templates()
    }
  end

  defp load_function_templates do
    [
      %{name: "gen_server_function", template: "def handle_call(${1:request}, ${2:from}, state) do\n  ${3:body}\nend"},
      %{name: "supervisor_function", template: "def init(${1:args}) do\n  children = [\n    ${2:child_spec}\n  ]\n  Supervisor.init(children, strategy: ${3::one_for_one})\nend"}
    ]
  end

  defp load_module_templates, do: []
  defp load_test_templates, do: []

  defp update_metrics(state, processing_time_us, completion_count) do
    current_completions = state.metrics.completions_generated
    current_avg = state.metrics.avg_generation_time
    
    new_completions = current_completions + completion_count
    new_avg = (current_avg * current_completions + processing_time_us) / new_completions
    
    %{state |
      metrics: %{state.metrics |
        completions_generated: new_completions,
        avg_generation_time: new_avg
      }
    }
  end
end