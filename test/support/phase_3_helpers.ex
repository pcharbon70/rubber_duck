defmodule RubberDuck.Phase3Helpers do
  @moduledoc """
  Test helpers for Phase 3 integration tests.
  
  Provides utilities for setting up test data, mocking services,
  and common assertions for LLM and memory system tests.
  """
  
  # Import ExUnit assertions
  import ExUnit.Assertions
  
  alias RubberDuck.Memory.Manager, as: MemoryManager
  alias RubberDuck.LLM.Service, as: LLMService
  
  @doc """
  Creates test memories across different levels for a user.
  """
  def setup_test_memories(user_id, opts \\ []) do
    count = Keyword.get(opts, :count, 5)
    topics = Keyword.get(opts, :topics, ["elixir", "genserver", "supervisor"])
    
    for i <- 1..count do
      topic = Enum.random(topics)
      
      MemoryManager.store_interaction(%{
        user_id: user_id,
        session_id: "test_session",
        type: Enum.random([:query, :generation, :completion]),
        input: "Test input about #{topic} - #{i}",
        output: "Test output for #{topic} - #{i}",
        metadata: %{
          topic: topic,
          quality_score: :rand.uniform(),
          timestamp: DateTime.utc_now(),
          test_data: true
        }
      })
    end
    
    :ok
  end
  
  @doc """
  Creates a mock LLM request for testing.
  """
  def mock_llm_request(content, opts \\ []) do
    %{
      model: Keyword.get(opts, :model, "mock-fast"),
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: content}
      ],
      provider: Keyword.get(opts, :provider, :mock),
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens, 1000)
    }
  end
  
  @doc """
  Creates a mock generation input for testing.
  """
  def mock_generation_input(prompt, user_id, opts \\ []) do
    %{
      prompt: prompt,
      language: Keyword.get(opts, :language, :elixir),
      user_id: user_id,
      context: Keyword.get(opts, :context, %{}),
      options: Keyword.get(opts, :options, [])
    }
  end
  
  @doc """
  Waits for async processes to complete.
  """
  def wait_for_async(timeout \\ 1000) do
    Process.sleep(timeout)
  end
  
  @doc """
  Asserts that a result contains expected code patterns.
  """
  def assert_code_quality(code, patterns) do
    Enum.each(patterns, fn pattern ->
      assert code =~ pattern,
        "Expected code to contain '#{pattern}' but it didn't.\nCode:\n#{code}"
    end)
  end
  
  @doc """
  Asserts that memory was used in generation.
  """
  def assert_memory_used(result) do
    assert result.metadata[:memory_used] == true ||
           Enum.any?(result.metadata[:sources] || [], &(&1.type == :memory)),
      "Expected memory to be used but it wasn't"
  end
  
  @doc """
  Asserts that enhancement techniques were applied.
  """
  def assert_techniques_applied(result, expected_techniques) do
    applied = result.metadata[:techniques_used] || result.techniques_applied || []
    
    Enum.each(expected_techniques, fn tech ->
      assert tech in applied,
        "Expected technique #{tech} to be applied but it wasn't. Applied: #{inspect(applied)}"
    end)
  end
  
  @doc """
  Creates test documents for RAG indexing.
  """
  def create_test_documents(count \\ 5) do
    topics = [
      {"GenServer", "A behaviour module for implementing stateful server processes"},
      {"Supervisor", "A process that supervises other processes for fault tolerance"},
      {"Application", "A component that can be started and stopped as a unit"},
      {"Agent", "A simple abstraction around state"},
      {"Task", "Conveniences for spawning and awaiting tasks"}
    ]
    
    for i <- 1..count do
      {topic, description} = Enum.at(topics, rem(i - 1, length(topics)))
      
      %{
        content: """
        #{topic} Documentation
        
        #{description}
        
        Example usage:
        ```elixir
        defmodule My#{topic} do
          # Implementation details for #{topic}
        end
        ```
        
        This is test document #{i} about #{topic}.
        """,
        metadata: %{
          type: :documentation,
          topic: String.downcase(topic),
          source: "test_doc_#{i}",
          indexed_at: DateTime.utc_now()
        }
      }
    end
  end
  
  @doc """
  Measures execution time of a function.
  """
  def measure_time(fun) do
    start_time = System.monotonic_time(:millisecond)
    result = fun.()
    end_time = System.monotonic_time(:millisecond)
    
    {result, end_time - start_time}
  end
  
  @doc """
  Simulates application restart for testing.
  """
  def simulate_restart do
    # Note: This is a simplified version. Real restart testing
    # would require more sophisticated approaches.
    
    # Stop non-critical processes
    # The actual application remains running
    
    # Clear ETS tables to simulate memory loss
    :ets.delete_all_objects(:short_term_memory)
    :ets.delete_all_objects(:mid_term_memory)
    
    # Re-initialize
    Process.sleep(100)
    
    :ok
  end
  
  @doc """
  Creates a test reasoning chain module.
  """
  defmacro create_test_chain(name, steps) do
    quote do
      defmodule unquote(name) do
        use RubberDuck.CoT.Chain
        
        reasoning_chain do
          name unquote(name)
          
          unquote_splicing(steps)
        end
      end
    end
  end
  
  @doc """
  Asserts cost tracking is accurate.
  """
  def assert_cost_tracking(response) do
    usage = response.usage
    
    # Token counts should be positive
    assert usage.prompt_tokens > 0
    assert usage.completion_tokens > 0
    assert usage.total_tokens == usage.prompt_tokens + usage.completion_tokens
    
    # Costs should be calculated
    assert usage.prompt_cost > 0
    assert usage.completion_cost > 0
    
    # Total cost should be sum of parts (with small float tolerance)
    expected_total = usage.prompt_cost + usage.completion_cost
    assert_in_delta(usage.total_cost, expected_total, 0.0001)
  end
  
  @doc """
  Creates concurrent test tasks.
  """
  def create_concurrent_tasks(count, task_fn) do
    for i <- 1..count do
      Task.async(fn -> task_fn.(i) end)
    end
  end
  
  @doc """
  Asserts enhancement improved quality.
  """
  def assert_quality_improved(result) do
    metrics = result.metrics || %{}
    
    assert metrics["quality_improvement"] > 0,
      "Expected quality improvement but got #{metrics["quality_improvement"]}"
    
    # Enhanced should be different from original
    assert result.enhanced != result.original,
      "Enhanced content should differ from original"
  end
end