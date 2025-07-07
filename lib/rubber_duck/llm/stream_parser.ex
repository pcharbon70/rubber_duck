defmodule RubberDuck.LLM.StreamParser do
  @moduledoc """
  Parses Server-Sent Events (SSE) streams from LLM providers.

  Handles both OpenAI and Anthropic streaming formats.
  """

  @type chunk :: %{
          content: String.t() | nil,
          role: String.t() | nil,
          finish_reason: String.t() | nil,
          usage: map() | nil,
          metadata: map()
        }

  @doc """
  Parses SSE data from a provider into structured chunks.

  ## Examples

      iex> StreamParser.parse_sse("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}", :openai)
      [%{content: "Hello", role: nil, finish_reason: nil, usage: nil, metadata: %{}}]
  """
  @spec parse_sse(String.t(), atom()) :: [chunk()]
  def parse_sse(data, provider) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> parse_lines(provider, [])
    |> Enum.reverse()
  end

  defp parse_lines([], _provider, acc), do: acc

  defp parse_lines([line | rest], provider, acc) do
    case parse_line(line, provider) do
      {:ok, chunk} ->
        parse_lines(rest, provider, [chunk | acc])

      {:skip, _} ->
        parse_lines(rest, provider, acc)

      {:error, _} ->
        parse_lines(rest, provider, acc)
    end
  end

  defp parse_line("data: [DONE]", :openai), do: {:skip, :done}

  defp parse_line("data: " <> json_data, :openai) do
    case Jason.decode(json_data) do
      {:ok, data} ->
        parse_openai_chunk(data)

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp parse_line("event: " <> event_type, :anthropic) do
    # Store event type for next data line
    {:skip, {:event, event_type}}
  end

  defp parse_line("data: " <> json_data, :anthropic) do
    case Jason.decode(json_data) do
      {:ok, data} ->
        parse_anthropic_chunk(data)

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  defp parse_line(_, _), do: {:skip, :unknown}

  defp parse_openai_chunk(%{"choices" => choices} = data) when is_list(choices) do
    # Extract content from the first choice
    chunk =
      case List.first(choices) do
        %{"delta" => delta} = choice ->
          %{
            content: delta["content"],
            role: delta["role"],
            finish_reason: choice["finish_reason"],
            usage: data["usage"],
            metadata: %{
              id: data["id"],
              model: data["model"],
              system_fingerprint: data["system_fingerprint"]
            }
          }

        _ ->
          %{
            content: nil,
            role: nil,
            finish_reason: nil,
            usage: nil,
            metadata: %{}
          }
      end

    {:ok, chunk}
  end

  defp parse_openai_chunk(_), do: {:error, :invalid_format}

  defp parse_anthropic_chunk(%{"type" => "message_start"} = data) do
    {:ok,
     %{
       content: nil,
       role: get_in(data, ["message", "role"]),
       finish_reason: nil,
       usage: nil,
       metadata: %{
         id: get_in(data, ["message", "id"]),
         model: get_in(data, ["message", "model"]),
         type: "message_start"
       }
     }}
  end

  defp parse_anthropic_chunk(%{"type" => "content_block_delta", "delta" => delta}) do
    {:ok,
     %{
       content: delta["text"],
       role: nil,
       finish_reason: nil,
       usage: nil,
       metadata: %{
         type: "content_block_delta",
         index: delta["index"]
       }
     }}
  end

  defp parse_anthropic_chunk(%{"type" => "message_delta"} = data) do
    {:ok,
     %{
       content: nil,
       role: nil,
       finish_reason: data["delta"]["stop_reason"],
       usage: data["usage"],
       metadata: %{
         type: "message_delta",
         stop_sequence: data["delta"]["stop_sequence"]
       }
     }}
  end

  defp parse_anthropic_chunk(%{"type" => "message_stop"}) do
    {:ok,
     %{
       content: nil,
       role: nil,
       finish_reason: "stop",
       usage: nil,
       metadata: %{type: "message_stop"}
     }}
  end

  defp parse_anthropic_chunk(_), do: {:error, :invalid_format}

  @doc """
  Processes a stream of SSE data, calling the callback for each chunk.

  This function is designed to work with streaming HTTP responses.
  """
  @spec process_stream(Enumerable.t(), atom(), function()) :: :ok | {:error, term()}
  def process_stream(stream, provider, callback) when is_function(callback, 1) do
    buffer = ""

    stream
    |> Stream.transform(buffer, fn chunk, acc ->
      data = acc <> chunk
      lines = String.split(data, "\n")

      case List.pop_at(lines, -1) do
        {incomplete, complete_lines} ->
          chunks =
            complete_lines
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))
            |> parse_lines(provider, [])

          {chunks, incomplete || ""}
      end
    end)
    |> Stream.each(callback)
    |> Stream.run()

    :ok
  rescue
    e -> {:error, e}
  end

  @doc """
  Accumulates streaming chunks into a complete response.
  """
  @spec accumulate_chunks([chunk()]) :: %{
          content: String.t(),
          role: String.t() | nil,
          finish_reason: String.t() | nil,
          usage: map() | nil
        }
  def accumulate_chunks(chunks) do
    chunks
    |> Enum.reduce(
      %{content: [], role: nil, finish_reason: nil, usage: nil},
      fn chunk, acc ->
        %{
          content: [chunk.content | acc.content],
          role: acc.role || chunk.role,
          finish_reason: chunk.finish_reason || acc.finish_reason,
          usage: chunk.usage || acc.usage
        }
      end
    )
    |> Map.update!(:content, fn parts ->
      parts
      |> Enum.reverse()
      |> Enum.reject(&is_nil/1)
      |> Enum.join("")
    end)
  end
end
