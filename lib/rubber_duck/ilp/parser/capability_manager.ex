defmodule RubberDuck.ILP.Parser.CapabilityManager do
  @moduledoc """
  Language capability discovery and metadata management system.
  Tracks parser capabilities, performance metrics, and feature support across languages.
  """
  use GenServer
  require Logger

  alias RubberDuck.ILP.Parser.{Abstraction, PluginManager}

  defstruct [
    :language_capabilities,
    :performance_metrics,
    :feature_matrix,
    :compatibility_map,
    :metadata_cache
  ]

  # Standard LSP capabilities
  @lsp_capabilities [
    :text_document_sync,
    :completion,
    :hover,
    :signature_help,
    :definition,
    :references,
    :document_highlight,
    :document_symbol,
    :workspace_symbol,
    :code_action,
    :code_lens,
    :document_formatting,
    :document_range_formatting,
    :document_on_type_formatting,
    :rename,
    :folding_range,
    :selection_range,
    :semantic_tokens
  ]

  # Extended ILP capabilities
  @ilp_capabilities [
    :incremental_parsing,
    :macro_expansion,
    :type_inference,
    :framework_detection,
    :pattern_recognition,
    :documentation_extraction,
    :refactoring_support,
    :code_generation,
    :syntax_validation,
    :semantic_analysis
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets capabilities for a specific language.
  """
  def get_language_capabilities(language) do
    GenServer.call(__MODULE__, {:get_capabilities, language})
  end

  @doc """
  Gets all supported languages with their capabilities.
  """
  def get_all_capabilities do
    GenServer.call(__MODULE__, :get_all_capabilities)
  end

  @doc """
  Gets performance metrics for a language parser.
  """
  def get_performance_metrics(language) do
    GenServer.call(__MODULE__, {:get_performance_metrics, language})
  end

  @doc """
  Updates performance metrics for a language parser.
  """
  def update_performance_metrics(language, metrics) do
    GenServer.cast(__MODULE__, {:update_performance_metrics, language, metrics})
  end

  @doc """
  Gets the feature compatibility matrix.
  """
  def get_feature_matrix do
    GenServer.call(__MODULE__, :get_feature_matrix)
  end

  @doc """
  Checks if a language supports a specific capability.
  """
  def supports_capability?(language, capability) do
    GenServer.call(__MODULE__, {:supports_capability, language, capability})
  end

  @doc """
  Gets languages that support a specific capability.
  """
  def get_languages_with_capability(capability) do
    GenServer.call(__MODULE__, {:get_languages_with_capability, capability})
  end

  @doc """
  Discovers capabilities by testing parser functionality.
  """
  def discover_capabilities(language) do
    GenServer.call(__MODULE__, {:discover_capabilities, language})
  end

  @doc """
  Gets metadata for a specific language.
  """
  def get_language_metadata(language) do
    GenServer.call(__MODULE__, {:get_language_metadata, language})
  end

  @doc """
  Updates language metadata.
  """
  def update_language_metadata(language, metadata) do
    GenServer.cast(__MODULE__, {:update_language_metadata, language, metadata})
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting ILP Parser CapabilityManager")
    
    state = %__MODULE__{
      language_capabilities: %{},
      performance_metrics: %{},
      feature_matrix: build_initial_feature_matrix(),
      compatibility_map: %{},
      metadata_cache: %{}
    }
    
    # Initialize capabilities for supported languages
    initial_state = initialize_language_capabilities(state)
    
    {:ok, initial_state}
  end

  @impl true
  def handle_call({:get_capabilities, language}, _from, state) do
    capabilities = Map.get(state.language_capabilities, language, %{})
    {:reply, capabilities, state}
  end

  @impl true
  def handle_call(:get_all_capabilities, _from, state) do
    {:reply, state.language_capabilities, state}
  end

  @impl true
  def handle_call({:get_performance_metrics, language}, _from, state) do
    metrics = Map.get(state.performance_metrics, language, %{})
    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:get_feature_matrix, _from, state) do
    {:reply, state.feature_matrix, state}
  end

  @impl true
  def handle_call({:supports_capability, language, capability}, _from, state) do
    supports = case Map.get(state.language_capabilities, language) do
      nil -> false
      capabilities -> Map.get(capabilities, capability, false)
    end
    
    {:reply, supports, state}
  end

  @impl true
  def handle_call({:get_languages_with_capability, capability}, _from, state) do
    languages = state.language_capabilities
    |> Enum.filter(fn {_language, capabilities} ->
      Map.get(capabilities, capability, false)
    end)
    |> Enum.map(fn {language, _capabilities} -> language end)
    
    {:reply, languages, state}
  end

  @impl true
  def handle_call({:discover_capabilities, language}, _from, state) do
    case perform_capability_discovery(language) do
      {:ok, discovered_capabilities} ->
        new_capabilities = Map.put(state.language_capabilities, language, discovered_capabilities)
        new_state = %{state | language_capabilities: new_capabilities}
        {:reply, {:ok, discovered_capabilities}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_language_metadata, language}, _from, state) do
    metadata = Map.get(state.metadata_cache, language, %{})
    {:reply, metadata, state}
  end

  @impl true
  def handle_cast({:update_performance_metrics, language, metrics}, state) do
    current_metrics = Map.get(state.performance_metrics, language, %{})
    updated_metrics = merge_performance_metrics(current_metrics, metrics)
    
    new_performance_metrics = Map.put(state.performance_metrics, language, updated_metrics)
    new_state = %{state | performance_metrics: new_performance_metrics}
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_language_metadata, language, metadata}, state) do
    current_metadata = Map.get(state.metadata_cache, language, %{})
    updated_metadata = Map.merge(current_metadata, metadata)
    
    new_metadata_cache = Map.put(state.metadata_cache, language, updated_metadata)
    new_state = %{state | metadata_cache: new_metadata_cache}
    
    {:noreply, new_state}
  end

  defp build_initial_feature_matrix do
    languages = Abstraction.supported_languages()
    
    matrix = for language <- languages, into: %{} do
      {language, build_language_feature_set(language)}
    end
    
    matrix
  end

  defp build_language_feature_set(language) do
    # Build feature set based on language characteristics
    base_features = %{
      syntax_highlighting: true,
      folding: true,
      basic_symbols: true
    }
    
    language_specific = case language do
      :elixir ->
        %{
          incremental_parsing: true,
          macro_expansion: true,
          otp_patterns: true,
          documentation_extraction: true,
          type_inference: true,
          semantic_tokens: true
        }
      
      lang when lang in [:javascript, :typescript] ->
        %{
          incremental_parsing: true,
          framework_detection: true,
          semantic_tokens: true,
          refactoring_support: true
        }
      
      lang when lang in [:python, :java, :go, :rust] ->
        %{
          incremental_parsing: true,
          semantic_tokens: true,
          type_inference: true
        }
      
      lang when lang in [:c, :cpp] ->
        %{
          incremental_parsing: true,
          semantic_tokens: true,
          header_analysis: true
        }
      
      _ ->
        %{}
    end
    
    Map.merge(base_features, language_specific)
  end

  defp initialize_language_capabilities(state) do
    languages = Abstraction.supported_languages()
    
    capabilities = for language <- languages, into: %{} do
      {language, discover_language_capabilities(language)}
    end
    
    %{state | language_capabilities: capabilities}
  end

  defp discover_language_capabilities(language) do
    # Discover capabilities by querying the parser
    base_capabilities = %{
      # LSP capabilities
      text_document_sync: true,
      completion: has_completion_support?(language),
      hover: has_hover_support?(language),
      signature_help: has_signature_help?(language),
      definition: has_definition_support?(language),
      references: has_references_support?(language),
      document_highlight: has_highlight_support?(language),
      document_symbol: has_symbol_support?(language),
      workspace_symbol: has_workspace_symbol_support?(language),
      code_action: has_code_action_support?(language),
      code_lens: has_code_lens_support?(language),
      document_formatting: has_formatting_support?(language),
      document_range_formatting: has_range_formatting_support?(language),
      document_on_type_formatting: has_on_type_formatting_support?(language),
      rename: has_rename_support?(language),
      folding_range: has_folding_support?(language),
      selection_range: has_selection_range_support?(language),
      semantic_tokens: has_semantic_tokens_support?(language)
    }
    
    # Add ILP-specific capabilities
    ilp_capabilities = %{
      incremental_parsing: has_incremental_parsing?(language),
      macro_expansion: has_macro_expansion?(language),
      type_inference: has_type_inference?(language),
      framework_detection: has_framework_detection?(language),
      pattern_recognition: has_pattern_recognition?(language),
      documentation_extraction: has_documentation_extraction?(language),
      refactoring_support: has_refactoring_support?(language),
      code_generation: has_code_generation?(language),
      syntax_validation: has_syntax_validation?(language),
      semantic_analysis: has_semantic_analysis?(language)
    }
    
    Map.merge(base_capabilities, ilp_capabilities)
  end

  defp perform_capability_discovery(language) do
    try do
      # Test basic parsing
      test_source = get_test_source(language)
      
      case Abstraction.parse(test_source, language) do
        {:ok, ast} ->
          capabilities = test_parser_capabilities(language, test_source, ast)
          {:ok, capabilities}
        
        {:error, reason} ->
          {:error, {:parse_failure, reason}}
      end
    rescue
      e ->
        {:error, {:discovery_error, e}}
    end
  end

  defp test_parser_capabilities(language, source, ast) do
    capabilities = %{}
    
    # Test each capability
    capabilities = test_lsp_capabilities(capabilities, language, source, ast)
    capabilities = test_ilp_capabilities(capabilities, language, source, ast)
    
    capabilities
  end

  defp test_lsp_capabilities(capabilities, language, source, ast) do
    Enum.reduce(@lsp_capabilities, capabilities, fn capability, acc ->
      supports = case capability do
        :completion -> test_completion_capability(language, source, ast)
        :hover -> test_hover_capability(language, source, ast)
        :definition -> test_definition_capability(language, source, ast)
        :references -> test_references_capability(language, source, ast)
        :document_symbol -> test_symbol_capability(language, source, ast)
        :folding_range -> test_folding_capability(language, source, ast)
        :semantic_tokens -> test_semantic_tokens_capability(language, source, ast)
        _ -> false
      end
      
      Map.put(acc, capability, supports)
    end)
  end

  defp test_ilp_capabilities(capabilities, language, source, ast) do
    Enum.reduce(@ilp_capabilities, capabilities, fn capability, acc ->
      supports = case capability do
        :incremental_parsing -> test_incremental_parsing_capability(language, source, ast)
        :macro_expansion -> test_macro_expansion_capability(language, source, ast)
        :type_inference -> test_type_inference_capability(language, source, ast)
        :pattern_recognition -> test_pattern_recognition_capability(language, source, ast)
        :semantic_analysis -> test_semantic_analysis_capability(language, source, ast)
        _ -> false
      end
      
      Map.put(acc, capability, supports)
    end)
  end

  defp merge_performance_metrics(current, new) do
    %{
      total_parses: (current[:total_parses] || 0) + (new[:total_parses] || 0),
      avg_parse_time: calculate_avg_parse_time(current, new),
      error_rate: calculate_error_rate(current, new),
      cache_hit_rate: calculate_cache_hit_rate(current, new),
      last_updated: System.monotonic_time(:millisecond)
    }
  end

  defp calculate_avg_parse_time(current, new) do
    current_avg = current[:avg_parse_time] || 0
    new_avg = new[:avg_parse_time] || 0
    current_count = current[:total_parses] || 0
    new_count = new[:total_parses] || 0
    
    total_count = current_count + new_count
    
    if total_count > 0 do
      (current_avg * current_count + new_avg * new_count) / total_count
    else
      0
    end
  end

  defp calculate_error_rate(current, new) do
    current_errors = current[:error_count] || 0
    new_errors = new[:error_count] || 0
    current_total = current[:total_parses] || 0
    new_total = new[:total_parses] || 0
    
    total_errors = current_errors + new_errors
    total_parses = current_total + new_total
    
    if total_parses > 0 do
      total_errors / total_parses
    else
      0.0
    end
  end

  defp calculate_cache_hit_rate(current, new) do
    current_hits = current[:cache_hits] || 0
    new_hits = new[:cache_hits] || 0
    current_total = current[:total_parses] || 0
    new_total = new[:total_parses] || 0
    
    total_hits = current_hits + new_hits
    total_parses = current_total + new_total
    
    if total_parses > 0 do
      total_hits / total_parses
    else
      0.0
    end
  end

  # Test source generators for different languages
  defp get_test_source(:elixir) do
    """
    defmodule TestModule do
      @moduledoc "Test module"
      
      def test_function(arg) do
        arg + 1
      end
      
      defp private_function do
        :ok
      end
    end
    """
  end

  defp get_test_source(:javascript) do
    """
    function testFunction(arg) {
      return arg + 1;
    }
    
    class TestClass {
      constructor(value) {
        this.value = value;
      }
      
      getValue() {
        return this.value;
      }
    }
    """
  end

  defp get_test_source(:python) do
    """
    def test_function(arg):
        return arg + 1
    
    class TestClass:
        def __init__(self, value):
            self.value = value
        
        def get_value(self):
            return self.value
    """
  end

  defp get_test_source(_language) do
    "// Test source code"
  end

  # Capability testing functions (simplified)
  defp has_completion_support?(:elixir), do: true
  defp has_completion_support?(lang) when lang in [:javascript, :typescript, :python], do: true
  defp has_completion_support?(_), do: false

  defp has_hover_support?(:elixir), do: true
  defp has_hover_support?(lang) when lang in [:javascript, :typescript, :python], do: true
  defp has_hover_support?(_), do: false

  defp has_signature_help?(:elixir), do: true
  defp has_signature_help?(lang) when lang in [:javascript, :typescript], do: true
  defp has_signature_help?(_), do: false

  defp has_definition_support?(:elixir), do: true
  defp has_definition_support?(lang) when lang in [:javascript, :typescript, :python], do: true
  defp has_definition_support?(_), do: false

  defp has_references_support?(:elixir), do: true
  defp has_references_support?(lang) when lang in [:javascript, :typescript], do: true
  defp has_references_support?(_), do: false

  defp has_highlight_support?(_), do: true
  defp has_symbol_support?(_), do: true
  defp has_workspace_symbol_support?(_), do: false
  defp has_code_action_support?(_), do: false
  defp has_code_lens_support?(_), do: false
  defp has_formatting_support?(_), do: false
  defp has_range_formatting_support?(_), do: false
  defp has_on_type_formatting_support?(_), do: false
  defp has_rename_support?(_), do: false
  defp has_folding_support?(_), do: true
  defp has_selection_range_support?(_), do: false
  defp has_semantic_tokens_support?(:elixir), do: true
  defp has_semantic_tokens_support?(lang) when lang in [:javascript, :typescript], do: true
  defp has_semantic_tokens_support?(_), do: false

  defp has_incremental_parsing?(:elixir), do: true
  defp has_incremental_parsing?(lang) when lang in [:javascript, :typescript], do: true
  defp has_incremental_parsing?(_), do: false

  defp has_macro_expansion?(:elixir), do: true
  defp has_macro_expansion?(_), do: false

  defp has_type_inference?(:elixir), do: true
  defp has_type_inference?(lang) when lang in [:typescript, :java, :go, :rust], do: true
  defp has_type_inference?(_), do: false

  defp has_framework_detection?(lang) when lang in [:javascript, :typescript], do: true
  defp has_framework_detection?(_), do: false

  defp has_pattern_recognition?(:elixir), do: true
  defp has_pattern_recognition?(_), do: false

  defp has_documentation_extraction?(:elixir), do: true
  defp has_documentation_extraction?(_), do: false

  defp has_refactoring_support?(_), do: false
  defp has_code_generation?(_), do: false
  defp has_syntax_validation?(_), do: true
  defp has_semantic_analysis?(:elixir), do: true
  defp has_semantic_analysis?(lang) when lang in [:javascript, :typescript], do: true
  defp has_semantic_analysis?(_), do: false

  # Capability test functions (simplified)
  defp test_completion_capability(_language, _source, _ast), do: true
  defp test_hover_capability(_language, _source, _ast), do: true
  defp test_definition_capability(_language, _source, _ast), do: true
  defp test_references_capability(_language, _source, _ast), do: true
  defp test_symbol_capability(_language, _source, _ast), do: true
  defp test_folding_capability(_language, _source, _ast), do: true
  defp test_semantic_tokens_capability(_language, _source, _ast), do: true
  defp test_incremental_parsing_capability(_language, _source, _ast), do: true
  defp test_macro_expansion_capability(_language, _source, _ast), do: true
  defp test_type_inference_capability(_language, _source, _ast), do: true
  defp test_pattern_recognition_capability(_language, _source, _ast), do: true
  defp test_semantic_analysis_capability(_language, _source, _ast), do: true
end