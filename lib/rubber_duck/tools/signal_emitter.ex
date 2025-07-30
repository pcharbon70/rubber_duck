defmodule RubberDuck.Tools.SignalEmitter do
  @moduledoc """
  Emits a Jido signal to trigger workflows or agent communication.
  
  This tool integrates with the Jido agent system to emit signals that can
  trigger workflows, notify other agents, or coordinate distributed tasks.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :signal_emitter
    description "Emits a Jido signal to trigger workflows or agent communication"
    category :integration
    version "1.0.0"
    tags [:jido, :workflow, :signals, :coordination]
    
    parameter :signal_type do
      type :string
      required true
      description "Type of signal to emit"
      constraints [
        min_length: 1,
        max_length: 100
      ]
    end
    
    parameter :payload do
      type :map
      required false
      description "Data payload to include with the signal"
      default %{}
    end
    
    parameter :target do
      type :string
      required false
      description "Target agent or workflow to receive the signal"
      default "*"
    end
    
    parameter :priority do
      type :string
      required false
      description "Signal priority level"
      default "normal"
      constraints [
        enum: ["low", "normal", "high", "urgent"]
      ]
    end
    
    parameter :broadcast do
      type :boolean
      required false
      description "Whether to broadcast to all listeners"
      default false
    end
    
    parameter :timeout_ms do
      type :integer
      required false
      description "Timeout for signal acknowledgment (ms)"
      default 5000
      constraints [
        min: 100,
        max: 60000
      ]
    end
    
    parameter :retry_count do
      type :integer
      required false
      description "Number of retry attempts if signal fails"
      default 0
      constraints [
        min: 0,
        max: 5
      ]
    end
    
    parameter :metadata do
      type :map
      required false
      description "Additional metadata for the signal"
      default %{}
    end
    
    parameter :synchronous do
      type :boolean
      required false
      description "Wait for signal processing completion"
      default false
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :restricted
      capabilities [:jido_signal]
      rate_limit 200
    end
  end
  
  @doc """
  Executes signal emission to the Jido system.
  """
  def execute(params, context) do
    with {:ok, signal} <- build_signal(params, context),
         {:ok, emitted} <- emit_signal(signal, params),
         {:ok, result} <- handle_signal_response(emitted, params) do
      
      {:ok, %{
        signal_id: result.signal_id,
        status: result.status,
        target: params.target,
        signal_type: params.signal_type,
        emitted_at: result.emitted_at,
        acknowledgments: result.acknowledgments,
        metadata: %{
          priority: params.priority,
          broadcast: params.broadcast,
          retry_count: params.retry_count,
          synchronous: params.synchronous
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp build_signal(params, context) do
    signal = %{
      id: generate_signal_id(),
      type: params.signal_type,
      payload: enrich_payload(params.payload, context),
      target: parse_target(params.target),
      priority: String.to_atom(params.priority),
      broadcast: params.broadcast,
      timeout_ms: params.timeout_ms,
      retry_count: params.retry_count,
      metadata: build_metadata(params, context),
      synchronous: params.synchronous,
      emitted_by: context[:agent_id] || "rubber_duck_tools",
      created_at: DateTime.utc_now()
    }
    
    {:ok, signal}
  end
  
  defp generate_signal_id do
    "signal_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
  
  defp enrich_payload(payload, context) do
    # Add context information to payload
    enriched = Map.merge(payload, %{
      "source" => "rubber_duck_tools",
      "tool" => "signal_emitter",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
    
    # Add project context if available
    enriched = if context[:project_root] do
      Map.put(enriched, "project_root", context[:project_root])
    else
      enriched
    end
    
    # Add session context if available
    enriched = if context[:session_id] do
      Map.put(enriched, "session_id", context[:session_id])
    else
      enriched
    end
    
    enriched
  end
  
  defp parse_target("*"), do: :broadcast
  defp parse_target("all"), do: :broadcast
  defp parse_target(target) when is_binary(target) do
    cond do
      String.contains?(target, ".") -> {:agent, target}
      String.contains?(target, ":") -> {:workflow, target}
      true -> {:agent, target}
    end
  end
  
  defp build_metadata(params, context) do
    base_metadata = Map.merge(params.metadata, %{
      "emitter_tool" => "signal_emitter",
      "emitter_version" => "1.0.0",
      "ruby_duck_version" => context[:version] || "unknown"
    })
    
    # Add trace information if available
    base_metadata = if context[:trace_id] do
      Map.put(base_metadata, "trace_id", context[:trace_id])
    else
      base_metadata
    end
    
    base_metadata
  end
  
  defp emit_signal(signal, params) do
    # In a real implementation, this would interface with the Jido system
    # For now, we'll simulate the signal emission
    
    case attempt_signal_emission(signal, params.retry_count + 1) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "Failed to emit signal: #{reason}"}
    end
  end
  
  defp attempt_signal_emission(signal, attempts_left) when attempts_left > 0 do
    case simulate_jido_emission(signal) do
      {:ok, result} -> 
        {:ok, result}
      
      {:error, :temporary_failure} when attempts_left > 1 ->
        # Retry with exponential backoff
        backoff_ms = (5 - attempts_left) * 1000
        Process.sleep(backoff_ms)
        attempt_signal_emission(signal, attempts_left - 1)
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp attempt_signal_emission(_signal, 0) do
    {:error, "Max retry attempts exceeded"}
  end
  
  defp simulate_jido_emission(signal) do
    # Simulate different emission scenarios
    case :rand.uniform(10) do
      n when n <= 8 -> # 80% success rate
        simulate_successful_emission(signal)
      
      9 -> # 10% temporary failure
        {:error, :temporary_failure}
      
      10 -> # 10% permanent failure
        {:error, :permanent_failure}
    end
  end
  
  defp simulate_successful_emission(signal) do
    # Simulate successful signal emission
    emitted_at = DateTime.utc_now()
    
    # Simulate acknowledgments based on target type
    acknowledgments = case signal.target do
      :broadcast ->
        # Simulate multiple agents acknowledging
        simulate_broadcast_acks(signal)
      
      {:agent, agent_name} ->
        # Simulate single agent acknowledgment
        [simulate_agent_ack(agent_name, signal)]
      
      {:workflow, workflow_id} ->
        # Simulate workflow acknowledgment
        [simulate_workflow_ack(workflow_id, signal)]
    end
    
    result = %{
      signal_id: signal.id,
      status: :emitted,
      emitted_at: emitted_at,
      acknowledgments: acknowledgments,
      target_count: length(acknowledgments)
    }
    
    {:ok, result}
  end
  
  defp simulate_broadcast_acks(signal) do
    # Simulate 2-5 agents responding to broadcast
    agent_count = :rand.uniform(4) + 1
    
    1..agent_count
    |> Enum.map(fn i ->
      agent_name = "agent_#{i}"
      simulate_agent_ack(agent_name, signal)
    end)
  end
  
  defp simulate_agent_ack(agent_name, signal) do
    %{
      type: :agent_ack,
      agent: agent_name,
      signal_id: signal.id,
      acknowledged_at: DateTime.utc_now(),
      status: :received,
      processing_time_ms: :rand.uniform(100) + 10
    }
  end
  
  defp simulate_workflow_ack(workflow_id, signal) do
    %{
      type: :workflow_ack,
      workflow: workflow_id,
      signal_id: signal.id,
      acknowledged_at: DateTime.utc_now(),
      status: :queued,
      estimated_processing_time_ms: :rand.uniform(5000) + 1000
    }
  end
  
  defp handle_signal_response(emitted, params) do
    if params.synchronous do
      # Wait for processing completion
      wait_for_completion(emitted, params.timeout_ms)
    else
      # Return immediately with emission status
      {:ok, emitted}
    end
  end
  
  defp wait_for_completion(emitted, timeout_ms) do
    # Simulate waiting for signal processing completion
    wait_time = min(timeout_ms, 2000)  # Cap at 2 seconds for simulation
    Process.sleep(wait_time)
    
    # Simulate completion status
    completion_status = case :rand.uniform(4) do
      1 -> :completed
      2 -> :processing
      3 -> :failed
      4 -> :timeout
    end
    
    updated_result = Map.merge(emitted, %{
      status: completion_status,
      completed_at: DateTime.utc_now(),
      processing_duration_ms: wait_time
    })
    
    {:ok, updated_result}
  end
  
  # Utility functions for signal management
  
  @doc """
  Creates a code completion signal for triggering code generation workflows.
  """
  def code_completion_signal(code_context, options \\ %{}) do
    %{
      signal_type: "code.completion.requested",
      payload: %{
        "context" => code_context,
        "language" => "elixir",
        "options" => options
      },
      priority: "normal",
      target: "code_generation_workflow"
    }
  end
  
  @doc """
  Creates a test execution signal for triggering test runs.
  """
  def test_execution_signal(test_pattern, options \\ %{}) do
    %{
      signal_type: "test.execution.requested",
      payload: %{
        "pattern" => test_pattern,
        "options" => options
      },
      priority: "high",
      target: "test_runner_workflow"
    }
  end
  
  @doc """
  Creates an error analysis signal for debugging workflows.
  """
  def error_analysis_signal(error_data, context \\ %{}) do
    %{
      signal_type: "error.analysis.requested",
      payload: %{
        "error" => error_data,
        "context" => context
      },
      priority: "high",
      target: "debug_workflow"
    }
  end
  
  @doc """
  Creates a refactoring signal for code improvement workflows.
  """
  def refactoring_signal(code, refactoring_type, options \\ %{}) do
    %{
      signal_type: "code.refactoring.requested",
      payload: %{
        "code" => code,
        "refactoring_type" => refactoring_type,
        "options" => options
      },
      priority: "normal",
      target: "refactoring_workflow"
    }
  end
  
  @doc """
  Creates a documentation generation signal.
  """
  def documentation_signal(code_or_module, doc_type \\ "module") do
    %{
      signal_type: "documentation.generation.requested",
      payload: %{
        "target" => code_or_module,
        "type" => doc_type
      },
      priority: "low",
      target: "documentation_workflow"
    }
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end