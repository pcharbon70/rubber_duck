defmodule RubberDuck.LLM.StreamingTest do
  use ExUnit.Case, async: false

  alias RubberDuck.LLM.{Service, StreamParser}

  describe "streaming responses" do
    setup do
      # Service is already started by application
      :ok
    end

    test "can stream completion from mock provider" do
      opts = [
        model: "mock-fast",
        messages: [%{"role" => "user", "content" => "Stream this response"}],
        stream: true
      ]

      test_pid = self()

      {:ok, stream_ref} =
        Service.completion_stream(opts, fn chunk ->
          # Callback receives each chunk
          assert Map.has_key?(chunk, :content)
          send(test_pid, {:chunk, chunk})
        end)

      # Collect some chunks
      chunks = collect_chunks(5, 1000)
      assert length(chunks) > 0

      # Verify stream completes
      assert_receive {:stream_complete, ^stream_ref}, 2000
    end
  end

  describe "SSE parsing" do
    test "parses OpenAI SSE format" do
      sse_data = """
      data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

      data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1234567890,"model":"gpt-4","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

      data: [DONE]
      """

      chunks = StreamParser.parse_sse(sse_data, :openai)

      assert length(chunks) == 2
      assert hd(chunks).content == "Hello"
      assert hd(tl(chunks)).content == " world"
    end

    test "parses Anthropic SSE format" do
      sse_data = """
      event: message_start
      data: {"type":"message_start","message":{"id":"msg_123","type":"message","role":"assistant","content":[],"model":"claude-3-sonnet"}}

      event: content_block_delta
      data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

      event: message_stop
      data: {"type":"message_stop"}
      """

      chunks = StreamParser.parse_sse(sse_data, :anthropic)

      assert length(chunks) >= 1
      assert Enum.any?(chunks, &(&1.content == "Hello"))
    end
  end

  defp collect_chunks(max_count, timeout) do
    collect_chunks([], max_count, timeout)
  end

  defp collect_chunks(chunks, 0, _timeout), do: Enum.reverse(chunks)

  defp collect_chunks(chunks, remaining, timeout) do
    receive do
      {:chunk, chunk} ->
        collect_chunks([chunk | chunks], remaining - 1, timeout)
    after
      timeout ->
        Enum.reverse(chunks)
    end
  end
end
