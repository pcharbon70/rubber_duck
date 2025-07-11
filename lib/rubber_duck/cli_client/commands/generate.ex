defmodule RubberDuck.CLIClient.Commands.Generate do
  @moduledoc """
  Generate command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    # Extract values from Optimus.ParseResult struct
    prompt = Map.get(args.args, :prompt)
    language = Map.get(args.options, :language, "elixir")
    output = Map.get(args.options, :output)

    params = %{
      "prompt" => prompt,
      "language" => language,
      "output" => output,
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }

    # Use streaming for generation
    stream_handler = fn
      {:start, _} ->
        unless opts[:quiet], do: IO.write("Generating code... ")

      {:data, chunk} ->
        unless opts[:quiet], do: IO.write(chunk)

      {:end, "completed"} ->
        unless opts[:quiet], do: IO.puts("\n\nGeneration complete!")

      {:end, status} ->
        IO.puts(:stderr, "\nGeneration ended with status: #{status}")
    end

    case Client.send_streaming_command("generate", params, stream_handler) do
      {:ok, stream_id} ->
        # Wait for streaming to complete
        Process.sleep(100)
        {:ok, %{type: :generation_result, stream_id: stream_id}}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
