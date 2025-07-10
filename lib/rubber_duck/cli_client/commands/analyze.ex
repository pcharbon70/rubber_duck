defmodule RubberDuck.CLIClient.Commands.Analyze do
  @moduledoc """
  Analyze command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    # Extract values from Optimus.ParseResult struct
    path = Map.get(args.args, :path)
    analysis_type = Map.get(args.options, :type, :all)
    recursive = Map.get(args.flags, :recursive, false)

    params = %{
      "path" => path,
      "type" => analysis_type,
      "recursive" => recursive,
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }

    case Client.send_command("analyze", params) do
      {:ok, result} ->
        {:ok, format_analysis_result(result)}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp format_analysis_result(%{"results" => results, "summary" => summary}) do
    """
    Analysis Results:

    #{format_results(results)}

    Summary:
    #{format_summary(summary)}
    """
  end

  defp format_analysis_result(result) do
    # Fallback for unexpected result format
    inspect(result)
  end

  defp format_results(results) when is_list(results) do
    results
    |> Enum.map(&format_single_result/1)
    |> Enum.join("\n\n")
  end

  defp format_results(_), do: "No results"

  defp format_single_result(%{"file" => file, "findings" => findings}) do
    """
    File: #{file}
    Findings:
    #{format_findings(findings)}
    """
  end

  defp format_single_result(result), do: inspect(result)

  defp format_findings(findings) when is_list(findings) do
    findings
    |> Enum.map(&format_finding/1)
    |> Enum.join("\n")
  end

  defp format_findings(_), do: "  None"

  defp format_finding(%{"type" => type, "line" => line, "message" => message}) do
    "  - Line #{line} [#{type}]: #{message}"
  end

  defp format_finding(finding), do: "  - #{inspect(finding)}"

  defp format_summary(%{"total_files" => total, "issues_found" => issues}) do
    "Analyzed #{total} files, found #{issues} issues"
  end

  defp format_summary(summary), do: inspect(summary)
end
