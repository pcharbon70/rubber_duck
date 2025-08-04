defmodule RubberDuck.Jido.Signals.Pipeline.PipelineOrchestratorTest do
  use ExUnit.Case
  
  alias RubberDuck.Jido.Signals.Pipeline.PipelineOrchestrator
  
  setup do
    # Start orchestrator with minimal config for testing
    {:ok, pid} = PipelineOrchestrator.start_link(
      monitors: [],  # No monitors for testing
      transformers: []  # We'll test with specific transformers
    )
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)
    
    {:ok, orchestrator: pid}
  end
  
  describe "process/2" do
    test "processes a valid signal through empty pipeline" do
      signal = %{
        type: "test.signal",
        source: "test:unit",
        data: %{message: "test"}
      }
      
      assert {:ok, processed} = PipelineOrchestrator.process(signal)
      assert processed.type == "test.signal"
    end
    
    test "rejects invalid Jido signal" do
      invalid_signal = %{invalid: "signal"}
      
      assert {:error, {:invalid_jido_signal, _}} = PipelineOrchestrator.process(invalid_signal)
    end
  end
  
  describe "process_batch/2" do
    test "processes multiple signals in batch" do
      signals = [
        %{type: "test.one", source: "test", data: %{}},
        %{type: "test.two", source: "test", data: %{}},
        %{type: "test.three", source: "test", data: %{}}
      ]
      
      assert {:ok, processed} = PipelineOrchestrator.process_batch(signals)
      assert length(processed) == 3
    end
    
    test "reports batch processing failures" do
      signals = [
        %{type: "test.valid", source: "test", data: %{}},
        %{invalid: "signal"},
        %{type: "test.another", source: "test", data: %{}}
      ]
      
      assert {:error, {:batch_processing_failed, failures}} = 
        PipelineOrchestrator.process_batch(signals)
      assert length(failures) > 0
    end
  end
  
  describe "health_check/0" do
    test "returns health status" do
      health = PipelineOrchestrator.health_check()
      
      assert Map.has_key?(health, :status)
      assert health.status in [:healthy, :degraded, :unhealthy]
      assert Map.has_key?(health, :stats)
    end
  end
  
  describe "get_metrics/0" do
    test "returns pipeline metrics" do
      # Process some signals first
      PipelineOrchestrator.process(%{
        type: "test.signal",
        source: "test",
        data: %{}
      })
      
      metrics = PipelineOrchestrator.get_metrics()
      
      assert Map.has_key?(metrics, :pipeline_stats)
      assert metrics.pipeline_stats.processed >= 0
      assert Map.has_key?(metrics, :average_processing_time)
    end
  end
  
  describe "configuration" do
    test "gets current configuration" do
      config = PipelineOrchestrator.get_config()
      
      assert is_map(config)
      assert Map.has_key?(config, :max_concurrency)
      assert Map.has_key?(config, :strict_validation)
    end
    
    test "updates configuration" do
      assert :ok = PipelineOrchestrator.update_config(%{
        max_concurrency: 5,
        strict_validation: true
      })
      
      config = PipelineOrchestrator.get_config()
      assert config.max_concurrency == 5
      assert config.strict_validation == true
    end
  end
end