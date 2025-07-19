defmodule RubberDuckWeb.AnalysisChannel do
  @moduledoc """
  Channel dedicated to streaming analysis results and handling
  analysis-specific real-time operations.

  This channel now works directly with the analysis engine,
  bypassing the removed commands system.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Engine.Manager, as: EngineManager
  alias RubberDuck.Workspace

  require Logger

  @impl true
  def join("analysis:project:" <> project_id, _params, socket) do
    with {:ok, project} <- authorize_project_access(project_id, socket.assigns.user_id) do
      socket =
        socket
        |> assign(:project_id, project_id)
        |> assign(:project, project)

      {:ok, %{status: "joined", project_id: project_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def join("analysis:file:" <> file_id, _params, socket) do
    with {:ok, file} <- authorize_file_access(file_id, socket.assigns.user_id) do
      socket =
        socket
        |> assign(:file_id, file_id)
        |> assign(:file, file)

      {:ok, %{status: "joined", file_id: file_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Start a complete project analysis
  @impl true
  def handle_in("start_analysis", params, socket) do
    project_id = socket.assigns[:project_id]
    options = Map.get(params, "options", %{})

    # Create a unique analysis ID
    analysis_id = generate_analysis_id()

    # Start async analysis
    Task.start_link(fn ->
      analyze_project(project_id, analysis_id, options, socket)
    end)

    # Send initial started message
    push(socket, "analysis_started", %{
      analysis_id: analysis_id,
      project_id: project_id,
      timestamp: DateTime.utc_now()
    })

    {:reply, {:ok, %{analysis_id: analysis_id}}, socket}
  end

  # Run specific analysis type on code
  @impl true
  def handle_in("analyze", %{"type" => type, "code" => code} = params, socket) do
    file_path = params["file_path"] || "temp_analysis_file"
    language = params["language"] || detect_language(file_path)

    # Create a unique analysis ID
    analysis_id = generate_analysis_id()

    # Build input for the analysis engine
    input = %{
      file_path: file_path,
      content: code,
      language: String.to_atom(language),
      options: %{
        analysis_type: String.to_atom(type),
        project_context: params["context"] || %{}
      }
    }

    # Start async analysis
    Task.start_link(fn ->
      case EngineManager.execute(:analysis, input, 30_000) do
        {:ok, result} ->
          push(socket, "analysis_result", %{
            analysis_id: analysis_id,
            type: type,
            result: format_analysis_result(result)
          })

          push(socket, "analysis_complete", %{
            analysis_id: analysis_id,
            status: "success",
            timestamp: DateTime.utc_now()
          })

        {:error, reason} ->
          push(socket, "analysis_error", %{
            analysis_id: analysis_id,
            error: to_string(reason),
            timestamp: DateTime.utc_now()
          })
      end
    end)

    {:reply, {:ok, %{analysis_id: analysis_id}}, socket}
  end

  # Cancel running analysis (placeholder - needs implementation)
  @impl true
  def handle_in("cancel_analysis", %{"analysis_id" => _analysis_id}, socket) do
    # TODO: Implement analysis cancellation
    {:reply, {:error, %{reason: "Cancellation not yet implemented"}}, socket}
  end

  # Get analysis status (placeholder - needs implementation)
  @impl true
  def handle_in("get_status", %{"analysis_id" => _analysis_id}, socket) do
    # TODO: Implement status tracking
    {:reply, {:error, %{reason: "Status tracking not yet implemented"}}, socket}
  end

  # Private functions

  defp authorize_project_access(project_id, _user_id) do
    # TODO: Implement proper authorization
    case Workspace.get_project(project_id) do
      {:ok, project} -> {:ok, project}
      _ -> {:error, :unauthorized}
    end
  end

  defp authorize_file_access(file_id, _user_id) do
    # TODO: Implement proper authorization
    case Workspace.get_code_file(file_id) do
      {:ok, file} -> {:ok, file}
      _ -> {:error, :unauthorized}
    end
  end

  defp generate_analysis_id do
    "analysis_#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end

  defp detect_language(file_path) do
    case Path.extname(file_path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".js" -> "javascript"
      ".jsx" -> "javascript"
      ".ts" -> "typescript"
      ".tsx" -> "typescript"
      ".py" -> "python"
      ".rb" -> "ruby"
      ".go" -> "go"
      ".rs" -> "rust"
      ".java" -> "java"
      _ -> "unknown"
    end
  end

  defp analyze_project(project_id, analysis_id, options, socket) do
    case Workspace.list_code_files(project_id) do
      {:ok, files} ->
        total_files = length(files)

        # Analyze each file
        files
        |> Enum.with_index(1)
        |> Enum.each(fn {file, index} ->
          analyze_file(file, analysis_id, options, socket)

          # Send progress update
          push(socket, "analysis_progress", %{
            analysis_id: analysis_id,
            current: index,
            total: total_files,
            file: file.path
          })
        end)

        # Send completion
        push(socket, "analysis_complete", %{
          analysis_id: analysis_id,
          project_id: project_id,
          total_files: total_files,
          timestamp: DateTime.utc_now()
        })

      {:error, reason} ->
        push(socket, "analysis_error", %{
          analysis_id: analysis_id,
          error: to_string(reason)
        })
    end
  end

  defp analyze_file(file, analysis_id, options, socket) do
    input = %{
      file_path: file.path,
      options: options
    }

    case EngineManager.execute(:analysis, input, 30_000) do
      {:ok, result} ->
        push(socket, "file_analyzed", %{
          analysis_id: analysis_id,
          file: file.path,
          result: format_analysis_result(result)
        })

      {:error, reason} ->
        Logger.warning("Failed to analyze #{file.path}: #{inspect(reason)}")
    end
  end

  defp format_analysis_result(result) do
    %{
      file: result.file,
      language: result.language,
      issues: format_issues(result.issues),
      metrics: result.metrics || %{},
      summary: result.summary || generate_summary(result.issues),
      patterns: Map.get(result, :patterns, []),
      suggestions: Map.get(result, :suggestions, [])
    }
  end

  defp format_issues(issues) when is_list(issues) do
    Enum.map(issues, fn issue ->
      %{
        type: issue.type || :info,
        category: issue.category || :general,
        message: issue.message || "Unknown issue",
        line: issue.line || 0,
        column: issue.column || 0,
        severity: issue.severity || :low
      }
    end)
  end

  defp format_issues(_), do: []

  defp generate_summary(issues) when is_list(issues) do
    issue_count = length(issues)
    by_type = Enum.group_by(issues, & &1.type)

    %{
      total_issues: issue_count,
      errors: length(Map.get(by_type, :error, [])),
      warnings: length(Map.get(by_type, :warning, [])),
      info: length(Map.get(by_type, :info, []))
    }
  end

  defp generate_summary(_), do: %{total_issues: 0, errors: 0, warnings: 0, info: 0}
end
