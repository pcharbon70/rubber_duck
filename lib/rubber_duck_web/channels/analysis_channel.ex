defmodule RubberDuckWeb.AnalysisChannel do
  @moduledoc """
  Channel dedicated to streaming analysis results and handling
  analysis-specific real-time operations.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Workflows.CompleteAnalysis
  alias RubberDuck.Analysis.{AST, Semantic, Style, Security}

  require Logger

  @impl true
  def join("analysis:project:" <> project_id, _params, socket) do
    with {:ok, _project} <- authorize_project_access(project_id, socket.assigns.user_id) do
      socket =
        socket
        |> assign(:project_id, project_id)
        |> assign(:active_analyses, %{})

      {:ok, %{status: "joined", project_id: project_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def join("analysis:file:" <> file_id, _params, socket) do
    with {:ok, _file} <- authorize_file_access(file_id, socket.assigns.user_id) do
      socket =
        socket
        |> assign(:file_id, file_id)
        |> assign(:active_analyses, %{})

      {:ok, %{status: "joined", file_id: file_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Start a complete project analysis
  @impl true
  def handle_in("start_analysis", params, socket) do
    analysis_id = generate_analysis_id()
    options = Map.get(params, "options", %{})

    # Start async analysis
    Task.start_link(fn ->
      run_complete_analysis(socket, analysis_id, socket.assigns.project_id, options)
    end)

    # Track active analysis
    active =
      Map.put(socket.assigns.active_analyses, analysis_id, %{
        started_at: DateTime.utc_now(),
        status: :running
      })

    {:reply, {:ok, %{analysis_id: analysis_id}}, assign(socket, :active_analyses, active)}
  end

  # Run specific analysis type
  def handle_in("analyze", %{"type" => type, "code" => code} = params, socket) do
    analysis_id = generate_analysis_id()

    Task.start_link(fn ->
      run_specific_analysis(socket, analysis_id, type, code, params)
    end)

    {:reply, {:ok, %{analysis_id: analysis_id}}, socket}
  end

  # Cancel running analysis
  def handle_in("cancel_analysis", %{"analysis_id" => analysis_id}, socket) do
    # TODO: Implement analysis cancellation
    active = Map.delete(socket.assigns.active_analyses, analysis_id)
    {:reply, :ok, assign(socket, :active_analyses, active)}
  end

  # Get analysis status
  def handle_in("get_status", %{"analysis_id" => analysis_id}, socket) do
    status = Map.get(socket.assigns.active_analyses, analysis_id, %{status: :not_found})
    {:reply, {:ok, status}, socket}
  end

  # Private functions

  defp run_complete_analysis(socket, analysis_id, project_id, options) do
    try do
      # Start analysis and stream progress
      push(socket, "analysis_started", %{
        analysis_id: analysis_id,
        project_id: project_id,
        timestamp: DateTime.utc_now()
      })

      # Run the complete analysis workflow
      result = CompleteAnalysis.run(project_id, options)

      case result do
        {:ok, analysis_result} ->
          # Stream results by category
          stream_analysis_results(socket, analysis_id, analysis_result)

          push(socket, "analysis_complete", %{
            analysis_id: analysis_id,
            summary: build_summary(analysis_result),
            timestamp: DateTime.utc_now()
          })

        {:error, error} ->
          push(socket, "analysis_error", %{
            analysis_id: analysis_id,
            error: to_string(error),
            timestamp: DateTime.utc_now()
          })
      end
    rescue
      error ->
        Logger.error("Analysis error: #{inspect(error)}")

        push(socket, "analysis_error", %{
          analysis_id: analysis_id,
          error: Exception.message(error),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp run_specific_analysis(socket, analysis_id, type, code, params) do
    try do
      result =
        case type do
          "ast" -> AST.parse(code, params["language"] || "elixir")
          "semantic" -> Semantic.analyze(code, params)
          "style" -> Style.analyze(code, params)
          "security" -> Security.analyze(code, params)
          _ -> {:error, "Unknown analysis type: #{type}"}
        end

      case result do
        {:ok, analysis_result} ->
          push(socket, "analysis_result", %{
            analysis_id: analysis_id,
            type: type,
            result: analysis_result,
            timestamp: DateTime.utc_now()
          })

        {:error, error} ->
          push(socket, "analysis_error", %{
            analysis_id: analysis_id,
            error: to_string(error),
            timestamp: DateTime.utc_now()
          })
      end
    rescue
      error ->
        push(socket, "analysis_error", %{
          analysis_id: analysis_id,
          error: Exception.message(error),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp stream_analysis_results(socket, analysis_id, results) do
    # Stream semantic issues
    if results[:semantic_issues] do
      push(socket, "analysis_update", %{
        analysis_id: analysis_id,
        type: "semantic",
        issues: results.semantic_issues,
        timestamp: DateTime.utc_now()
      })
    end

    # Stream style issues
    if results[:style_issues] do
      push(socket, "analysis_update", %{
        analysis_id: analysis_id,
        type: "style",
        issues: results.style_issues,
        timestamp: DateTime.utc_now()
      })
    end

    # Stream security issues
    if results[:security_issues] do
      push(socket, "analysis_update", %{
        analysis_id: analysis_id,
        type: "security",
        issues: results.security_issues,
        timestamp: DateTime.utc_now()
      })
    end

    # Stream any additional results
    if results[:metadata] do
      push(socket, "analysis_metadata", %{
        analysis_id: analysis_id,
        metadata: results.metadata,
        timestamp: DateTime.utc_now()
      })
    end
  end

  defp build_summary(results) do
    %{
      total_issues: count_all_issues(results),
      semantic_issues: length(results[:semantic_issues] || []),
      style_issues: length(results[:style_issues] || []),
      security_issues: length(results[:security_issues] || []),
      files_analyzed: results[:metadata][:files_analyzed] || 0
    }
  end

  defp count_all_issues(results) do
    [:semantic_issues, :style_issues, :security_issues]
    |> Enum.map(fn key -> length(results[key] || []) end)
    |> Enum.sum()
  end

  defp authorize_project_access(project_id, _user_id) do
    # TODO: Implement real authorization
    {:ok, %{id: project_id}}
  end

  defp authorize_file_access(file_id, _user_id) do
    # TODO: Implement real authorization
    {:ok, %{id: file_id}}
  end

  defp generate_analysis_id do
    "analysis_#{:crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)}"
  end
end
