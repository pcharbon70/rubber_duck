defmodule RubberDuck.Jido.Actions.Provider.Local.ListAvailableModelsAction do
  @moduledoc """
  Action for discovering and listing locally available language models.

  This action scans local directories, model repositories, and caches to discover
  available models, analyze their characteristics, compatibility, and readiness
  for loading. Supports multiple model formats and provides detailed metadata.

  ## Parameters

  - `operation` - List operation type (required: :scan, :cached, :detailed, :compatible)
  - `scan_paths` - Directories to scan for models (default: standard paths)
  - `model_formats` - Model formats to include (default: :all)
  - `include_metadata` - Include detailed model metadata (default: true)
  - `check_compatibility` - Check system compatibility (default: true)
  - `sort_by` - Sort criteria for results (default: :name)
  - `filter_criteria` - Filtering criteria for models (default: %{})
  - `cache_results` - Cache scan results (default: true)

  ## Returns

  - `{:ok, result}` - Model listing completed successfully
  - `{:error, reason}` - Model listing failed

  ## Example

      params = %{
        operation: :detailed,
        scan_paths: ["/models", "/opt/ai-models"],
        model_formats: [:gguf, :huggingface, :pytorch],
        include_metadata: true,
        check_compatibility: true,
        sort_by: :size,
        filter_criteria: %{
          min_size_mb: 1000,
          max_size_mb: 20000,
          task_types: [:text_generation, :chat]
        }
      }

      {:ok, result} = ListAvailableModelsAction.run(params, context)
  """

  use Jido.Action,
    name: "list_available_models",
    description: "Discover and list locally available language models",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "List operation (scan, cached, detailed, compatible, search)"
      ],
      scan_paths: [
        type: {:list, :string},
        default: [],
        doc: "Directories to scan for models (empty = use default paths)"
      ],
      model_formats: [
        type: {:union, [:atom, {:list, :atom}]},
        default: :all,
        doc: "Model formats to include (all, gguf, huggingface, pytorch, onnx, safetensors)"
      ],
      include_metadata: [
        type: :boolean,
        default: true,
        doc: "Include detailed model metadata"
      ],
      check_compatibility: [
        type: :boolean,
        default: true,
        doc: "Check system compatibility for each model"
      ],
      sort_by: [
        type: :atom,
        default: :name,
        doc: "Sort criteria (name, size, date, format, compatibility)"
      ],
      filter_criteria: [
        type: :map,
        default: %{},
        doc: "Filtering criteria for models"
      ],
      cache_results: [
        type: :boolean,
        default: true,
        doc: "Cache scan results for faster future access"
      ],
      deep_scan: [
        type: :boolean,
        default: false,
        doc: "Perform deep analysis of model files"
      ],
      include_remote: [
        type: :boolean,
        default: false,
        doc: "Include remote/downloadable models"
      ]
    ]

  require Logger

  @valid_operations [:scan, :cached, :detailed, :compatible, :search]
  @valid_model_formats [:gguf, :huggingface, :pytorch, :onnx, :safetensors, :tensorflow, :coreml]
  @valid_sort_criteria [:name, :size, :date, :format, :compatibility, :popularity]

  @default_scan_paths [
    "/models",
    "/opt/models",
    "/opt/ai-models",
    "~/.cache/huggingface",
    "~/.cache/torch",
    "~/.local/share/models",
    "./models"
  ]

  @model_file_patterns %{
    gguf: ["*.gguf"],
    huggingface: ["config.json", "pytorch_model.bin", "model.safetensors"],
    pytorch: ["*.bin", "*.pth", "*.pt"],
    onnx: ["*.onnx"],
    safetensors: ["*.safetensors"],
    tensorflow: ["saved_model.pb", "*.tf"],
    coreml: ["*.mlmodel", "*.mlpackage"]
  }

  @impl true
  def run(params, context) do
    Logger.info("Executing model listing operation: #{params.operation}")

    with {:ok, validated_params} <- validate_listing_parameters(params),
         {:ok, scan_config} <- prepare_scan_configuration(validated_params),
         {:ok, result} <- execute_listing_operation(scan_config, context) do
      
      emit_models_listed_signal(params.operation, result)
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Model listing operation failed: #{inspect(reason)}")
        emit_models_listing_error_signal(params.operation, reason)
        {:error, reason}
    end
  end

  # Parameter validation

  defp validate_listing_parameters(params) do
    with {:ok, _} <- validate_operation(params.operation),
         {:ok, _} <- validate_model_formats(params.model_formats),
         {:ok, _} <- validate_sort_criteria(params.sort_by),
         {:ok, _} <- validate_scan_paths(params.scan_paths) do
      
      {:ok, params}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end

  defp validate_operation(operation) do
    if operation in @valid_operations do
      {:ok, operation}
    else
      {:error, {:invalid_operation, operation, @valid_operations}}
    end
  end

  defp validate_model_formats(:all), do: {:ok, @valid_model_formats}
  defp validate_model_formats(formats) when is_list(formats) do
    invalid_formats = formats -- @valid_model_formats
    
    if Enum.empty?(invalid_formats) do
      {:ok, formats}
    else
      {:error, {:invalid_model_formats, invalid_formats, @valid_model_formats}}
    end
  end
  defp validate_model_formats(format) when is_atom(format) do
    if format in @valid_model_formats do
      {:ok, [format]}
    else
      {:error, {:invalid_model_format, format, @valid_model_formats}}
    end
  end
  defp validate_model_formats(formats), do: {:error, {:invalid_model_formats_type, formats}}

  defp validate_sort_criteria(criteria) do
    if criteria in @valid_sort_criteria do
      {:ok, criteria}
    else
      {:error, {:invalid_sort_criteria, criteria, @valid_sort_criteria}}
    end
  end

  defp validate_scan_paths(paths) when is_list(paths) do
    invalid_paths = Enum.filter(paths, fn path ->
      not is_binary(path) or String.length(path) == 0
    end)
    
    if Enum.empty?(invalid_paths) do
      {:ok, paths}
    else
      {:error, {:invalid_scan_paths, invalid_paths}}
    end
  end
  defp validate_scan_paths(paths), do: {:error, {:invalid_scan_paths_type, paths}}

  # Scan configuration

  defp prepare_scan_configuration(params) do
    # Determine scan paths
    scan_paths = if Enum.empty?(params.scan_paths) do
      expand_default_paths()
    else
      expand_paths(params.scan_paths)
    end
    
    # Determine formats to scan
    formats = case params.model_formats do
      :all -> @valid_model_formats
      formats -> formats
    end
    
    config = %{
      operation: params.operation,
      scan_paths: scan_paths,
      model_formats: formats,
      include_metadata: params.include_metadata,
      check_compatibility: params.check_compatibility,
      sort_by: params.sort_by,
      filter_criteria: params.filter_criteria,
      cache_results: params.cache_results,
      deep_scan: params.deep_scan,
      include_remote: params.include_remote,
      scan_start_time: DateTime.utc_now()
    }
    
    {:ok, config}
  end

  defp expand_default_paths() do
    @default_scan_paths
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.exists?/1)
  end

  defp expand_paths(paths) do
    paths
    |> Enum.map(&Path.expand/1)
    |> Enum.filter(&File.exists?/1)
  end

  # Operation execution

  defp execute_listing_operation(config, context) do
    case config.operation do
      :scan -> execute_fresh_scan(config, context)
      :cached -> execute_cached_listing(config, context)
      :detailed -> execute_detailed_listing(config, context)
      :compatible -> execute_compatibility_listing(config, context)
      :search -> execute_model_search(config, context)
    end
  end

  # Fresh scan operation

  defp execute_fresh_scan(config, context) do
    Logger.info("Executing fresh model scan across #{length(config.scan_paths)} paths")
    
    scan_results = %{
      models_found: [],
      scan_statistics: %{},
      errors: []
    }
    
    # Scan each path
    {models, errors} = Enum.reduce(config.scan_paths, {[], []}, fn path, {acc_models, acc_errors} ->
      Logger.debug("Scanning path: #{path}")
      
      case scan_path_for_models(path, config) do
        {:ok, path_models} ->
          {acc_models ++ path_models, acc_errors}
        
        {:error, error} ->
          {acc_models, [%{path: path, error: error} | acc_errors]}
      end
    end)
    
    # Process and filter models
    processed_models = models
    |> process_discovered_models(config)
    |> apply_model_filters(config.filter_criteria)
    |> sort_models(config.sort_by)
    
    # Create scan statistics
    scan_stats = create_scan_statistics(processed_models, config, errors)
    
    # Cache results if requested
    if config.cache_results do
      cache_scan_results(processed_models, config)
    end
    
    result = %{
      operation: :scan,
      models_found: processed_models,
      total_models: length(processed_models),
      scan_statistics: scan_stats,
      scan_errors: errors,
      scan_duration_ms: DateTime.diff(DateTime.utc_now(), config.scan_start_time, :millisecond),
      scan_paths: config.scan_paths,
      formats_scanned: config.model_formats
    }
    
    {:ok, result}
  end

  defp scan_path_for_models(path, config) do
    if File.dir?(path) do
      models = config.model_formats
      |> Enum.flat_map(fn format ->
        find_models_by_format(path, format, config.deep_scan)
      end)
      |> Enum.uniq_by(& &1.path)
      
      {:ok, models}
    else
      {:error, {:path_not_directory, path}}
    end
  end

  defp find_models_by_format(base_path, format, deep_scan) do
    patterns = Map.get(@model_file_patterns, format, [])
    
    Enum.flat_map(patterns, fn pattern ->
      find_files_by_pattern(base_path, pattern, format, deep_scan)
    end)
  end

  defp find_files_by_pattern(base_path, pattern, format, deep_scan) do
    search_pattern = Path.join(base_path, "**/" <> pattern)
    
    Path.wildcard(search_pattern)
    |> Enum.map(fn file_path ->
      create_model_entry(file_path, format, deep_scan)
    end)
    |> Enum.filter(& &1 != nil)
  end

  defp create_model_entry(file_path, format, deep_scan) do
    try do
      stat = File.stat!(file_path)
      
      base_entry = %{
        name: derive_model_name(file_path, format),
        path: file_path,
        format: format,
        size_bytes: stat.size,
        size_mb: round(stat.size / (1024 * 1024)),
        modified_at: stat.mtime,
        discovered_at: DateTime.utc_now(),
        status: :discovered
      }
      
      if deep_scan do
        enhanced_entry = enhance_model_entry(base_entry)
        enhanced_entry
      else
        base_entry
      end
    rescue
      _ -> nil
    end
  end

  defp derive_model_name(file_path, format) do
    case format do
      :gguf ->
        file_path
        |> Path.basename()
        |> String.replace_suffix(".gguf", "")
      
      :huggingface ->
        # For HuggingFace, use directory name
        file_path
        |> Path.dirname()
        |> Path.basename()
      
      :pytorch ->
        file_path
        |> Path.basename()
        |> String.replace(~r/\.(bin|pth|pt)$/, "")
      
      _ ->
        file_path
        |> Path.basename()
        |> Path.rootname()
    end
  end

  defp enhance_model_entry(base_entry) do
    case base_entry.format do
      :gguf -> enhance_gguf_model(base_entry)
      :huggingface -> enhance_huggingface_model(base_entry)
      :pytorch -> enhance_pytorch_model(base_entry)
      _ -> add_basic_metadata(base_entry)
    end
  end

  defp enhance_gguf_model(entry) do
    # TODO: Parse GGUF metadata using actual GGUF library
    # For now, infer from filename patterns
    
    metadata = %{
      estimated_parameters: estimate_parameters_from_name(entry.name),
      quantization: detect_quantization_from_name(entry.name),
      architecture: detect_architecture_from_name(entry.name),
      context_length: estimate_context_length(entry.name),
      capabilities: infer_capabilities_from_name(entry.name)
    }
    
    Map.put(entry, :metadata, metadata)
  end

  defp enhance_huggingface_model(entry) do
    config_path = Path.join(Path.dirname(entry.path), "config.json")
    
    metadata = if File.exists?(config_path) do
      parse_huggingface_config(config_path)
    else
      %{
        source: :huggingface,
        config_available: false
      }
    end
    
    Map.put(entry, :metadata, metadata)
  end

  defp enhance_pytorch_model(entry) do
    # TODO: Analyze PyTorch model structure
    metadata = %{
      framework: :pytorch,
      estimated_parameters: estimate_parameters_from_size(entry.size_mb),
      tensor_format: detect_tensor_format(entry.path)
    }
    
    Map.put(entry, :metadata, metadata)
  end

  defp add_basic_metadata(entry) do
    metadata = %{
      format: entry.format,
      file_type: Path.extname(entry.path),
      estimated_parameters: estimate_parameters_from_size(entry.size_mb)
    }
    
    Map.put(entry, :metadata, metadata)
  end

  defp estimate_parameters_from_name(name) do
    name_lower = String.downcase(name)
    
    cond do
      String.contains?(name_lower, ["7b", "7-b"]) -> "7B"
      String.contains?(name_lower, ["13b", "13-b"]) -> "13B"
      String.contains?(name_lower, ["30b", "30-b", "33b", "33-b"]) -> "30B+"
      String.contains?(name_lower, ["65b", "65-b", "70b", "70-b"]) -> "65B+"
      String.contains?(name_lower, ["175b", "175-b"]) -> "175B"
      true -> "Unknown"
    end
  end

  defp detect_quantization_from_name(name) do
    name_lower = String.downcase(name)
    
    cond do
      String.contains?(name_lower, ["q2_k", "q2-k"]) -> "Q2_K"
      String.contains?(name_lower, ["q3_k", "q3-k"]) -> "Q3_K"
      String.contains?(name_lower, ["q4_k", "q4-k", "q4_0", "q4_1"]) -> "Q4_K"
      String.contains?(name_lower, ["q5_k", "q5-k", "q5_0", "q5_1"]) -> "Q5_K"
      String.contains?(name_lower, ["q6_k", "q6-k"]) -> "Q6_K"
      String.contains?(name_lower, ["q8_0", "q8-0"]) -> "Q8_0"
      String.contains?(name_lower, ["f16", "fp16"]) -> "F16"
      String.contains?(name_lower, ["f32", "fp32"]) -> "F32"
      true -> "Unknown"
    end
  end

  defp detect_architecture_from_name(name) do
    name_lower = String.downcase(name)
    
    cond do
      String.contains?(name_lower, ["llama", "alpaca", "vicuna"]) -> "LLaMA"
      String.contains?(name_lower, ["mistral", "mixtral"]) -> "Mistral"
      String.contains?(name_lower, ["falcon"]) -> "Falcon"
      String.contains?(name_lower, ["gpt", "chatgpt"]) -> "GPT"
      String.contains?(name_lower, ["claude"]) -> "Claude"
      String.contains?(name_lower, ["phi"]) -> "Phi"
      String.contains?(name_lower, ["gemma"]) -> "Gemma"
      true -> "Unknown"
    end
  end

  defp estimate_context_length(name) do
    name_lower = String.downcase(name)
    
    cond do
      String.contains?(name_lower, ["32k", "32768"]) -> 32768
      String.contains?(name_lower, ["16k", "16384"]) -> 16384
      String.contains?(name_lower, ["8k", "8192"]) -> 8192
      String.contains?(name_lower, ["4k", "4096"]) -> 4096
      String.contains?(name_lower, ["2k", "2048"]) -> 2048
      true -> 2048  # Default assumption
    end
  end

  defp infer_capabilities_from_name(name) do
    name_lower = String.downcase(name)
    capabilities = [:text_generation]
    
    capabilities = if String.contains?(name_lower, ["chat", "instruct", "conversation"]) do
      [:chat, :instruction_following | capabilities]
    else
      capabilities
    end
    
    capabilities = if String.contains?(name_lower, ["code", "coding", "programming"]) do
      [:code_generation, :code_completion | capabilities]
    else
      capabilities
    end
    
    capabilities = if String.contains?(name_lower, ["function", "tool", "agent"]) do
      [:function_calling, :tool_use | capabilities]
    else
      capabilities
    end
    
    Enum.uniq(capabilities)
  end

  defp estimate_parameters_from_size(size_mb) do
    cond do
      size_mb < 2000 -> "< 3B"
      size_mb < 5000 -> "3B - 7B"
      size_mb < 10000 -> "7B - 13B"
      size_mb < 20000 -> "13B - 30B"
      size_mb < 40000 -> "30B - 65B"
      true -> "> 65B"
    end
  end

  defp parse_huggingface_config(config_path) do
    try do
      config_content = File.read!(config_path)
      config = Jason.decode!(config_content)
      
      %{
        architecture: Map.get(config, "architectures", ["Unknown"]) |> List.first(),
        model_type: Map.get(config, "model_type", "Unknown"),
        vocab_size: Map.get(config, "vocab_size"),
        hidden_size: Map.get(config, "hidden_size"),
        num_layers: Map.get(config, "num_hidden_layers"),
        num_attention_heads: Map.get(config, "num_attention_heads"),
        max_position_embeddings: Map.get(config, "max_position_embeddings"),
        torch_dtype: Map.get(config, "torch_dtype"),
        transformers_version: Map.get(config, "transformers_version"),
        use_cache: Map.get(config, "use_cache", true)
      }
    rescue
      _ ->
        %{config_parse_error: true}
    end
  end

  defp detect_tensor_format(file_path) do
    case Path.extname(file_path) do
      ".bin" -> :pytorch_binary
      ".pth" -> :pytorch_checkpoint
      ".pt" -> :pytorch_traced
      ".safetensors" -> :safetensors
      _ -> :unknown
    end
  end

  defp process_discovered_models(models, config) do
    models
    |> Enum.map(fn model ->
      processed_model = model
      
      # Add compatibility check if requested
      processed_model = if config.check_compatibility do
        add_compatibility_info(processed_model)
      else
        processed_model
      end
      
      # Add metadata if requested
      processed_model = if config.include_metadata and not Map.has_key?(processed_model, :metadata) do
        add_basic_metadata(processed_model)
      else
        processed_model
      end
      
      processed_model
    end)
  end

  defp add_compatibility_info(model) do
    compatibility = check_model_compatibility(model)
    Map.put(model, :compatibility, compatibility)
  end

  defp check_model_compatibility(model) do
    # TODO: Check actual system compatibility
    # For now, return mock compatibility info
    
    system_memory_mb = 16384  # 16GB
    system_gpu_memory_mb = 8192  # 8GB GPU
    
    can_load_cpu = model.size_mb <= system_memory_mb
    can_load_gpu = model.size_mb <= system_gpu_memory_mb
    
    estimated_ram_usage = round(model.size_mb * 1.2)  # 20% overhead
    estimated_gpu_usage = round(model.size_mb * 1.1)  # 10% overhead
    
    load_feasibility = cond do
      can_load_gpu -> :gpu_optimal
      can_load_cpu -> :cpu_feasible
      true -> :insufficient_resources
    end
    
    %{
      can_load: can_load_cpu or can_load_gpu,
      load_feasibility: load_feasibility,
      estimated_ram_usage_mb: estimated_ram_usage,
      estimated_gpu_usage_mb: estimated_gpu_usage,
      recommended_device: if(can_load_gpu, do: :gpu, else: :cpu),
      compatibility_score: calculate_compatibility_score(model, can_load_cpu, can_load_gpu),
      system_requirements: %{
        min_ram_mb: round(model.size_mb * 1.2),
        min_gpu_memory_mb: if(model.format == :gguf, do: round(model.size_mb * 0.8), else: model.size_mb),
        cpu_cores_recommended: if(model.size_mb > 10000, do: 8, else: 4)
      }
    }
  end

  defp calculate_compatibility_score(model, can_load_cpu, can_load_gpu) do
    base_score = 0
    
    # Loading capability
    base_score = base_score + if(can_load_gpu, do: 40, else: 0)
    base_score = base_score + if(can_load_cpu, do: 20, else: 0)
    
    # Format compatibility
    format_score = case model.format do
      :gguf -> 30  # Excellent compatibility
      :huggingface -> 25  # Good compatibility
      :pytorch -> 20  # Fair compatibility
      :safetensors -> 25  # Good compatibility
      _ -> 10  # Basic compatibility
    end
    
    base_score = base_score + format_score
    
    # Size efficiency
    size_score = cond do
      model.size_mb < 4000 -> 10   # Small, efficient
      model.size_mb < 8000 -> 8    # Medium
      model.size_mb < 16000 -> 5   # Large
      true -> 2                    # Very large
    end
    
    min(base_score + size_score, 100)
  end

  # Model filtering and sorting

  defp apply_model_filters(models, filter_criteria) do
    Enum.filter(models, fn model ->
      passes_all_filters?(model, filter_criteria)
    end)
  end

  defp passes_all_filters?(model, criteria) when map_size(criteria) == 0, do: true
  defp passes_all_filters?(model, criteria) do
    Enum.all?(criteria, fn {filter_key, filter_value} ->
      passes_filter?(model, filter_key, filter_value)
    end)
  end

  defp passes_filter?(model, :min_size_mb, min_size) do
    model.size_mb >= min_size
  end

  defp passes_filter?(model, :max_size_mb, max_size) do
    model.size_mb <= max_size
  end

  defp passes_filter?(model, :formats, allowed_formats) when is_list(allowed_formats) do
    model.format in allowed_formats
  end

  defp passes_filter?(model, :task_types, required_tasks) when is_list(required_tasks) do
    model_capabilities = Map.get(model.metadata || %{}, :capabilities, [])
    Enum.any?(required_tasks, &(&1 in model_capabilities))
  end

  defp passes_filter?(model, :architecture, required_arch) do
    model_arch = Map.get(model.metadata || %{}, :architecture, "Unknown")
    String.contains?(String.downcase(model_arch), String.downcase(to_string(required_arch)))
  end

  defp passes_filter?(model, :can_load, true) do
    compatibility = Map.get(model, :compatibility, %{})
    Map.get(compatibility, :can_load, false)
  end

  defp passes_filter?(model, :compatibility_score, min_score) do
    compatibility = Map.get(model, :compatibility, %{})
    score = Map.get(compatibility, :compatibility_score, 0)
    score >= min_score
  end

  defp passes_filter?(_model, _key, _value), do: true

  defp sort_models(models, sort_by) do
    case sort_by do
      :name -> Enum.sort_by(models, & &1.name)
      :size -> Enum.sort_by(models, & &1.size_mb, :desc)
      :date -> Enum.sort_by(models, & &1.modified_at, :desc)
      :format -> Enum.sort_by(models, & &1.format)
      :compatibility -> 
        Enum.sort_by(models, fn model ->
          compatibility = Map.get(model, :compatibility, %{})
          Map.get(compatibility, :compatibility_score, 0)
        end, :desc)
      _ -> models
    end
  end

  # Statistics and caching

  defp create_scan_statistics(models, config, errors) do
    format_distribution = Enum.frequencies_by(models, & &1.format)
    size_distribution = categorize_models_by_size(models)
    
    %{
      total_models_found: length(models),
      paths_scanned: length(config.scan_paths),
      formats_found: Map.keys(format_distribution),
      format_distribution: format_distribution,
      size_distribution: size_distribution,
      total_size_gb: calculate_total_size_gb(models),
      scan_errors: length(errors),
      compatibility_summary: create_compatibility_summary(models),
      largest_model: find_largest_model(models),
      smallest_model: find_smallest_model(models)
    }
  end

  defp categorize_models_by_size(models) do
    categories = %{
      tiny: 0,      # < 1GB
      small: 0,     # 1GB - 4GB
      medium: 0,    # 4GB - 8GB
      large: 0,     # 8GB - 20GB
      very_large: 0 # > 20GB
    }
    
    Enum.reduce(models, categories, fn model, acc ->
      category = cond do
        model.size_mb < 1024 -> :tiny
        model.size_mb < 4096 -> :small
        model.size_mb < 8192 -> :medium
        model.size_mb < 20480 -> :large
        true -> :very_large
      end
      
      Map.update!(acc, category, &(&1 + 1))
    end)
  end

  defp calculate_total_size_gb(models) do
    total_mb = Enum.reduce(models, 0, &(&1.size_mb + &2))
    Float.round(total_mb / 1024, 2)
  end

  defp create_compatibility_summary(models) do
    models_with_compatibility = Enum.filter(models, &Map.has_key?(&1, :compatibility))
    
    if length(models_with_compatibility) == 0 do
      %{compatibility_checked: false}
    else
      loadable_models = Enum.count(models_with_compatibility, fn model ->
        model.compatibility.can_load
      end)
      
      gpu_optimal = Enum.count(models_with_compatibility, fn model ->
        model.compatibility.load_feasibility == :gpu_optimal
      end)
      
      %{
        compatibility_checked: true,
        total_checked: length(models_with_compatibility),
        loadable_models: loadable_models,
        gpu_optimal_models: gpu_optimal,
        cpu_only_models: loadable_models - gpu_optimal,
        compatibility_rate: loadable_models / length(models_with_compatibility)
      }
    end
  end

  defp find_largest_model(models) do
    case Enum.max_by(models, & &1.size_mb, fn -> nil end) do
      nil -> nil
      model -> %{name: model.name, size_mb: model.size_mb, format: model.format}
    end
  end

  defp find_smallest_model(models) do
    case Enum.min_by(models, & &1.size_mb, fn -> nil end) do
      nil -> nil
      model -> %{name: model.name, size_mb: model.size_mb, format: model.format}
    end
  end

  defp cache_scan_results(models, config) do
    # TODO: Implement actual caching to file system or database
    Logger.debug("Caching scan results for #{length(models)} models")
    :ok
  end

  # Cached listing operation

  defp execute_cached_listing(config, context) do
    Logger.info("Retrieving cached model listing")
    
    # TODO: Implement actual cache retrieval
    # For now, return empty cache
    
    result = %{
      operation: :cached,
      models_found: [],
      total_models: 0,
      cache_status: :empty,
      cache_age_hours: 0,
      recommendation: "Run a fresh scan to discover models"
    }
    
    {:ok, result}
  end

  # Detailed listing operation

  defp execute_detailed_listing(config, context) do
    Logger.info("Executing detailed model listing")
    
    # Force deep scan and metadata inclusion
    detailed_config = %{config | 
      deep_scan: true,
      include_metadata: true,
      check_compatibility: true
    }
    
    case execute_fresh_scan(detailed_config, context) do
      {:ok, scan_result} ->
        # Enhance with additional details
        enhanced_models = Enum.map(scan_result.models_found, fn model ->
          add_detailed_analysis(model)
        end)
        
        detailed_result = %{scan_result |
          operation: :detailed,
          models_found: enhanced_models,
          detailed_analysis: create_detailed_analysis(enhanced_models)
        }
        
        {:ok, detailed_result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp add_detailed_analysis(model) do
    detailed_info = %{
      file_analysis: analyze_model_file(model),
      performance_estimates: estimate_model_performance(model),
      usage_recommendations: generate_usage_recommendations(model),
      loading_requirements: calculate_loading_requirements(model)
    }
    
    Map.put(model, :detailed_info, detailed_info)
  end

  defp analyze_model_file(model) do
    %{
      file_integrity: :not_checked,  # TODO: Implement checksum verification
      access_permissions: check_file_permissions(model.path),
      storage_type: detect_storage_type(model.path),
      compression_detected: detect_compression(model.path)
    }
  end

  defp check_file_permissions(file_path) do
    try do
      stat = File.stat!(file_path)
      %{
        readable: stat.access == :read or stat.access == :read_write,
        writable: stat.access == :write or stat.access == :read_write,
        owner: :unknown  # TODO: Get actual file owner
      }
    rescue
      _ -> %{error: "Cannot check permissions"}
    end
  end

  defp detect_storage_type(file_path) do
    # Simple heuristic based on path
    cond do
      String.contains?(file_path, ["/tmp", "/cache"]) -> :temporary
      String.contains?(file_path, "/home") -> :user_storage
      String.contains?(file_path, ["/opt", "/usr"]) -> :system_storage
      String.starts_with?(file_path, "/") -> :local_storage
      true -> :unknown
    end
  end

  defp detect_compression(file_path) do
    # Check if file appears to be compressed based on extension or magic bytes
    compressed_extensions = [".gz", ".bz2", ".xz", ".zip", ".tar"]
    
    Enum.any?(compressed_extensions, &String.ends_with?(file_path, &1))
  end

  defp estimate_model_performance(model) do
    # Rough performance estimates based on model characteristics
    base_inference_ms = case model.size_mb do
      size when size < 2000 -> 50   # Small models
      size when size < 5000 -> 150  # Medium models
      size when size < 10000 -> 300 # Large models
      _ -> 600                      # Very large models
    end
    
    # Adjust for format efficiency
    format_multiplier = case model.format do
      :gguf -> 0.8        # GGUF is efficient
      :safetensors -> 0.9
      :pytorch -> 1.2
      :onnx -> 0.85
      _ -> 1.0
    end
    
    estimated_inference_ms = round(base_inference_ms * format_multiplier)
    
    %{
      estimated_inference_latency_ms: estimated_inference_ms,
      estimated_tokens_per_second: round(1000 / estimated_inference_ms * 10),
      memory_efficiency_score: calculate_memory_efficiency_score(model),
      recommended_batch_size: calculate_recommended_batch_size(model)
    }
  end

  defp calculate_memory_efficiency_score(model) do
    # Higher scores for smaller, more efficient models
    base_score = 100 - min(model.size_mb / 1000, 80)
    
    format_bonus = case model.format do
      :gguf -> 15
      :safetensors -> 10
      :onnx -> 8
      _ -> 0
    end
    
    round(base_score + format_bonus)
  end

  defp calculate_recommended_batch_size(model) do
    case model.size_mb do
      size when size < 2000 -> 8
      size when size < 5000 -> 4
      size when size < 10000 -> 2
      _ -> 1
    end
  end

  defp generate_usage_recommendations(model) do
    recommendations = []
    
    # Size-based recommendations
    recommendations = case model.size_mb do
      size when size > 20000 ->
        ["Very large model - consider using GPU with sufficient VRAM" | recommendations]
      size when size > 10000 ->
        ["Large model - GPU acceleration recommended" | recommendations]
      size when size < 2000 ->
        ["Small model - suitable for CPU inference" | recommendations]
      _ ->
        recommendations
    end
    
    # Format-specific recommendations
    recommendations = case model.format do
      :gguf ->
        ["GGUF format - excellent for CPU inference with llama.cpp" | recommendations]
      :huggingface ->
        ["HuggingFace format - use with transformers library" | recommendations]
      :pytorch ->
        ["PyTorch format - requires PyTorch runtime" | recommendations]
      _ ->
        recommendations
    end
    
    # Capability-based recommendations
    if Map.has_key?(model, :metadata) and Map.has_key?(model.metadata, :capabilities) do
      capabilities = model.metadata.capabilities
      
      recommendations = if :chat in capabilities do
        ["Optimized for chat/conversation use cases" | recommendations]
      else
        recommendations
      end
      
      recommendations = if :code_generation in capabilities do
        ["Suitable for code generation tasks" | recommendations]
      else
        recommendations
      end
    end
    
    Enum.reverse(recommendations)
  end

  defp calculate_loading_requirements(model) do
    base_memory = model.size_mb
    
    %{
      minimum_ram_mb: round(base_memory * 1.1),
      recommended_ram_mb: round(base_memory * 1.5),
      minimum_gpu_memory_mb: round(base_memory * 0.9),
      recommended_gpu_memory_mb: round(base_memory * 1.2),
      estimated_load_time_seconds: estimate_load_time(model),
      disk_io_requirements: %{
        sequential_read_speed_mb_s: 100,
        recommended_storage_type: "SSD"
      }
    }
  end

  defp estimate_load_time(model) do
    # Rough estimate: 100MB/second loading speed
    base_time = model.size_mb / 100
    
    # Adjust for format
    format_factor = case model.format do
      :gguf -> 1.0
      :pytorch -> 1.3
      :huggingface -> 1.5
      _ -> 1.2
    end
    
    round(base_time * format_factor)
  end

  defp create_detailed_analysis(models) do
    %{
      performance_distribution: analyze_performance_distribution(models),
      format_analysis: analyze_format_characteristics(models),
      size_efficiency_analysis: analyze_size_efficiency(models),
      loading_time_analysis: analyze_loading_times(models),
      recommendations: generate_collection_recommendations(models)
    }
  end

  defp analyze_performance_distribution(models) do
    performance_scores = Enum.map(models, fn model ->
      Map.get(model.detailed_info.performance_estimates, :memory_efficiency_score, 50)
    end)
    
    %{
      average_performance_score: if(length(performance_scores) > 0, do: Enum.sum(performance_scores) / length(performance_scores), else: 0),
      performance_range: {Enum.min(performance_scores, fn -> 0 end), Enum.max(performance_scores, fn -> 0 end)},
      high_performance_models: Enum.count(performance_scores, &(&1 > 75))
    }
  end

  defp analyze_format_characteristics(models) do
    by_format = Enum.group_by(models, & &1.format)
    
    Enum.map(by_format, fn {format, format_models} ->
      avg_size = Enum.sum(Enum.map(format_models, & &1.size_mb)) / length(format_models)
      
      {format, %{
        count: length(format_models),
        average_size_mb: round(avg_size),
        size_range: {
          Enum.min_by(format_models, & &1.size_mb).size_mb,
          Enum.max_by(format_models, & &1.size_mb).size_mb
        }
      }}
    end)
    |> Enum.into(%{})
  end

  defp analyze_size_efficiency(models) do
    models_with_estimates = Enum.filter(models, &Map.has_key?(&1, :metadata))
    
    if length(models_with_estimates) == 0 do
      %{analysis_available: false}
    else
      efficiency_scores = Enum.map(models_with_estimates, fn model ->
        Map.get(model.detailed_info.performance_estimates, :memory_efficiency_score, 50)
      end)
      
      %{
        average_efficiency: Enum.sum(efficiency_scores) / length(efficiency_scores),
        most_efficient: find_most_efficient_model(models_with_estimates),
        least_efficient: find_least_efficient_model(models_with_estimates)
      }
    end
  end

  defp find_most_efficient_model(models) do
    case Enum.max_by(models, fn model ->
      Map.get(model.detailed_info.performance_estimates, :memory_efficiency_score, 0)
    end, fn -> nil end) do
      nil -> nil
      model -> %{name: model.name, score: model.detailed_info.performance_estimates.memory_efficiency_score}
    end
  end

  defp find_least_efficient_model(models) do
    case Enum.min_by(models, fn model ->
      Map.get(model.detailed_info.performance_estimates, :memory_efficiency_score, 100)
    end, fn -> nil end) do
      nil -> nil
      model -> %{name: model.name, score: model.detailed_info.performance_estimates.memory_efficiency_score}
    end
  end

  defp analyze_loading_times(models) do
    load_times = Enum.map(models, fn model ->
      Map.get(model.detailed_info.loading_requirements, :estimated_load_time_seconds, 10)
    end)
    
    %{
      average_load_time_seconds: if(length(load_times) > 0, do: Enum.sum(load_times) / length(load_times), else: 0),
      fastest_loading: Enum.min(load_times, fn -> 0 end),
      slowest_loading: Enum.max(load_times, fn -> 0 end),
      quick_loading_models: Enum.count(load_times, &(&1 < 10))
    }
  end

  defp generate_collection_recommendations(models) do
    recommendations = []
    
    total_size_gb = calculate_total_size_gb(models)
    
    recommendations = if total_size_gb > 100 do
      ["Large model collection (#{total_size_gb}GB) - consider storage optimization" | recommendations]
    else
      recommendations
    end
    
    format_count = models |> Enum.map(& &1.format) |> Enum.uniq() |> length()
    
    recommendations = if format_count > 3 do
      ["Multiple model formats detected - consider standardizing for easier management" | recommendations]
    else
      recommendations
    end
    
    loadable_count = Enum.count(models, fn model ->
      case Map.get(model, :compatibility) do
        %{can_load: true} -> true
        _ -> false
      end
    end)
    
    loadable_ratio = if length(models) > 0, do: loadable_count / length(models), else: 0
    
    recommendations = if loadable_ratio < 0.5 do
      ["Many models may not be loadable with current system resources" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  # Compatibility listing

  defp execute_compatibility_listing(config, context) do
    Logger.info("Executing compatibility-focused model listing")
    
    # First get all models
    case execute_fresh_scan(config, context) do
      {:ok, scan_result} ->
        # Filter for compatible models only
        compatible_models = Enum.filter(scan_result.models_found, fn model ->
          case Map.get(model, :compatibility) do
            %{can_load: true} -> true
            _ -> false
          end
        end)
        
        # Group by compatibility level
        compatibility_groups = group_by_compatibility(compatible_models)
        
        result = %{
          operation: :compatible,
          compatible_models: compatible_models,
          total_compatible: length(compatible_models),
          compatibility_groups: compatibility_groups,
          compatibility_summary: create_detailed_compatibility_summary(compatible_models),
          loading_recommendations: generate_loading_recommendations(compatible_models)
        }
        
        {:ok, result}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp group_by_compatibility(models) do
    Enum.group_by(models, fn model ->
      model.compatibility.load_feasibility
    end)
  end

  defp create_detailed_compatibility_summary(models) do
    %{
      gpu_optimal: Enum.count(models, &(&1.compatibility.load_feasibility == :gpu_optimal)),
      cpu_feasible: Enum.count(models, &(&1.compatibility.load_feasibility == :cpu_feasible)),
      average_compatibility_score: calculate_average_compatibility_score(models),
      recommended_models: find_recommended_models(models)
    }
  end

  defp calculate_average_compatibility_score(models) do
    if length(models) == 0 do
      0
    else
      scores = Enum.map(models, & &1.compatibility.compatibility_score)
      Enum.sum(scores) / length(scores)
    end
  end

  defp find_recommended_models(models) do
    models
    |> Enum.filter(&(&1.compatibility.compatibility_score > 70))
    |> Enum.take(5)
    |> Enum.map(fn model ->
      %{
        name: model.name,
        format: model.format,
        size_mb: model.size_mb,
        compatibility_score: model.compatibility.compatibility_score,
        recommended_device: model.compatibility.recommended_device
      }
    end)
  end

  defp generate_loading_recommendations(models) do
    recommendations = []
    
    gpu_optimal = Enum.filter(models, &(&1.compatibility.load_feasibility == :gpu_optimal))
    cpu_only = Enum.filter(models, &(&1.compatibility.load_feasibility == :cpu_feasible))
    
    recommendations = if length(gpu_optimal) > 0 do
      ["#{length(gpu_optimal)} models can be optimally loaded on GPU" | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(cpu_only) > 0 do
      ["#{length(cpu_only)} models require CPU-only loading" | recommendations]
    else
      recommendations
    end
    
    # Find the best models for different use cases
    best_small = Enum.filter(models, &(&1.size_mb < 4000)) |> List.first()
    best_large = Enum.filter(models, &(&1.size_mb > 8000)) |> List.first()
    
    recommendations = if best_small do
      ["Best small model: #{best_small.name} (#{best_small.size_mb}MB)" | recommendations]
    else
      recommendations
    end
    
    recommendations = if best_large do
      ["Best large model: #{best_large.name} (#{best_large.size_mb}MB)" | recommendations]
    else
      recommendations
    end
    
    Enum.reverse(recommendations)
  end

  # Model search

  defp execute_model_search(config, context) do
    # TODO: Implement search functionality
    # This would search models by name, capabilities, etc.
    
    result = %{
      operation: :search,
      search_query: Map.get(config.filter_criteria, :search_query, ""),
      results_found: [],
      total_results: 0,
      search_suggestions: [
        "Try searching by model name (e.g., 'llama')",
        "Search by capability (e.g., 'chat', 'code')",
        "Filter by size (e.g., 'small', 'large')"
      ]
    }
    
    {:ok, result}
  end

  # Signal emission

  defp emit_models_listed_signal(operation, result) do
    # TODO: Emit actual signal
    Logger.debug("Models #{operation} completed: #{Map.get(result, :total_models, 0)} models found")
  end

  defp emit_models_listing_error_signal(operation, reason) do
    # TODO: Emit actual signal
    Logger.debug("Models #{operation} failed: #{inspect(reason)}")
  end
end