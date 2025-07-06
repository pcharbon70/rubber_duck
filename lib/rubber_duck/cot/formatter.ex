defmodule RubberDuck.CoT.Formatter do
  @moduledoc """
  Formats Chain-of-Thought reasoning results for clear presentation.
  
  Provides various output formats including markdown, plain text,
  and structured data formats.
  """
  
  @doc """
  Formats the final result of a reasoning chain.
  """
  def format_result(result, session, format \\ :markdown) do
    case format do
      :markdown -> format_markdown(result, session)
      :plain -> format_plain_text(result, session)
      :json -> format_json(result, session)
      :structured -> format_structured(result, session)
      _ -> format_markdown(result, session)
    end
  end
  
  @doc """
  Formats a single reasoning step.
  """
  def format_step(step, index, format \\ :markdown) do
    case format do
      :markdown -> format_step_markdown(step, index)
      :plain -> format_step_plain(step, index)
      _ -> format_step_markdown(step, index)
    end
  end
  
  @doc """
  Creates a summary of the reasoning process.
  """
  def format_summary(session) do
    """
    ## Reasoning Summary
    
    **Query**: #{session.query}
    **Total Steps**: #{length(session.steps)}
    **Duration**: #{format_duration(session)}
    **Status**: #{session.status}
    """
  end
  
  # Private formatting functions
  
  defp format_markdown(result, session) do
    """
    # Chain-of-Thought Reasoning Result
    
    ## Query
    #{session.query}
    
    ## Reasoning Process
    
    #{format_reasoning_steps_markdown(session.steps)}
    
    ## Final Answer
    
    #{result.final_answer}
    
    ---
    
    #{format_metadata_markdown(result, session)}
    """
  end
  
  defp format_plain_text(result, session) do
    """
    QUERY: #{session.query}
    
    REASONING PROCESS:
    #{format_reasoning_steps_plain(session.steps)}
    
    FINAL ANSWER:
    #{result.final_answer}
    
    #{format_metadata_plain(result, session)}
    """
  end
  
  defp format_json(result, session) do
    Jason.encode!(%{
      query: session.query,
      reasoning_steps: Enum.map(session.steps, &format_step_json/1),
      final_answer: result.final_answer,
      metadata: %{
        total_steps: result.total_steps,
        duration_ms: result.duration_ms,
        session_id: session.id,
        status: session.status
      }
    }, pretty: true)
  end
  
  defp format_structured(result, session) do
    %{
      query: session.query,
      reasoning_path: build_reasoning_path(session.steps),
      final_answer: result.final_answer,
      confidence: calculate_confidence(session),
      key_insights: extract_key_insights(session.steps),
      metadata: build_metadata(result, session)
    }
  end
  
  defp format_reasoning_steps_markdown(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} ->
      format_step_markdown(step, idx)
    end)
    |> Enum.join("\n\n")
  end
  
  defp format_step_markdown(step, index) do
    """
    ### Step #{index}: #{format_step_name(step.name)}
    
    #{step.result}
    """
  end
  
  defp format_reasoning_steps_plain(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.map(fn {step, idx} ->
      format_step_plain(step, idx)
    end)
    |> Enum.join("\n\n")
  end
  
  defp format_step_plain(step, index) do
    """
    Step #{index} - #{format_step_name(step.name)}:
    #{step.result}
    """
  end
  
  defp format_step_json(step) do
    %{
      name: step.name,
      result: step.result,
      executed_at: step.executed_at
    }
  end
  
  defp format_step_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  
  defp format_metadata_markdown(result, session) do
    """
    ### Metadata
    
    - **Session ID**: `#{session.id}`
    - **Reasoning Steps**: #{result.total_steps}
    - **Total Duration**: #{format_duration_ms(result.duration_ms)}
    - **Started**: #{format_timestamp(session.started_at)}
    - **Completed**: #{format_timestamp(Map.get(session, :completed_at))}
    """
  end
  
  defp format_metadata_plain(result, session) do
    """
    ---
    Session ID: #{session.id}
    Steps: #{result.total_steps}
    Duration: #{format_duration_ms(result.duration_ms)}
    Started: #{format_timestamp(session.started_at)}
    """
  end
  
  defp build_reasoning_path(steps) do
    steps
    |> Enum.map(& &1.name)
    |> Enum.map(&Atom.to_string/1)
    |> Enum.join(" → ")
  end
  
  defp calculate_confidence(session) do
    # Simple confidence calculation based on completion
    base_confidence = if session.status == :completed, do: 0.8, else: 0.4
    
    # Adjust based on number of steps
    step_factor = min(1.0, length(session.steps) / 5)
    
    Float.round(base_confidence * step_factor, 2)
  end
  
  defp extract_key_insights(steps) do
    # Extract key phrases from each step
    steps
    |> Enum.map(fn step ->
      extract_key_phrase(step.result)
    end)
    |> Enum.filter(& &1)
  end
  
  defp extract_key_phrase(text) do
    # Simple extraction - find sentences with key indicators
    sentences = String.split(text, ~r/[.!?]/)
    
    key_sentence = Enum.find(sentences, fn sentence ->
      String.contains?(String.downcase(sentence), 
        ["therefore", "thus", "because", "the key", "important", "conclusion"])
    end)
    
    if key_sentence do
      String.trim(key_sentence)
    else
      nil
    end
  end
  
  defp build_metadata(result, session) do
    %{
      session_id: session.id,
      chain_module: session.chain_module,
      total_steps: result.total_steps,
      duration_ms: result.duration_ms,
      started_at: session.started_at,
      completed_at: Map.get(session, :completed_at),
      cached: Map.get(session, :cached, false)
    }
  end
  
  defp format_duration(session) do
    if session.started_at and Map.get(session, :completed_at) do
      duration_ms = DateTime.diff(session.completed_at, session.started_at, :millisecond)
      format_duration_ms(duration_ms)
    else
      "N/A"
    end
  end
  
  defp format_duration_ms(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration_ms(ms) when ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end
  defp format_duration_ms(ms) do
    minutes = div(ms, 60_000)
    seconds = rem(ms, 60_000) |> div(1000)
    "#{minutes}m #{seconds}s"
  end
  
  defp format_timestamp(nil), do: "N/A"
  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end
end