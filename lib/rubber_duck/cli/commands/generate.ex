defmodule RubberDuck.CLI.Commands.Generate do
  @moduledoc """
  CLI command for generating code from natural language descriptions.
  """

  alias RubberDuck.Engine.Manager

  @doc """
  Runs the generate command with the given arguments and configuration.
  """
  def run(args, config) do
    prompt = args[:prompt]
    output_file = args[:output]
    language = args[:language] || "elixir"
    context_path = args[:context]
    interactive = args[:interactive] || false

    # Build context if provided
    context = build_context(context_path)

    # Generate code
    case generate_code(prompt, language, context, config) do
      {:ok, code} ->
        handle_output(code, output_file, language, interactive)

      {:error, reason} ->
        {:error, "Code generation failed: #{reason}"}
    end
  end

  defp build_context(nil), do: %{}

  defp build_context(path) do
    # TODO: Implement context building from file/directory
    %{context_path: path}
  end

  defp generate_code(prompt, language, context, _config) do
    input = %{
      prompt: prompt,
      language: language,
      context: context
    }

    case Manager.execute(:generation, input) do
      {:ok, %{code: code}} -> {:ok, code}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_output(code, nil, language, _interactive) do
    # Output to stdout
    {:ok,
     %{
       type: :generation,
       code: code,
       language: language
     }}
  end

  defp handle_output(code, output_file, language, _interactive) do
    # Write to file
    case File.write(output_file, code) do
      :ok ->
        {:ok,
         %{
           type: :generation,
           code: code,
           language: language,
           output_file: output_file,
           message: "Code written to #{output_file}"
         }}

      {:error, reason} ->
        {:error, "Failed to write output file: #{reason}"}
    end
  end
end
