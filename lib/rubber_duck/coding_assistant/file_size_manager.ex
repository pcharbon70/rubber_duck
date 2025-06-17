defmodule RubberDuck.CodingAssistant.FileSizeManager do
  @moduledoc """
  File size management and validation for code analysis operations.
  
  This module provides centralized file size validation, quota management,
  and configuration for handling files of various sizes in the coding
  assistant system.
  """

  use GenServer
  require Logger

  # Default size limits (in bytes)
  @default_max_file_size 10 * 1024 * 1024      # 10MB
  @default_max_total_size 100 * 1024 * 1024    # 100MB total
  @default_max_files_per_batch 50
  @default_streaming_threshold 1 * 1024 * 1024  # 1MB

  # Size categories for different handling strategies
  @size_categories %{
    tiny: 0..1024,                              # 0-1KB
    small: 1025..(64 * 1024),                   # 1KB-64KB
    medium: (64 * 1024 + 1)..(1024 * 1024),     # 64KB-1MB
    large: (1024 * 1024 + 1)..(10 * 1024 * 1024), # 1MB-10MB
    xlarge: (10 * 1024 * 1024 + 1)..(50 * 1024 * 1024), # 10MB-50MB
    huge: (50 * 1024 * 1024 + 1)..1_000_000_000 # 50MB+
  }

  defstruct [
    :config,
    :current_usage,
    :file_quotas,
    :statistics
  ]

  ## Public API

  @doc """
  Start the file size manager.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Validate a single file size.
  """
  def validate_file_size(file_path_or_size, context \\ %{}) do
    GenServer.call(__MODULE__, {:validate_file_size, file_path_or_size, context})
  end

  @doc """
  Validate multiple files in a batch.
  """
  def validate_file_batch(files, context \\ %{}) do
    GenServer.call(__MODULE__, {:validate_file_batch, files, context})
  end

  @doc """
  Get the recommended processing strategy for a file.
  """
  def get_processing_strategy(file_size, file_type \\ :unknown) do
    GenServer.call(__MODULE__, {:get_processing_strategy, file_size, file_type})
  end

  @doc """
  Check current usage against quotas.
  """
  def check_quota_usage do
    GenServer.call(__MODULE__, :check_quota_usage)
  end

  @doc """
  Update configuration.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  @doc """
  Get file size statistics.
  """
  def get_statistics do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @doc """
  Reserve quota for upcoming operation.
  """
  def reserve_quota(size, operation_type \\ :analysis) do
    GenServer.call(__MODULE__, {:reserve_quota, size, operation_type})
  end

  @doc """
  Release reserved quota.
  """
  def release_quota(size, operation_type \\ :analysis) do
    GenServer.cast(__MODULE__, {:release_quota, size, operation_type})
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    config = build_config(opts)
    
    state = %__MODULE__{
      config: config,
      current_usage: initialize_usage_tracking(),
      file_quotas: initialize_quota_tracking(),
      statistics: initialize_statistics()
    }
    
    Logger.info("FileSizeManager started with max file size: #{format_bytes(config.max_file_size)}")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:validate_file_size, file_path_or_size, context}, _from, state) do
    result = validate_single_file(file_path_or_size, context, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:validate_file_batch, files, context}, _from, state) do
    result = validate_file_batch_internal(files, context, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_processing_strategy, file_size, file_type}, _from, state) do
    strategy = determine_processing_strategy(file_size, file_type, state.config)
    {:reply, strategy, state}
  end

  @impl GenServer
  def handle_call(:check_quota_usage, _from, state) do
    usage = calculate_quota_usage(state)
    {:reply, usage, state}
  end

  @impl GenServer
  def handle_call({:update_config, new_config}, _from, state) do
    updated_config = Map.merge(state.config, new_config)
    new_state = %{state | config: updated_config}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_statistics, _from, state) do
    {:reply, state.statistics, state}
  end

  @impl GenServer
  def handle_call({:reserve_quota, size, operation_type}, _from, state) do
    case try_reserve_quota(size, operation_type, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_cast({:release_quota, size, operation_type}, state) do
    new_state = release_quota_internal(size, operation_type, state)
    {:noreply, new_state}
  end

  ## Validation Functions

  defp validate_single_file(file_path_or_size, context, state) do
    file_size = case file_path_or_size do
      size when is_integer(size) -> size
      file_path when is_binary(file_path) -> get_file_size(file_path)
    end
    
    case file_size do
      {:error, reason} ->
        {:error, {:file_access_error, reason}}
      
      size when is_integer(size) ->
        run_size_validations(size, context, state)
    end
  end

  defp run_size_validations(file_size, context, state) do
    validations = [
      &validate_max_file_size/3,
      &validate_file_category/3,
      &validate_quota_limits/3,
      &validate_memory_constraints/3
    ]
    
    Enum.reduce_while(validations, :ok, fn validator, _acc ->
      case validator.(file_size, context, state) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_max_file_size(file_size, _context, state) do
    max_size = state.config.max_file_size
    
    if file_size <= max_size do
      :ok
    else
      {:error, {:file_too_large, file_size, max_size}}
    end
  end

  defp validate_file_category(file_size, context, _state) do
    category = categorize_file_size(file_size)
    processing_mode = Map.get(context, :processing_mode, :standard)
    
    case {category, processing_mode} do
      {:huge, :standard} ->
        {:error, {:requires_streaming, file_size, category}}
      
      {:xlarge, :batch} ->
        {:error, {:too_large_for_batch, file_size, category}}
      
      _ ->
        :ok
    end
  end

  defp validate_quota_limits(file_size, context, state) do
    operation_type = Map.get(context, :operation_type, :analysis)
    current_usage = get_current_usage(operation_type, state)
    max_usage = get_max_usage(operation_type, state.config)
    
    if current_usage + file_size <= max_usage do
      :ok
    else
      {:error, {:quota_exceeded, current_usage + file_size, max_usage}}
    end
  end

  defp validate_memory_constraints(file_size, context, state) do
    processing_strategy = Map.get(context, :strategy, :auto)
    available_memory = get_available_memory()
    memory_requirement = estimate_memory_requirement(file_size, processing_strategy)
    
    if memory_requirement <= available_memory do
      :ok
    else
      {:error, {:insufficient_memory, memory_requirement, available_memory}}
    end
  end

  defp validate_file_batch_internal(files, context, state) do
    # Validate batch constraints first
    case validate_batch_constraints(files, context, state) do
      :ok ->
        # Then validate each file
        file_validations = Enum.map(files, fn file ->
          {file, validate_single_file(file, context, state)}
        end)
        
        # Check if any files failed validation
        failed_files = Enum.filter(file_validations, fn {_file, result} ->
          match?({:error, _}, result)
        end)
        
        if Enum.empty?(failed_files) do
          {:ok, %{
            total_files: length(files),
            total_size: calculate_total_size(files),
            processing_strategy: determine_batch_strategy(files, state.config)
          }}
        else
          {:error, {:batch_validation_failed, failed_files}}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_batch_constraints(files, _context, state) do
    file_count = length(files)
    max_files = state.config.max_files_per_batch
    
    cond do
      file_count > max_files ->
        {:error, {:too_many_files, file_count, max_files}}
      
      file_count == 0 ->
        {:error, :empty_batch}
      
      true ->
        total_size = calculate_total_size(files)
        max_total = state.config.max_total_size
        
        if total_size <= max_total do
          :ok
        else
          {:error, {:batch_too_large, total_size, max_total}}
        end
    end
  end

  ## Processing Strategy Functions

  defp determine_processing_strategy(file_size, file_type, config) do
    category = categorize_file_size(file_size)
    streaming_threshold = config.streaming_threshold
    
    base_strategy = case category do
      :tiny -> %{type: :direct, memory_efficient: false, chunked: false}
      :small -> %{type: :direct, memory_efficient: false, chunked: false}
      :medium -> %{type: :buffered, memory_efficient: true, chunked: false}
      :large -> %{type: :streaming, memory_efficient: true, chunked: true}
      :xlarge -> %{type: :streaming, memory_efficient: true, chunked: true, progressive: true}
      :huge -> %{type: :memory_mapped, memory_efficient: true, chunked: true, progressive: true}
    end
    
    # Adjust strategy based on file type
    adjusted_strategy = adjust_strategy_for_file_type(base_strategy, file_type)
    
    # Add size-specific recommendations
    Map.merge(adjusted_strategy, %{
      file_size: file_size,
      size_category: category,
      recommended_chunk_size: calculate_recommended_chunk_size(file_size),
      estimated_memory: estimate_memory_requirement(file_size, adjusted_strategy.type),
      estimated_time: estimate_processing_time(file_size, adjusted_strategy.type)
    })
  end

  defp adjust_strategy_for_file_type(strategy, file_type) do
    case file_type do
      :binary ->
        # Binary files might need special handling
        Map.put(strategy, :binary_safe, true)
      
      :text ->
        # Text files can use standard streaming
        strategy
      
      :code ->
        # Code files might benefit from AST-aware chunking
        Map.put(strategy, :syntax_aware, true)
      
      _ ->
        strategy
    end
  end

  defp determine_batch_strategy(files, config) do
    file_sizes = Enum.map(files, &get_file_size/1)
    total_size = Enum.sum(file_sizes)
    max_file_size = Enum.max(file_sizes)
    
    cond do
      max_file_size > config.streaming_threshold ->
        :mixed_streaming
      
      total_size > config.max_total_size / 2 ->
        :batch_streaming
      
      length(files) > 20 ->
        :parallel_processing
      
      true ->
        :standard_batch
    end
  end

  ## Size Categorization

  defp categorize_file_size(size) do
    Enum.find_value(@size_categories, fn {category, range} ->
      if size in range, do: category
    end) || :huge
  end

  ## Quota Management

  defp try_reserve_quota(size, operation_type, state) do
    current_usage = get_current_usage(operation_type, state)
    max_usage = get_max_usage(operation_type, state.config)
    
    if current_usage + size <= max_usage do
      new_usage = update_usage(state.current_usage, operation_type, size)
      new_state = %{state | current_usage: new_usage}
      {:ok, new_state}
    else
      {:error, {:quota_exceeded, current_usage + size, max_usage}}
    end
  end

  defp release_quota_internal(size, operation_type, state) do
    new_usage = reduce_usage(state.current_usage, operation_type, size)
    %{state | current_usage: new_usage}
  end

  defp get_current_usage(operation_type, state) do
    Map.get(state.current_usage, operation_type, 0)
  end

  defp get_max_usage(operation_type, config) do
    case operation_type do
      :analysis -> config.max_total_size
      :batch -> config.max_total_size * 2  # Allow more for batch operations
      _ -> config.max_total_size
    end
  end

  defp update_usage(current_usage, operation_type, size) do
    Map.update(current_usage, operation_type, size, &(&1 + size))
  end

  defp reduce_usage(current_usage, operation_type, size) do
    Map.update(current_usage, operation_type, 0, &max(0, &1 - size))
  end

  ## Utility Functions

  defp get_file_size(file_path) when is_binary(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{size: size}} -> size
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_file_size(size) when is_integer(size), do: size

  defp calculate_total_size(files) do
    files
    |> Enum.map(&get_file_size/1)
    |> Enum.filter(&is_integer/1)
    |> Enum.sum()
  end

  defp calculate_recommended_chunk_size(file_size) do
    cond do
      file_size < 1024 * 1024 -> 8192          # 8KB for small files
      file_size < 10 * 1024 * 1024 -> 65536    # 64KB for medium files
      file_size < 100 * 1024 * 1024 -> 262144  # 256KB for large files
      true -> 1048576                          # 1MB for huge files
    end
  end

  defp estimate_memory_requirement(file_size, processing_type) do
    base_memory = case processing_type do
      :direct -> file_size * 2        # Need to load entire file + processing overhead
      :buffered -> file_size * 1.5    # Buffered processing
      :streaming -> 1024 * 1024       # Constant memory usage
      :memory_mapped -> 1024 * 512    # Minimal memory footprint
      _ -> file_size
    end
    
    # Add base overhead
    base_memory + (10 * 1024 * 1024)  # 10MB base overhead
  end

  defp estimate_processing_time(file_size, processing_type) do
    # Very rough estimates in milliseconds
    base_time_per_byte = case processing_type do
      :direct -> 0.001
      :buffered -> 0.002
      :streaming -> 0.005
      :memory_mapped -> 0.003
      _ -> 0.001
    end
    
    round(file_size * base_time_per_byte)
  end

  defp get_available_memory do
    # Get available system memory - simplified implementation
    # In production, this would check actual system resources
    100 * 1024 * 1024  # 100MB available
  end

  defp calculate_quota_usage(state) do
    total_usage = state.current_usage
    |> Map.values()
    |> Enum.sum()
    
    %{
      current_usage: total_usage,
      max_usage: state.config.max_total_size,
      usage_percentage: if(state.config.max_total_size > 0, do: total_usage / state.config.max_total_size * 100, else: 0),
      by_operation: state.current_usage
    }
  end

  ## Configuration Functions

  defp build_config(opts) do
    %{
      max_file_size: Keyword.get(opts, :max_file_size, @default_max_file_size),
      max_total_size: Keyword.get(opts, :max_total_size, @default_max_total_size),
      max_files_per_batch: Keyword.get(opts, :max_files_per_batch, @default_max_files_per_batch),
      streaming_threshold: Keyword.get(opts, :streaming_threshold, @default_streaming_threshold),
      memory_limit: Keyword.get(opts, :memory_limit, 200 * 1024 * 1024), # 200MB
      enable_quotas: Keyword.get(opts, :enable_quotas, true)
    }
  end

  defp initialize_usage_tracking do
    %{
      analysis: 0,
      batch: 0,
      streaming: 0
    }
  end

  defp initialize_quota_tracking do
    %{
      hourly_usage: 0,
      daily_usage: 0,
      reset_time: System.system_time(:second)
    }
  end

  defp initialize_statistics do
    %{
      files_processed: 0,
      total_bytes_processed: 0,
      average_file_size: 0,
      size_distribution: %{
        tiny: 0, small: 0, medium: 0, 
        large: 0, xlarge: 0, huge: 0
      },
      rejections: %{
        too_large: 0,
        quota_exceeded: 0,
        memory_limit: 0
      }
    }
  end

  defp format_bytes(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} bytes"
    end
  end
end