defmodule RubberDuck.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    # Check if console reporter is enabled
    console_reporter_config = Application.get_env(:rubber_duck, :telemetry, [])[:console_reporter] || []
    console_reporter_enabled = Keyword.get(console_reporter_config, :enabled, false)

    children =
      if console_reporter_enabled do
        [
          {Telemetry.Metrics.ConsoleReporter, metrics: metrics()},
          {
            :telemetry_poller,
            measurements: periodic_measurements(), period: 10_000, name: :rubber_duck_poller
          }
        ]
      else
        [
          {
            :telemetry_poller,
            measurements: periodic_measurements(), period: 10_000, name: :rubber_duck_poller
          }
        ]
      end

    # Attach Ash telemetry handlers
    RubberDuck.Telemetry.AshHandler.attach()

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: :millisecond,
        tags: [:route]
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: :millisecond,
        tags: [:route]
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: :millisecond
      ),

      # Database Metrics
      summary("rubber_duck.repo.query.total_time",
        unit: :millisecond,
        description: "The sum of the other measurements"
      ),
      summary("rubber_duck.repo.query.decode_time",
        unit: :millisecond,
        description: "The time spent decoding the data received from the database"
      ),
      summary("rubber_duck.repo.query.query_time",
        unit: :millisecond,
        description: "The time spent executing the query"
      ),
      summary("rubber_duck.repo.query.queue_time",
        unit: :millisecond,
        description: "The time spent waiting for a database connection"
      ),
      summary("rubber_duck.repo.query.idle_time",
        unit: :millisecond,
        description: "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: :byte),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Ash Framework Metrics
      counter("ash.request.start.count",
        tags: [:resource, :action]
      ),
      summary("ash.request.stop.duration",
        unit: :millisecond,
        tags: [:resource, :action]
      ),
      counter("ash.request.error.count",
        tags: [:resource, :action, :error]
      ),

      # Custom RubberDuck Metrics
      counter("rubber_duck.analysis.start.count",
        tags: [:analysis_type]
      ),
      summary("rubber_duck.analysis.stop.duration",
        unit: :millisecond,
        tags: [:analysis_type]
      ),
      counter("rubber_duck.llm_request.count",
        tags: [:provider, :model]
      ),
      summary("rubber_duck.llm_request.duration",
        unit: :millisecond,
        tags: [:provider, :model]
      ),
      counter("rubber_duck.code_file.indexed.count",
        tags: [:language]
      ),
      summary("rubber_duck.embedding.generation.duration",
        unit: :millisecond,
        tags: [:model]
      )
    ]
  end

  defp periodic_measurements do
    [
      {RubberDuck.Telemetry.Measurements, :dispatch_vm_metrics, []}
    ]
  end
end
