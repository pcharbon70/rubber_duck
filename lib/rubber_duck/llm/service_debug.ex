defmodule RubberDuck.LLM.ServiceDebug do
  @moduledoc """
  Debug wrapper for LLM Service to trace execution
  """

  require Logger

  def trace_completion(opts) do
    Logger.info("[LLM Debug] ===== Starting LLM Service Completion =====")
    Logger.info("[LLM Debug] Options: #{inspect(opts, pretty: true)}")

    # Check if Service is running
    service_pid = Process.whereis(RubberDuck.LLM.Service)
    Logger.info("[LLM Debug] LLM Service PID: #{inspect(service_pid)}")

    if service_pid do
      # Get the service state
      Logger.info("[LLM Debug] Calling list_models...")

      models_result =
        try do
          RubberDuck.LLM.Service.list_models()
        catch
          kind, reason ->
            Logger.error("[LLM Debug] list_models failed: #{kind} - #{inspect(reason)}")
            {:error, {kind, reason}}
        end

      case models_result do
        {:ok, models} ->
          Logger.info("[LLM Debug] Available models:")

          Enum.each(models, fn model ->
            Logger.info("[LLM Debug]   #{model.model} (#{model.provider}) - Available: #{model.available}")
          end)

        error ->
          Logger.error("[LLM Debug] Failed to get models: #{inspect(error)}")
      end

      # Now try the completion
      Logger.info("[LLM Debug] Calling Service.completion with timeout tracking...")
      start_time = System.monotonic_time(:millisecond)

      task =
        Task.async(fn ->
          try do
            RubberDuck.LLM.Service.completion(opts)
          catch
            kind, reason ->
              {:error, {kind, reason}}
          end
        end)

      # Monitor with incremental timeouts
      check_intervals = [1000, 5000, 10000, 30000, 60000, 120_000]

      result = monitor_with_intervals(task, check_intervals, start_time)

      end_time = System.monotonic_time(:millisecond)
      Logger.info("[LLM Debug] Total time: #{end_time - start_time}ms")
      Logger.info("[LLM Debug] Result: #{inspect(result, pretty: true)}")

      result
    else
      Logger.error("[LLM Debug] LLM Service is not running!")
      {:error, :service_not_running}
    end
  end

  defp monitor_with_intervals(task, [], start_time) do
    # Final wait
    case Task.yield(task, 5000) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        Logger.error("[LLM Debug] Task did not complete after #{elapsed}ms")
        {:error, :final_timeout}
    end
  end

  defp monitor_with_intervals(task, [interval | rest], start_time) do
    case Task.yield(task, interval) do
      {:ok, result} ->
        result

      nil ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        Logger.info("[LLM Debug] Still running after #{elapsed}ms...")
        monitor_with_intervals(task, rest, start_time)
    end
  end
end
