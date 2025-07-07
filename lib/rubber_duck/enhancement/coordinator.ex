defmodule RubberDuck.Enhancement.Coordinator do
  @moduledoc """
  Central coordinator for LLM enhancement techniques.

  Manages the selection, composition, and execution of enhancement
  techniques (CoT, RAG, Self-Correction) based on task requirements.
  """

  use GenServer
  require Logger

  alias RubberDuck.Enhancement.{TechniqueSelector, PipelineBuilder, MetricsCollector}
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrectionEngine

  @type task :: %{
          type: atom(),
          content: String.t(),
          context: map(),
          options: keyword()
        }

  @type enhancement_result :: %{
          original: String.t(),
          enhanced: String.t(),
          techniques_applied: [atom()],
          metrics: map(),
          metadata: map()
        }

  # Client API

  @doc """
  Starts the enhancement coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enhances content using appropriate techniques.

  ## Options
  - `:techniques` - Specific techniques to use (overrides auto-selection)
  - `:pipeline_type` - :sequential, :parallel, or :conditional
  - `:max_iterations` - Maximum enhancement iterations
  - `:timeout` - Overall timeout for enhancement
  """
  @spec enhance(task(), keyword()) :: {:ok, enhancement_result()} | {:error, term()}
  def enhance(task, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    GenServer.call(__MODULE__, {:enhance, task, opts}, timeout)
  end

  @doc """
  Runs A/B test comparing different technique combinations.
  """
  @spec ab_test(task(), list(keyword())) :: {:ok, map()} | {:error, term()}
  def ab_test(task, variants) do
    GenServer.call(__MODULE__, {:ab_test, task, variants}, 120_000)
  end

  @doc """
  Gets current enhancement statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Updates configuration at runtime.
  """
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.cast(__MODULE__, {:update_config, config})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      config: build_initial_config(opts),
      stats: %{
        total_enhancements: 0,
        technique_usage: %{},
        avg_improvement: 0.0,
        errors: 0
      },
      active_enhancements: %{}
    }

    # Subscribe to telemetry events
    :telemetry.attach_many(
      "enhancement-coordinator",
      [
        [:rubber_duck, :enhancement, :start],
        [:rubber_duck, :enhancement, :stop],
        [:rubber_duck, :enhancement, :exception]
      ],
      &handle_telemetry_event/4,
      nil
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:enhance, task, opts}, from, state) do
    enhancement_id = generate_enhancement_id()

    # Start telemetry span
    metadata = %{
      enhancement_id: enhancement_id,
      task_type: task.type,
      techniques: opts[:techniques]
    }

    :telemetry.execute(
      [:rubber_duck, :enhancement, :start],
      %{system_time: System.system_time()},
      metadata
    )

    # Track active enhancement
    state =
      put_in(state, [:active_enhancements, enhancement_id], %{
        task: task,
        opts: opts,
        from: from,
        started_at: DateTime.utc_now()
      })

    # Spawn enhancement process
    Task.start(fn ->
      result = do_enhance(task, opts, state.config)
      GenServer.cast(__MODULE__, {:enhancement_complete, enhancement_id, result})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:ab_test, task, variants}, _from, state) do
    result = run_ab_test(task, variants, state.config)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end

  @impl true
  def handle_cast({:update_config, config}, state) do
    new_config = Map.merge(state.config, config)
    {:noreply, %{state | config: new_config}}
  end

  @impl true
  def handle_cast({:enhancement_complete, enhancement_id, result}, state) do
    case Map.get(state.active_enhancements, enhancement_id) do
      nil ->
        {:noreply, state}

      %{from: from} = enhancement ->
        # Reply to caller
        GenServer.reply(from, result)

        # Update stats
        state = update_stats(state, enhancement, result)

        # Clean up
        state = update_in(state.active_enhancements, &Map.delete(&1, enhancement_id))

        # Complete telemetry span
        :telemetry.execute(
          [:rubber_duck, :enhancement, :stop],
          %{duration: DateTime.diff(DateTime.utc_now(), enhancement.started_at, :microsecond)},
          %{enhancement_id: enhancement_id, result: result}
        )

        {:noreply, state}
    end
  end

  # Private functions

  defp do_enhance(task, opts, config) do
    try do
      # Select techniques
      techniques =
        if opts[:techniques] do
          opts[:techniques]
        else
          TechniqueSelector.select_techniques(task, config)
        end

      # Build pipeline
      pipeline_type = opts[:pipeline_type] || :sequential
      pipeline = PipelineBuilder.build(techniques, pipeline_type, config)

      # Execute enhancement
      result = execute_pipeline(pipeline, task, opts)

      # Collect metrics
      metrics = MetricsCollector.collect(result, techniques)

      {:ok,
       %{
         original: task.content,
         enhanced: result.content,
         techniques_applied: techniques,
         metrics: metrics,
         metadata: %{
           pipeline_type: pipeline_type,
           iterations: result[:iterations] || 1,
           duration_ms: result[:duration_ms]
         }
       }}
    rescue
      e ->
        Logger.error("Enhancement failed: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp execute_pipeline(pipeline, task, opts) do
    start_time = System.monotonic_time(:millisecond)

    result =
      Enum.reduce(pipeline, %{content: task.content, context: task.context}, fn step, acc ->
        apply_technique(step, acc, opts)
      end)

    duration_ms = System.monotonic_time(:millisecond) - start_time
    Map.put(result, :duration_ms, duration_ms)
  end

  defp apply_technique({:cot, config}, data, _opts) do
    # Apply Chain-of-Thought reasoning
    # For now, using a simplified approach since we need a chain module
    # In production, this would select or generate appropriate chain
    case apply_cot_reasoning(data.content, config) do
      {:ok, result} ->
        %{data | content: result.output, context: Map.put(data.context, :cot_chain, result.chain)}

      {:error, _reason} ->
        data
    end
  end

  defp apply_technique({:rag, config}, data, _opts) do
    # Apply RAG enhancement
    case apply_rag_enhancement(data.content, data.context, config) do
      {:ok, enhanced} ->
        %{data | content: enhanced.content, context: Map.put(data.context, :rag_sources, enhanced.sources)}

      {:error, _reason} ->
        data
    end
  end

  defp apply_technique({:self_correction, config}, data, opts) do
    # Apply self-correction
    max_iterations = opts[:max_iterations] || config[:max_iterations] || 3

    case SelfCorrectionEngine.correct(%{
           content: data.content,
           type: data.context[:content_type] || :text,
           context: data.context,
           options: [max_iterations: max_iterations]
         }) do
      {:ok, result} ->
        %{
          data
          | content: result.corrected_content,
            context: Map.put(data.context, :corrections_applied, result.corrections),
            iterations: result.iterations
        }

      {:error, _reason} ->
        data
    end
  end

  defp apply_technique({:parallel, techniques}, data, opts) do
    # Execute techniques in parallel
    tasks =
      Enum.map(techniques, fn technique ->
        Task.async(fn -> apply_technique(technique, data, opts) end)
      end)

    results = Task.await_many(tasks, 30_000)

    # Merge results (for now, take the last one - could be smarter)
    List.last(results) || data
  end

  defp apply_technique({:conditional, condition, true_branch, false_branch}, data, opts) do
    if evaluate_condition(condition, data) do
      apply_technique(true_branch, data, opts)
    else
      apply_technique(false_branch, data, opts)
    end
  end

  defp evaluate_condition({:has_errors, _}, data) do
    # Check if content has errors (simplified)
    String.contains?(data.content, ["error", "Error", "ERROR"])
  end

  defp evaluate_condition({:content_type, type}, data) do
    data.context[:content_type] == type
  end

  defp evaluate_condition(_condition, _data), do: true

  defp run_ab_test(task, variants, config) do
    results =
      Enum.map(variants, fn variant_opts ->
        case do_enhance(task, variant_opts, config) do
          {:ok, result} -> %{variant: variant_opts, result: result, success: true}
          {:error, reason} -> %{variant: variant_opts, error: reason, success: false}
        end
      end)

    analysis = analyze_ab_results(results)

    {:ok,
     %{
       task: task,
       variants: results,
       analysis: analysis,
       winner: analysis.winner
     }}
  end

  defp analyze_ab_results(results) do
    successful_results = Enum.filter(results, & &1.success)

    if Enum.empty?(successful_results) do
      %{winner: nil, reason: "All variants failed"}
    else
      # Simple analysis - compare improvement scores
      scored_results =
        Enum.map(successful_results, fn r ->
          score = calculate_improvement_score(r.result)
          {r.variant, score}
        end)

      {winner, best_score} = Enum.max_by(scored_results, fn {_variant, score} -> score end)

      %{
        winner: winner,
        best_score: best_score,
        all_scores: scored_results
      }
    end
  end

  defp calculate_improvement_score(result) do
    # Simple scoring based on metrics
    base_score = Map.get(result.metrics, :quality_improvement, 0.0)

    # Bonus for using multiple techniques effectively
    technique_bonus = length(result.techniques_applied) * 0.1

    # Penalty for long execution time
    time_penalty = if result.metadata[:duration_ms] > 10_000, do: -0.2, else: 0

    base_score + technique_bonus + time_penalty
  end

  defp update_stats(state, _enhancement, {:ok, result}) do
    state
    |> update_in([:stats, :total_enhancements], &(&1 + 1))
    |> update_in([:stats, :technique_usage], fn usage ->
      Enum.reduce(result.techniques_applied, usage, fn tech, acc ->
        Map.update(acc, tech, 1, &(&1 + 1))
      end)
    end)
    |> update_in([:stats, :avg_improvement], fn avg ->
      improvement = Map.get(result.metrics, :quality_improvement, 0.0)
      total = state.stats.total_enhancements
      (avg * total + improvement) / (total + 1)
    end)
  end

  defp update_stats(state, _enhancement, {:error, _reason}) do
    update_in(state, [:stats, :errors], &(&1 + 1))
  end

  defp build_initial_config(opts) do
    %{
      default_pipeline_type: :sequential,
      technique_timeouts: %{
        cot: 30_000,
        rag: 20_000,
        self_correction: 40_000
      },
      max_parallel_techniques: 3,
      ab_test_min_samples: 10
    }
    |> Map.merge(Enum.into(opts, %{}))
  end

  defp generate_enhancement_id do
    "enh_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end

  defp handle_telemetry_event(_event, _measurements, _metadata, _config) do
    # Telemetry handling is done elsewhere
    :ok
  end

  # Simplified CoT application for now
  defp apply_cot_reasoning(content, config) do
    # In production, this would use the actual CoT system
    # For now, return a simulated enhancement
    chain_type = config[:chain_type] || :default

    enhanced =
      case chain_type do
        :explanation -> "Let me explain step by step:\n\n#{content}\n\nIn conclusion..."
        :generation -> "Based on the requirements:\n\n#{content}\n\nImplementation details..."
        :analysis -> "Analyzing the following:\n\n#{content}\n\nKey findings..."
        _ -> "Reasoning about: #{content}"
      end

    {:ok,
     %{
       output: enhanced,
       chain: %{
         steps: [:understand, :analyze, :conclude],
         chain_type: chain_type
       }
     }}
  end

  # Simplified RAG enhancement for now
  defp apply_rag_enhancement(content, _context, config) do
    # In production, this would use the actual RAG pipeline
    # For now, return a simulated enhancement
    retrieval_strategy = config[:retrieval_strategy] || :semantic

    sources = [
      %{type: :documentation, relevance: 0.9},
      %{type: :similar_code, relevance: 0.8}
    ]

    enhanced = "#{content}\n\n[Enhanced with relevant context from #{retrieval_strategy} retrieval]"

    {:ok,
     %{
       content: enhanced,
       sources: sources
     }}
  end
end
