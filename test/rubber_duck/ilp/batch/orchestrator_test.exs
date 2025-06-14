defmodule RubberDuck.ILP.Batch.OrchestratorTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.ILP.Batch.Orchestrator
  
  describe "batch orchestrator" do
    test "can submit a job" do
      job_spec = %{
        type: :codebase_analysis,
        target_files: ["lib/test.ex"],
        priority: 5
      }
      
      assert :ok = Orchestrator.submit_job(job_spec)
    end
    
    test "returns metrics" do
      metrics = Orchestrator.get_metrics()
      
      assert is_map(metrics)
      assert Map.has_key?(metrics, :jobs_submitted)
      assert Map.has_key?(metrics, :jobs_completed)
      assert Map.has_key?(metrics, :jobs_failed)
    end
    
    test "can list jobs" do
      jobs = Orchestrator.list_jobs()
      
      assert is_map(jobs)
      assert Map.has_key?(jobs, :queued)
      assert Map.has_key?(jobs, :active)
      assert is_list(jobs.queued)
      assert is_list(jobs.active)
    end
  end
end