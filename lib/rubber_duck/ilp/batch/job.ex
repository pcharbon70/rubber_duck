defmodule RubberDuck.ILP.Batch.Job do
  @moduledoc """
  Batch job structure for large-scale operations.
  Includes checkpointing, progress tracking, and resource management.
  """
  
  defstruct [
    :id,
    :type,
    :spec,
    :priority,
    :status,
    :progress,
    :created_at,
    :started_at,
    :completed_at,
    :checkpoints,
    :resource_requirements,
    :task_ref,
    :process_pid,
    :context,
    :error_info
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    type: atom(),
    spec: map(),
    priority: integer(),
    status: :queued | :running | :completed | :failed | :cancelled,
    progress: float(),
    created_at: integer(),
    started_at: integer() | nil,
    completed_at: integer() | nil,
    checkpoints: list(),
    resource_requirements: map(),
    task_ref: reference() | nil,
    process_pid: pid() | nil,
    context: map() | nil,
    error_info: any() | nil
  }

  @doc """
  Creates a new batch job.
  """
  def new(type, spec, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      type: type,
      spec: spec,
      priority: Keyword.get(opts, :priority, 5),
      status: :queued,
      progress: 0.0,
      created_at: System.monotonic_time(:millisecond),
      checkpoints: [],
      resource_requirements: calculate_requirements(type, spec),
      context: %{}
    }
  end

  @doc """
  Updates job progress.
  """
  def update_progress(%__MODULE__{} = job, progress) when progress >= 0.0 and progress <= 1.0 do
    %{job | progress: progress}
  end

  @doc """
  Adds a checkpoint to the job.
  """
  def add_checkpoint(%__MODULE__{} = job, checkpoint_data) do
    checkpoint = %{
      timestamp: System.monotonic_time(:millisecond),
      progress: job.progress,
      data: checkpoint_data
    }
    
    %{job | checkpoints: [checkpoint | job.checkpoints]}
  end

  @doc """
  Marks job as started.
  """
  def mark_started(%__MODULE__{} = job, task_ref, process_pid) do
    %{job | 
      status: :running,
      started_at: System.monotonic_time(:millisecond),
      task_ref: task_ref,
      process_pid: process_pid
    }
  end

  @doc """
  Marks job as completed.
  """
  def mark_completed(%__MODULE__{} = job) do
    %{job | 
      status: :completed,
      completed_at: System.monotonic_time(:millisecond),
      progress: 1.0
    }
  end

  @doc """
  Marks job as failed.
  """
  def mark_failed(%__MODULE__{} = job, error_info) do
    %{job | 
      status: :failed,
      completed_at: System.monotonic_time(:millisecond),
      error_info: error_info
    }
  end

  @doc """
  Marks job as cancelled.
  """
  def mark_cancelled(%__MODULE__{} = job) do
    %{job | 
      status: :cancelled,
      completed_at: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Gets the most recent checkpoint.
  """
  def latest_checkpoint(%__MODULE__{checkpoints: []}), do: nil
  def latest_checkpoint(%__MODULE__{checkpoints: [latest | _]}), do: latest

  @doc """
  Calculates job duration in milliseconds.
  """
  def duration(%__MODULE__{started_at: nil}), do: 0
  def duration(%__MODULE__{started_at: started_at, completed_at: nil}) do
    System.monotonic_time(:millisecond) - started_at
  end
  def duration(%__MODULE__{started_at: started_at, completed_at: completed_at}) do
    completed_at - started_at
  end

  @doc """
  Checks if job is in a terminal state.
  """
  def terminal?(%__MODULE__{status: status}) do
    status in [:completed, :failed, :cancelled]
  end

  @doc """
  Checks if job is currently running.
  """
  def running?(%__MODULE__{status: :running}), do: true
  def running?(%__MODULE__{}), do: false

  @doc """
  Gets job summary for display.
  """
  def summary(%__MODULE__{} = job) do
    %{
      id: job.id,
      type: job.type,
      status: job.status,
      progress: job.progress,
      priority: job.priority,
      created_at: job.created_at,
      duration: duration(job),
      resource_requirements: job.resource_requirements
    }
  end

  @doc """
  Estimates completion time based on current progress.
  """
  def estimated_completion(%__MODULE__{progress: 0.0}), do: nil
  def estimated_completion(%__MODULE__{progress: progress, started_at: started_at}) when progress > 0.0 do
    current_time = System.monotonic_time(:millisecond)
    elapsed = current_time - started_at
    total_estimated = elapsed / progress
    remaining = total_estimated - elapsed
    
    current_time + round(remaining)
  end
  def estimated_completion(%__MODULE__{}), do: nil

  defp generate_id do
    "job_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp calculate_requirements(:codebase_analysis, _spec) do
    %{
      memory_mb: 512,
      cpu_percent: 40,
      disk_mb: 100,
      network_required: false
    }
  end

  defp calculate_requirements(:refactoring, spec) do
    base_memory = 256
    file_count = length(Map.get(spec, :target_files, []))
    memory_adjustment = min(file_count * 10, 256)  # Max 256MB additional
    
    %{
      memory_mb: base_memory + memory_adjustment,
      cpu_percent: 30,
      disk_mb: 50,
      network_required: false
    }
  end

  defp calculate_requirements(:documentation_generation, spec) do
    target_modules = length(Map.get(spec, :target_modules, []))
    memory_needed = max(128, target_modules * 5)
    
    %{
      memory_mb: memory_needed,
      cpu_percent: 25,
      disk_mb: 200,  # Documentation can be large
      network_required: Map.get(spec, :fetch_external_docs, false)
    }
  end

  defp calculate_requirements(:test_generation, spec) do
    target_functions = length(Map.get(spec, :target_functions, []))
    memory_needed = max(128, target_functions * 3)
    
    %{
      memory_mb: memory_needed,
      cpu_percent: 35,
      disk_mb: 75,
      network_required: false
    }
  end

  defp calculate_requirements(:dependency_analysis, _spec) do
    %{
      memory_mb: 192,
      cpu_percent: 20,
      disk_mb: 25,
      network_required: true  # May need to fetch dependency info
    }
  end

  defp calculate_requirements(:performance_analysis, spec) do
    target_files = length(Map.get(spec, :target_files, []))
    memory_needed = max(256, target_files * 15)
    
    %{
      memory_mb: memory_needed,
      cpu_percent: 50,
      disk_mb: 100,
      network_required: false
    }
  end

  defp calculate_requirements(:security_audit, spec) do
    scan_depth = Map.get(spec, :scan_depth, :standard)
    
    memory_multiplier = case scan_depth do
      :basic -> 1
      :standard -> 2
      :deep -> 4
    end
    
    %{
      memory_mb: 128 * memory_multiplier,
      cpu_percent: 45,
      disk_mb: 50,
      network_required: Map.get(spec, :check_vulnerabilities, false)
    }
  end

  defp calculate_requirements(_type, _spec) do
    # Default requirements for unknown job types
    %{
      memory_mb: 128,
      cpu_percent: 20,
      disk_mb: 25,
      network_required: false
    }
  end
end