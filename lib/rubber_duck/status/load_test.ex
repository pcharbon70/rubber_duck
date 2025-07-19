defmodule RubberDuck.Status.LoadTest do
  @moduledoc """
  Load testing framework for the Status Broadcasting System.
  
  Provides tools to simulate various load scenarios and measure
  system performance under stress.
  
  ## Usage
  
      # Run a simple load test
      LoadTest.run(:basic, duration: 30_000, rate: 100)
      
      # Run a burst test
      LoadTest.run(:burst, burst_size: 1000, interval: 5000)
      
      # Run a stress test
      LoadTest.run(:stress, conversations: 100, rate: 500)
  """
  
  require Logger
  
  alias RubberDuck.Status
  alias RubberDuck.Status.{Monitor, Debug}
  
  @type scenario :: :basic | :burst | :stress | :ramp_up | :sustained
  @type opts :: keyword()
  
  @doc """
  Runs a load test scenario.
  
  ## Scenarios
  
  - `:basic` - Steady rate of messages
  - `:burst` - Periodic bursts of messages
  - `:stress` - High load stress test
  - `:ramp_up` - Gradually increasing load
  - `:sustained` - Long-running sustained load
  
  ## Options
  
  - `:duration` - Test duration in milliseconds (default: 10_000)
  - `:rate` - Messages per second (default: 100)
  - `:conversations` - Number of conversations (default: 10)
  - `:categories` - List of categories to use
  - `:report` - Whether to generate a report (default: true)
  """
  @spec run(scenario(), opts()) :: {:ok, map()} | {:error, term()}
  def run(scenario, opts \\ []) do
    Logger.info("Starting load test: #{scenario}")
    
    # Capture initial state
    initial_state = capture_system_state()
    
    # Start monitoring
    monitor_ref = start_monitoring()
    
    # Run the scenario
    test_pid = spawn_link(fn ->
      run_scenario(scenario, opts)
    end)
    
    # Wait for completion
    duration = Keyword.get(opts, :duration, 10_000)
    Process.sleep(duration)
    
    # Stop the test
    Process.exit(test_pid, :normal)
    
    # Capture final state
    final_state = capture_system_state()
    
    # Stop monitoring
    stop_monitoring(monitor_ref)
    
    # Generate report
    report = if Keyword.get(opts, :report, true) do
      generate_report(scenario, opts, initial_state, final_state, monitor_ref)
    else
      %{}
    end
    
    {:ok, report}
  end
  
  @doc """
  Runs multiple scenarios and compares results.
  """
  def benchmark(scenarios \\ [:basic, :burst, :stress], opts \\ []) do
    results = Enum.map(scenarios, fn scenario ->
      Logger.info("Running benchmark scenario: #{scenario}")
      {:ok, report} = run(scenario, opts)
      {scenario, report}
    end)
    
    comparison = compare_results(results)
    
    {:ok, %{
      scenarios: Map.new(results),
      comparison: comparison
    }}
  end
  
  @doc """
  Simulates a real-world usage pattern.
  """
  def simulate_realistic_load(opts \\ []) do
    duration = Keyword.get(opts, :duration, 60_000)  # 1 minute
    
    # Create conversation pools
    active_conversations = create_conversation_pool(20)
    occasional_conversations = create_conversation_pool(50)
    
    # Start simulation
    Task.start(fn ->
      simulate_realistic_pattern(
        active_conversations,
        occasional_conversations,
        duration
      )
    end)
    
    {:ok, %{
      duration: duration,
      active_conversations: length(active_conversations),
      occasional_conversations: length(occasional_conversations)
    }}
  end
  
  # Private Functions
  
  defp run_scenario(:basic, opts) do
    rate = Keyword.get(opts, :rate, 100)
    conversations = create_conversation_pool(Keyword.get(opts, :conversations, 10))
    categories = Keyword.get(opts, :categories, ["thinking", "processing", "ready"])
    
    message_interval = div(1000, rate)
    
    run_basic_load(conversations, categories, message_interval)
  end
  
  defp run_scenario(:burst, opts) do
    burst_size = Keyword.get(opts, :burst_size, 500)
    burst_interval = Keyword.get(opts, :interval, 5000)
    conversations = create_conversation_pool(Keyword.get(opts, :conversations, 20))
    categories = Keyword.get(opts, :categories, ["thinking", "processing", "ready"])
    
    run_burst_load(conversations, categories, burst_size, burst_interval)
  end
  
  defp run_scenario(:stress, opts) do
    rate = Keyword.get(opts, :rate, 500)
    conversations = create_conversation_pool(Keyword.get(opts, :conversations, 100))
    categories = Keyword.get(opts, :categories, ["thinking", "processing", "ready", "error"])
    
    # Run at very high rate with no delays
    run_stress_load(conversations, categories, rate)
  end
  
  defp run_scenario(:ramp_up, opts) do
    initial_rate = Keyword.get(opts, :initial_rate, 10)
    max_rate = Keyword.get(opts, :max_rate, 200)
    ramp_duration = Keyword.get(opts, :ramp_duration, 30_000)
    conversations = create_conversation_pool(Keyword.get(opts, :conversations, 50))
    categories = Keyword.get(opts, :categories, ["thinking", "processing", "ready"])
    
    run_ramp_up_load(conversations, categories, initial_rate, max_rate, ramp_duration)
  end
  
  defp run_scenario(:sustained, opts) do
    rate = Keyword.get(opts, :rate, 50)
    conversations = create_conversation_pool(Keyword.get(opts, :conversations, 30))
    categories = Keyword.get(opts, :categories, ["thinking", "processing", "ready"])
    
    # Run at moderate rate for extended period
    message_interval = div(1000, rate)
    run_basic_load(conversations, categories, message_interval)
  end
  
  defp run_basic_load(conversations, categories, interval) do
    conversation = Enum.random(conversations)
    category = Enum.random(categories)
    
    Status.broadcast(
      conversation,
      category,
      generate_test_message(),
      %{load_test: true, timestamp: System.monotonic_time(:millisecond)}
    )
    
    Process.sleep(interval)
    run_basic_load(conversations, categories, interval)
  end
  
  defp run_burst_load(conversations, categories, burst_size, interval) do
    # Send burst
    for _ <- 1..burst_size do
      conversation = Enum.random(conversations)
      category = Enum.random(categories)
      
      Status.broadcast(
        conversation,
        category,
        generate_test_message(),
        %{load_test: true, burst: true}
      )
    end
    
    Process.sleep(interval)
    run_burst_load(conversations, categories, burst_size, interval)
  end
  
  defp run_stress_load(conversations, categories, rate) do
    # Spawn multiple processes to achieve high rate
    worker_count = min(rate, 100)
    messages_per_worker = div(rate, worker_count)
    
    for _ <- 1..worker_count do
      Task.start(fn ->
        stress_worker(conversations, categories, messages_per_worker)
      end)
    end
    
    Process.sleep(1000)
    run_stress_load(conversations, categories, rate)
  end
  
  defp stress_worker(conversations, categories, messages_per_second) do
    for _ <- 1..messages_per_second do
      Status.broadcast(
        Enum.random(conversations),
        Enum.random(categories),
        generate_test_message(),
        %{load_test: true, stress: true}
      )
    end
  end
  
  defp run_ramp_up_load(conversations, categories, current_rate, max_rate, ramp_duration) do
    if current_rate < max_rate do
      # Send messages at current rate
      interval = div(1000, current_rate)
      
      for _ <- 1..current_rate do
        Task.start(fn ->
          Status.broadcast(
            Enum.random(conversations),
            Enum.random(categories),
            generate_test_message(),
            %{load_test: true, ramp_up: true, rate: current_rate}
          )
        end)
      end
      
      Process.sleep(1000)
      
      # Increase rate
      rate_increment = (max_rate - current_rate) / (ramp_duration / 1000)
      new_rate = min(current_rate + rate_increment, max_rate)
      
      run_ramp_up_load(conversations, categories, round(new_rate), max_rate, ramp_duration - 1000)
    else
      # Continue at max rate
      run_basic_load(conversations, categories, div(1000, max_rate))
    end
  end
  
  defp simulate_realistic_pattern(active_convs, occasional_convs, remaining_duration) do
    if remaining_duration > 0 do
      # Active conversations - frequent updates
      for conv <- Enum.take_random(active_convs, 3) do
        Status.broadcast(
          conv,
          Enum.random(["thinking", "processing"]),
          generate_test_message(),
          %{load_test: true, pattern: :active}
        )
      end
      
      # Occasional conversations - sporadic updates
      if :rand.uniform() < 0.3 do
        conv = Enum.random(occasional_convs)
        Status.broadcast(
          conv,
          Enum.random(["ready", "idle", "complete"]),
          generate_test_message(),
          %{load_test: true, pattern: :occasional}
        )
      end
      
      # Random delay to simulate real usage
      delay = :rand.uniform(500) + 100
      Process.sleep(delay)
      
      simulate_realistic_pattern(active_convs, occasional_convs, remaining_duration - delay)
    end
  end
  
  defp create_conversation_pool(count) do
    for i <- 1..count do
      "load_test_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}_#{i}"
    end
  end
  
  defp generate_test_message do
    messages = [
      "Processing request...",
      "Analyzing data...",
      "Generating response...",
      "Task completed",
      "Waiting for input",
      "Running calculations",
      "Optimizing results",
      "Validating output"
    ]
    
    Enum.random(messages)
  end
  
  defp capture_system_state do
    %{
      timestamp: System.monotonic_time(:millisecond),
      queue_depth: get_queue_depth(),
      channel_count: length(Debug.list_channels()),
      memory: :erlang.memory(:total),
      health: Debug.health_check(),
      metrics: Monitor.metrics_summary()
    }
  end
  
  defp get_queue_depth do
    case Debug.dump_queue() do
      %{queue_size: size} -> size
      _ -> 0
    end
  end
  
  defp start_monitoring do
    ref = make_ref()
    
    # Start collecting detailed metrics
    :persistent_term.put({__MODULE__, ref, :metrics}, [])
    
    # Start monitoring process
    Task.start(fn ->
      monitor_loop(ref)
    end)
    
    ref
  end
  
  defp monitor_loop(ref) do
    # Collect metrics every 100ms
    metrics = %{
      timestamp: System.monotonic_time(:millisecond),
      queue_depth: get_queue_depth(),
      memory_mb: :erlang.memory(:total) / 1_048_576
    }
    
    current = :persistent_term.get({__MODULE__, ref, :metrics}, [])
    :persistent_term.put({__MODULE__, ref, :metrics}, [metrics | current])
    
    Process.sleep(100)
    monitor_loop(ref)
  end
  
  defp stop_monitoring(ref) do
    # Clean up
    :persistent_term.put({__MODULE__, ref, :stop}, true)
  end
  
  defp generate_report(scenario, opts, initial_state, final_state, monitor_ref) do
    duration = Keyword.get(opts, :duration, 10_000)
    metrics = :persistent_term.get({__MODULE__, monitor_ref, :metrics}, []) |> Enum.reverse()
    
    %{
      scenario: scenario,
      duration_ms: duration,
      options: opts,
      summary: %{
        total_time_ms: final_state.timestamp - initial_state.timestamp,
        initial_queue_depth: initial_state.queue_depth,
        final_queue_depth: final_state.queue_depth,
        max_queue_depth: metrics |> Enum.map(& &1.queue_depth) |> Enum.max(fn -> 0 end),
        initial_channels: initial_state.channel_count,
        final_channels: final_state.channel_count,
        memory_growth_mb: (final_state.memory - initial_state.memory) / 1_048_576,
        health_before: initial_state.health.healthy,
        health_after: final_state.health.healthy
      },
      performance_metrics: calculate_performance_metrics(metrics, initial_state, final_state),
      recommendations: generate_recommendations(scenario, metrics, final_state)
    }
  end
  
  defp calculate_performance_metrics(metrics, initial_state, final_state) do
    queue_depths = Enum.map(metrics, & &1.queue_depth)
    
    %{
      avg_queue_depth: average(queue_depths),
      p95_queue_depth: percentile(queue_depths, 0.95),
      p99_queue_depth: percentile(queue_depths, 0.99),
      queue_depth_variance: variance(queue_depths),
      memory_usage_mb: %{
        min: metrics |> Enum.map(& &1.memory_mb) |> Enum.min(fn -> 0 end),
        max: metrics |> Enum.map(& &1.memory_mb) |> Enum.max(fn -> 0 end),
        average: metrics |> Enum.map(& &1.memory_mb) |> average()
      }
    }
  end
  
  defp generate_recommendations(scenario, metrics, final_state) do
    recommendations = []
    
    # Check queue depth
    max_queue = metrics |> Enum.map(& &1.queue_depth) |> Enum.max(fn -> 0 end)
    recommendations = if max_queue > 5000 do
      ["Consider increasing batch size or flush rate to handle high queue depth" | recommendations]
    else
      recommendations
    end
    
    # Check memory growth
    memory_growth = List.last(metrics).memory_mb - List.first(metrics).memory_mb
    recommendations = if memory_growth > 100 do
      ["High memory growth detected (#{Float.round(memory_growth, 2)}MB). Check for memory leaks." | recommendations]
    else
      recommendations
    end
    
    # Scenario-specific recommendations
    recommendations = case scenario do
      :stress ->
        ["System handled stress test. Consider implementing backpressure mechanisms." | recommendations]
      :burst ->
        ["Burst handling successful. Monitor queue recovery time after bursts." | recommendations]
      _ ->
        recommendations
    end
    
    recommendations
  end
  
  defp compare_results(results) do
    scenarios = Map.new(results)
    
    %{
      queue_depth_comparison: compare_metric(scenarios, [:summary, :max_queue_depth]),
      memory_growth_comparison: compare_metric(scenarios, [:summary, :memory_growth_mb]),
      performance_comparison: compare_performance(scenarios)
    }
  end
  
  defp compare_metric(scenarios, path) do
    scenarios
    |> Enum.map(fn {name, report} ->
      {name, get_in(report, path)}
    end)
    |> Enum.sort_by(&elem(&1, 1))
  end
  
  defp compare_performance(scenarios) do
    scenarios
    |> Enum.map(fn {name, report} ->
      perf = get_in(report, [:performance_metrics])
      {name, %{
        avg_queue_depth: perf[:avg_queue_depth],
        p95_queue_depth: perf[:p95_queue_depth]
      }}
    end)
  end
  
  # Statistical helpers
  
  defp average([]), do: 0
  defp average(list) do
    Enum.sum(list) / length(list)
  end
  
  defp variance(list) do
    avg = average(list)
    
    squared_diffs = Enum.map(list, fn x -> :math.pow(x - avg, 2) end)
    average(squared_diffs)
  end
  
  defp percentile(list, p) when is_list(list) and list != [] do
    sorted = Enum.sort(list)
    index = round(p * (length(sorted) - 1))
    Enum.at(sorted, index)
  end
  defp percentile(_, _), do: 0
end