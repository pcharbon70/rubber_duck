defmodule RubberDuck.Telemetry.Measurements do
  @moduledoc """
  Custom periodic measurements for RubberDuck application telemetry.
  """

  def dispatch_vm_metrics do
    memory = :erlang.memory()
    
    :telemetry.execute(
      [:vm, :memory],
      %{
        total: memory[:total],
        processes: memory[:processes],
        processes_used: memory[:processes_used],
        system: memory[:system],
        binary: memory[:binary],
        ets: memory[:ets]
      },
      %{}
    )

    _cpu_info = :erlang.statistics(:scheduler_wall_time)
    
    :telemetry.execute(
      [:vm, :total_run_queue_lengths],
      %{
        total: :erlang.statistics(:total_run_queue_lengths),
        cpu: :erlang.statistics(:run_queue),
        io: 0
      },
      %{}
    )
  end

  def dispatch_db_pool_metrics do
    # This will be implemented when we have database pools configured
    # For now, it's a placeholder for future pool metrics
    :ok
  end

  def dispatch_application_metrics do
    # Custom application-specific metrics can be added here
    # For example: active projects count, files being analyzed, etc.
    :telemetry.execute(
      [:rubber_duck, :application],
      %{
        uptime: System.monotonic_time(:second)
      },
      %{}
    )
  end
end
