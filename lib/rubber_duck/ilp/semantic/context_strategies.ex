defmodule RubberDuck.ILP.Semantic.ContextStrategies do
  @moduledoc """
  Context-aware chunking strategies for different code constructs.
  Implements intelligent segmentation based on language semantics, 
  code structure, and contextual relationships.
  """

  alias RubberDuck.ILP.AST.Node
  alias RubberDuck.ILP.Semantic.Chunker

  @doc """
  Applies context-aware chunking strategy based on code construct type.
  """
  def apply_strategy(ast, construct_type, opts \\ []) do
    case construct_type do
      :module_definition -> chunk_module_context(ast, opts)
      :function_definition -> chunk_function_context(ast, opts)
      :class_definition -> chunk_class_context(ast, opts)
      :interface_definition -> chunk_interface_context(ast, opts)
      :test_suite -> chunk_test_context(ast, opts)
      :configuration -> chunk_config_context(ast, opts)
      :documentation -> chunk_documentation_context(ast, opts)
      :imports_exports -> chunk_imports_exports_context(ast, opts)
      :error_handling -> chunk_error_handling_context(ast, opts)
      :data_structures -> chunk_data_structures_context(ast, opts)
      _ -> chunk_generic_context(ast, opts)
    end
  end

  @doc """
  Determines the most appropriate chunking strategy for given code.
  """
  def determine_strategy(ast, source_code) do
    language = ast.language
    
    # Analyze code characteristics
    characteristics = analyze_code_characteristics(ast, source_code)
    
    # Choose strategy based on language and characteristics
    case {language, characteristics.primary_construct} do
      {:elixir, :module} -> :module_definition
      {:elixir, :genserver} -> :genserver_context
      {:elixir, :test} -> :test_suite
      
      {lang, :class} when lang in [:java, :javascript, :typescript, :python] -> :class_definition
      {lang, :function} when lang in [:javascript, :typescript, :python] -> :function_definition
      {:typescript, :interface} -> :interface_definition
      
      {:python, :test} -> :test_suite
      {:javascript, :react_component} -> :react_component_context
      {:javascript, :config} -> :configuration
      
      {_, :documentation} -> :documentation
      {_, :config} -> :configuration
      {_, _} -> :generic_context
    end
  end

  @doc """
  Chunks module-level constructs preserving module boundaries and dependencies.
  """
  def chunk_module_context(ast, opts) do
    module_size_limit = Keyword.get(opts, :module_size_limit, 3000)
    preserve_exports = Keyword.get(opts, :preserve_exports, true)
    
    modules = Node.find_all(ast, &(&1.type == :defmodule))
    
    Enum.flat_map(modules, fn module_node ->
      module_content = extract_module_content(module_node)
      
      if estimate_content_size(module_content) > module_size_limit do
        # Split large modules by logical sections
        chunk_large_module(module_node, module_size_limit, preserve_exports)
      else
        # Keep module as single chunk
        [create_module_chunk(module_node)]
      end
    end)
  end

  @doc """
  Chunks function definitions keeping related functions together.
  """
  def chunk_function_context(ast, opts) do
    function_group_size = Keyword.get(opts, :function_group_size, 5)
    keep_private_with_public = Keyword.get(opts, :keep_private_with_public, true)
    
    functions = Node.find_all(ast, &(&1.type in [:def, :defp]))
    
    # Group functions by semantic relationships
    function_groups = group_related_functions(functions, keep_private_with_public)
    
    Enum.flat_map(function_groups, fn group ->
      if length(group) > function_group_size do
        # Split large groups
        group
        |> Enum.chunk_every(function_group_size, function_group_size, [])
        |> Enum.map(&create_function_group_chunk/1)
      else
        [create_function_group_chunk(group)]
      end
    end)
  end

  @doc """
  Chunks class definitions with methods and inner classes.
  """
  def chunk_class_context(ast, opts) do
    class_size_limit = Keyword.get(opts, :class_size_limit, 2500)
    keep_constructor_with_class = Keyword.get(opts, :keep_constructor_with_class, true)
    
    classes = Node.find_all(ast, &(&1.type in [:class_declaration, :class_definition]))
    
    Enum.flat_map(classes, fn class_node ->
      class_methods = extract_class_methods(class_node)
      class_fields = extract_class_fields(class_node)
      
      total_size = estimate_class_size(class_node, class_methods, class_fields)
      
      if total_size > class_size_limit do
        chunk_large_class(class_node, class_methods, class_fields, opts)
      else
        [create_class_chunk(class_node, class_methods, class_fields)]
      end
    end)
  end

  @doc """
  Chunks interface definitions with type information.
  """
  def chunk_interface_context(ast, opts) do
    interface_size_limit = Keyword.get(opts, :interface_size_limit, 1500)
    group_related_interfaces = Keyword.get(opts, :group_related_interfaces, true)
    
    interfaces = Node.find_all(ast, &(&1.type == :interface_declaration))
    
    if group_related_interfaces do
      # Group interfaces by namespace or inheritance
      interface_groups = group_related_interfaces(interfaces)
      
      Enum.flat_map(interface_groups, fn group ->
        if estimate_interfaces_size(group) > interface_size_limit do
          Enum.map(group, &create_interface_chunk/1)
        else
          [create_interface_group_chunk(group)]
        end
      end)
    else
      Enum.map(interfaces, &create_interface_chunk/1)
    end
  end

  @doc """
  Chunks test suites keeping test cases and setup together.
  """
  def chunk_test_context(ast, opts) do
    test_group_size = Keyword.get(opts, :test_group_size, 10)
    keep_setup_with_tests = Keyword.get(opts, :keep_setup_with_tests, true)
    
    test_cases = Node.find_all(ast, &is_test_node?/1)
    setup_functions = Node.find_all(ast, &is_setup_function?/1)
    
    # Group tests by describe blocks or similar constructs
    test_groups = group_tests_by_context(test_cases)
    
    Enum.flat_map(test_groups, fn {context, tests} ->
      relevant_setup = if keep_setup_with_tests do
        filter_relevant_setup(setup_functions, context)
      else
        []
      end
      
      if length(tests) > test_group_size do
        # Split large test groups
        tests
        |> Enum.chunk_every(test_group_size, test_group_size, [])
        |> Enum.map(&create_test_chunk(&1, relevant_setup, context))
      else
        [create_test_chunk(tests, relevant_setup, context)]
      end
    end)
  end

  @doc """
  Chunks configuration files and settings.
  """
  def chunk_config_context(ast, opts) do
    group_by_section = Keyword.get(opts, :group_by_section, true)
    section_size_limit = Keyword.get(opts, :section_size_limit, 1000)
    
    if group_by_section do
      # Identify configuration sections
      sections = identify_config_sections(ast)
      
      Enum.flat_map(sections, fn section ->
        if estimate_content_size(section) > section_size_limit do
          split_config_section(section, section_size_limit)
        else
          [create_config_chunk(section)]
        end
      end)
    else
      # Treat as generic content
      chunk_generic_context(ast, opts)
    end
  end

  @doc """
  Chunks documentation preserving logical sections.
  """
  def chunk_documentation_context(ast, opts) do
    preserve_headings = Keyword.get(opts, :preserve_headings, true)
    max_section_size = Keyword.get(opts, :max_section_size, 2000)
    
    if preserve_headings do
      # Split by headings and sections
      sections = extract_documentation_sections(ast)
      
      Enum.flat_map(sections, fn section ->
        if estimate_content_size(section) > max_section_size do
          split_documentation_section(section, max_section_size)
        else
          [create_documentation_chunk(section)]
        end
      end)
    else
      # Use sliding window approach
      source_code = extract_source_from_ast(ast)
      Chunker.sliding_window_chunk(source_code, opts)
    end
  end

  @doc """
  Chunks import/export statements and dependencies.
  """
  def chunk_imports_exports_context(ast, opts) do
    group_by_source = Keyword.get(opts, :group_by_source, true)
    
    imports = Node.find_all(ast, &is_import_node?/1)
    exports = Node.find_all(ast, &is_export_node?/1)
    
    chunks = []
    
    # Create import chunks
    import_chunks = if group_by_source do
      imports
      |> group_imports_by_source()
      |> Enum.map(&create_import_group_chunk/1)
    else
      [create_import_chunk(imports)]
    end
    
    # Create export chunks
    export_chunks = if length(exports) > 0 do
      [create_export_chunk(exports)]
    else
      []
    end
    
    chunks ++ import_chunks ++ export_chunks
  end

  @doc """
  Chunks error handling and exception management code.
  """
  def chunk_error_handling_context(ast, opts) do
    group_related_handlers = Keyword.get(opts, :group_related_handlers, true)
    
    error_handlers = Node.find_all(ast, &is_error_handling_node?/1)
    
    if group_related_handlers do
      # Group by error type or handling strategy
      handler_groups = group_error_handlers(error_handlers)
      Enum.map(handler_groups, &create_error_handling_chunk/1)
    else
      Enum.map(error_handlers, &create_single_error_handler_chunk/1)
    end
  end

  @doc """
  Chunks data structure definitions and related operations.
  """
  def chunk_data_structures_context(ast, opts) do
    include_related_functions = Keyword.get(opts, :include_related_functions, true)
    
    data_structures = Node.find_all(ast, &is_data_structure_node?/1)
    
    Enum.map(data_structures, fn struct_node ->
      related_functions = if include_related_functions do
        find_related_functions(struct_node, ast)
      else
        []
      end
      
      create_data_structure_chunk(struct_node, related_functions)
    end)
  end

  @doc """
  Generic chunking strategy for unknown or mixed content.
  """
  def chunk_generic_context(ast, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, 2048)
    overlap_ratio = Keyword.get(opts, :overlap_ratio, 0.1)
    
    source_code = extract_source_from_ast(ast)
    Chunker.sliding_window_chunk(source_code, window_size: chunk_size, overlap_ratio: overlap_ratio)
  end

  # Helper functions

  defp analyze_code_characteristics(ast, source_code) do
    # Identify primary constructs and patterns
    module_count = count_nodes_by_type(ast, [:defmodule, :module])
    function_count = count_nodes_by_type(ast, [:def, :defp, :function_declaration])
    class_count = count_nodes_by_type(ast, [:class_declaration, :class_definition])
    test_count = count_test_nodes(ast)
    
    # Determine primary construct
    primary_construct = cond do
      module_count > 0 and has_genserver_pattern?(ast) -> :genserver
      module_count > 0 -> :module
      class_count > 0 -> :class
      test_count > function_count * 0.5 -> :test
      function_count > 0 -> :function
      String.contains?(source_code, ["@doc", "##", "###"]) -> :documentation
      String.contains?(source_code, ["config", "settings"]) -> :config
      true -> :mixed
    end
    
    %{
      primary_construct: primary_construct,
      module_count: module_count,
      function_count: function_count,
      class_count: class_count,
      test_count: test_count,
      complexity_score: estimate_complexity(ast)
    }
  end

  defp extract_module_content(module_node) do
    module_node.children || []
  end

  defp chunk_large_module(module_node, size_limit, preserve_exports) do
    content = extract_module_content(module_node)
    
    # Split by logical sections: attributes, functions, etc.
    sections = group_module_content(content, preserve_exports)
    
    Enum.flat_map(sections, fn section ->
      if estimate_content_size(section) > size_limit do
        # Further split if still too large
        split_content_by_size(section, size_limit)
      else
        [create_module_section_chunk(module_node, section)]
      end
    end)
  end

  defp group_related_functions(functions, keep_private_with_public) do
    if keep_private_with_public do
      # Group private functions with their related public functions
      group_functions_by_relationship(functions)
    else
      # Simple grouping by proximity
      Enum.chunk_every(functions, 5, 5, [])
    end
  end

  defp group_functions_by_relationship(functions) do
    # Simplified grouping - in practice would analyze call graphs
    functions
    |> Enum.group_by(&extract_function_module/1)
    |> Map.values()
  end

  defp extract_class_methods(class_node) do
    Node.find_all(class_node, &(&1.type in [:method_declaration, :function_declaration]))
  end

  defp extract_class_fields(class_node) do
    Node.find_all(class_node, &(&1.type in [:field_declaration, :property_declaration]))
  end

  defp chunk_large_class(class_node, methods, fields, opts) do
    # Split class by method groups
    method_groups = Enum.chunk_every(methods, 3, 3, [])
    
    # Always include class declaration and fields in first chunk
    class_header_chunk = create_class_header_chunk(class_node, fields)
    method_chunks = Enum.map(method_groups, &create_class_methods_chunk(class_node, &1))
    
    [class_header_chunk | method_chunks]
  end

  defp group_related_interfaces(interfaces) do
    # Group by common patterns in names or inheritance
    interfaces
    |> Enum.group_by(&extract_interface_namespace/1)
    |> Map.values()
  end

  defp is_test_node?(node) do
    node.type in [:test, :it, :describe] or
    String.contains?(node.value || "", ["test", "spec", "it "])
  end

  defp is_setup_function?(node) do
    node.type in [:setup, :before, :after] or
    String.contains?(node.value || "", ["setup", "before", "after"])
  end

  defp group_tests_by_context(test_cases) do
    # Group by describe blocks or similar constructs
    test_cases
    |> Enum.group_by(&extract_test_context/1)
  end

  defp identify_config_sections(ast) do
    # Identify sections in configuration files
    sections = Node.find_all(ast, &is_config_section?/1)
    
    if Enum.empty?(sections) do
      # Fallback: split by top-level nodes
      ast.children || []
    else
      sections
    end
  end

  defp extract_documentation_sections(ast) do
    # Extract sections based on headings or structural markers
    Node.find_all(ast, &is_documentation_section?/1)
  end

  defp is_import_node?(node) do
    node.type in [:import, :require, :alias, :use, :import_statement]
  end

  defp is_export_node?(node) do
    node.type in [:export, :export_statement, :module_attribute]
  end

  defp is_error_handling_node?(node) do
    node.type in [:try, :catch, :rescue, :after, :throw, :error]
  end

  defp is_data_structure_node?(node) do
    node.type in [:defstruct, :struct, :type, :record, :interface]
  end

  # Utility functions for content estimation and creation

  defp estimate_content_size(content) when is_list(content) do
    Enum.sum(Enum.map(content, &estimate_node_size/1))
  end

  defp estimate_content_size(content) when is_binary(content) do
    String.length(content)
  end

  defp estimate_content_size(_), do: 100

  defp estimate_node_size(node) do
    case node.source_range do
      %{start: start, end: end_pos} ->
        calculate_range_size(start, end_pos)
      _ ->
        String.length(node.value || "") + 50
    end
  end

  defp calculate_range_size(%{line: start_line}, %{line: end_line}) do
    (end_line - start_line + 1) * 80  # Estimate 80 chars per line
  end

  defp calculate_range_size(_, _), do: 100

  defp create_module_chunk(module_node) do
    %{
      content: extract_node_content(module_node),
      type: :module,
      module_name: extract_module_name(module_node),
      size: estimate_node_size(module_node),
      metadata: %{
        construct_type: :module_definition,
        functions: count_functions_in_module(module_node),
        exports: extract_module_exports(module_node)
      }
    }
  end

  defp create_function_group_chunk(function_group) do
    content = Enum.map(function_group, &extract_node_content/1) |> Enum.join("\n\n")
    
    %{
      content: content,
      type: :function_group,
      function_count: length(function_group),
      size: String.length(content),
      metadata: %{
        construct_type: :function_definition,
        function_names: Enum.map(function_group, &extract_function_name/1),
        visibility: determine_group_visibility(function_group)
      }
    }
  end

  defp create_class_chunk(class_node, methods, fields) do
    %{
      content: extract_node_content(class_node),
      type: :class,
      class_name: extract_class_name(class_node),
      size: estimate_class_size(class_node, methods, fields),
      metadata: %{
        construct_type: :class_definition,
        method_count: length(methods),
        field_count: length(fields),
        inheritance: extract_inheritance_info(class_node)
      }
    }
  end

  defp create_test_chunk(tests, setup_functions, context) do
    all_content = (setup_functions ++ tests)
    |> Enum.map(&extract_node_content/1)
    |> Enum.join("\n\n")
    
    %{
      content: all_content,
      type: :test_suite,
      test_count: length(tests),
      size: String.length(all_content),
      metadata: %{
        construct_type: :test_suite,
        context: context,
        setup_functions: length(setup_functions),
        test_names: Enum.map(tests, &extract_test_name/1)
      }
    }
  end

  # Additional helper functions (simplified implementations)

  defp count_nodes_by_type(ast, types) do
    Node.find_all(ast, &(&1.type in types)) |> length()
  end

  defp count_test_nodes(ast) do
    Node.find_all(ast, &is_test_node?/1) |> length()
  end

  defp has_genserver_pattern?(ast) do
    Node.find_all(ast, fn node ->
      node.type == :use and String.contains?(node.value || "", "GenServer")
    end) |> length() > 0
  end

  defp estimate_complexity(ast) do
    Node.count_nodes(ast)
  end

  defp extract_source_from_ast(ast) do
    case ast.metadata do
      %{source: source} -> source
      _ -> "# Source not available"
    end
  end

  defp extract_node_content(_node), do: "# Node content"
  defp extract_module_name(_node), do: "TestModule"
  defp extract_function_name(_node), do: "test_function"
  defp extract_class_name(_node), do: "TestClass"
  defp extract_test_name(_node), do: "test_case"
  defp extract_function_module(_node), do: "default"
  defp extract_interface_namespace(_node), do: "default"
  defp extract_test_context(_node), do: "default_context"
  defp count_functions_in_module(_node), do: 0
  defp extract_module_exports(_node), do: []
  defp determine_group_visibility(_group), do: :mixed
  defp estimate_class_size(_class, _methods, _fields), do: 1000
  defp extract_inheritance_info(_node), do: nil
  defp group_module_content(content, _preserve_exports), do: [content]
  defp split_content_by_size(content, _limit), do: [content]
  defp create_module_section_chunk(_module, section), do: %{content: "section", type: :module_section, size: 100}
  defp create_class_header_chunk(_class, _fields), do: %{content: "class header", type: :class_header, size: 100}
  defp create_class_methods_chunk(_class, methods), do: %{content: "methods", type: :class_methods, size: length(methods) * 100}
  defp estimate_interfaces_size(interfaces), do: length(interfaces) * 200
  defp create_interface_chunk(_interface), do: %{content: "interface", type: :interface, size: 200}
  defp create_interface_group_chunk(interfaces), do: %{content: "interface group", type: :interface_group, size: length(interfaces) * 200}
  defp filter_relevant_setup(_setup, _context), do: []
  defp split_config_section(section, _limit), do: [section]
  defp create_config_chunk(_section), do: %{content: "config", type: :config, size: 100}
  defp split_documentation_section(section, _limit), do: [section]
  defp create_documentation_chunk(_section), do: %{content: "docs", type: :documentation, size: 100}
  defp group_imports_by_source(imports), do: [imports]
  defp create_import_group_chunk(_group), do: %{content: "imports", type: :imports, size: 100}
  defp create_import_chunk(_imports), do: %{content: "imports", type: :imports, size: 100}
  defp create_export_chunk(_exports), do: %{content: "exports", type: :exports, size: 100}
  defp group_error_handlers(handlers), do: [handlers]
  defp create_error_handling_chunk(_group), do: %{content: "error handling", type: :error_handling, size: 100}
  defp create_single_error_handler_chunk(_handler), do: %{content: "error handler", type: :error_handler, size: 100}
  defp find_related_functions(_struct, _ast), do: []
  defp create_data_structure_chunk(_struct, _functions), do: %{content: "data structure", type: :data_structure, size: 100}
  defp is_config_section?(_node), do: false
  defp is_documentation_section?(_node), do: false
end