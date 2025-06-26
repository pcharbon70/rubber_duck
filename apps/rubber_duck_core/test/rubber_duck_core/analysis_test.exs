defmodule RubberDuckCore.AnalysisTest do
  use ExUnit.Case, async: true

  alias RubberDuckCore.Analysis

  describe "new/1" do
    test "creates an analysis with default values" do
      analysis = Analysis.new()
      
      assert analysis.id != nil
      assert analysis.type == :code_review
      assert analysis.status == :pending
      assert analysis.input == %{}
      assert analysis.result == nil
      assert analysis.error == nil
      assert analysis.engine == nil
      assert analysis.conversation_id == nil
      assert %DateTime{} = analysis.created_at
      assert analysis.completed_at == nil
    end

    test "creates an analysis with provided attributes" do
      attrs = [
        id: "analysis-123",
        type: :security,
        engine: :security_engine,
        input: %{code: "def hello, do: :world"},
        conversation_id: "conv-456"
      ]
      
      analysis = Analysis.new(attrs)
      
      assert analysis.id == "analysis-123"
      assert analysis.type == :security
      assert analysis.engine == :security_engine
      assert analysis.input == %{code: "def hello, do: :world"}
      assert analysis.conversation_id == "conv-456"
    end
  end

  describe "state transitions" do
    test "start/1 marks analysis as running" do
      analysis = Analysis.new() |> Analysis.start()
      
      assert analysis.status == :running
    end

    test "complete/2 marks analysis as completed with result" do
      result = %{score: 85, issues: []}
      analysis = Analysis.new() |> Analysis.complete(result)
      
      assert analysis.status == :completed
      assert analysis.result == result
      assert %DateTime{} = analysis.completed_at
    end

    test "fail/2 marks analysis as failed with error" do
      error = "Failed to parse code"
      analysis = Analysis.new() |> Analysis.fail(error)
      
      assert analysis.status == :failed
      assert analysis.error == error
      assert %DateTime{} = analysis.completed_at
    end
  end
end