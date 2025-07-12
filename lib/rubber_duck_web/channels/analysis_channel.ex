defmodule RubberDuckWeb.AnalysisChannel do
  @moduledoc """
  Channel dedicated to streaming analysis results and handling
  analysis-specific real-time operations.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Commands.{Parser, Processor, Context}

  require Logger

  @impl true
  def join("analysis:project:" <> project_id, _params, socket) do
    with {:ok, _project} <- authorize_project_access(project_id, socket.assigns.user_id) do
      socket =
        socket
        |> assign(:project_id, project_id)

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

      {:ok, %{status: "joined", file_id: file_id}, socket}
    else
      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Start a complete project analysis
  @impl true
  def handle_in("start_analysis", params, socket) do
    options = Map.get(params, "options", %{})
    
    with {:ok, context} <- build_context(socket, params),
         {:ok, command} <- Parser.parse(build_analysis_args(socket.assigns.project_id, options), :websocket, context),
         {:ok, result} <- Processor.execute_async(command) do
      
      # Monitor the async execution
      monitor_project_analysis(result.request_id, socket)
      
      {:reply, {:ok, %{analysis_id: result.request_id}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Run specific analysis type
  def handle_in("analyze", %{"type" => type, "code" => _code} = params, socket) do
    file_path = params["file_path"] || "temp_analysis_file"
    
    with {:ok, context} <- build_context(socket, params),
         {:ok, command} <- Parser.parse(["analyze", file_path, "--type", type], :websocket, context),
         {:ok, result} <- Processor.execute_async(command) do
      
      # Monitor the async execution
      monitor_specific_analysis(result.request_id, type, socket)
      
      {:reply, {:ok, %{analysis_id: result.request_id}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Cancel running analysis
  def handle_in("cancel_analysis", %{"analysis_id" => request_id}, socket) do
    case Processor.cancel(request_id) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Get analysis status
  def handle_in("get_status", %{"analysis_id" => request_id}, socket) do
    case Processor.get_status(request_id) do
      {:ok, status} -> {:reply, {:ok, status}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  # Private functions

  defp monitor_project_analysis(request_id, socket) do
    # Send initial started message
    push(socket, "analysis_started", %{
      analysis_id: request_id,
      project_id: socket.assigns.project_id,
      timestamp: DateTime.utc_now()
    })

    # Monitor async analysis execution
    Task.start_link(fn ->
      poll_project_analysis_status(request_id, socket, 0)
    end)
  end

  defp monitor_specific_analysis(request_id, type, socket) do
    # Monitor async analysis execution
    Task.start_link(fn ->
      poll_specific_analysis_status(request_id, type, socket, 0)
    end)
  end

  defp poll_project_analysis_status(request_id, socket, attempts) do
    case Processor.get_status(request_id) do
      {:ok, %{status: :completed, result: result}} ->
        # Stream results by category if it's a structured result
        stream_analysis_results(socket, request_id, result)

        push(socket, "analysis_complete", %{
          analysis_id: request_id,
          summary: build_summary(result),
          timestamp: DateTime.utc_now()
        })

      {:ok, %{status: :failed, result: {:error, reason}}} ->
        push(socket, "analysis_error", %{
          analysis_id: request_id,
          error: to_string(reason),
          timestamp: DateTime.utc_now()
        })

      {:ok, %{status: status, progress: progress}} when status in [:pending, :running] ->
        # Send progress updates
        if rem(attempts, 10) == 0 do  # Every 5 seconds
          push(socket, "analysis_progress", %{
            analysis_id: request_id,
            status: to_string(status),
            progress: progress,
            timestamp: DateTime.utc_now()
          })
        end
        
        # Continue polling
        if attempts < 240 do  # Max 2 minutes
          Process.sleep(500)
          poll_project_analysis_status(request_id, socket, attempts + 1)
        else
          push(socket, "analysis_error", %{
            analysis_id: request_id,
            error: "Analysis timed out",
            timestamp: DateTime.utc_now()
          })
        end

      {:error, reason} ->
        push(socket, "analysis_error", %{
          analysis_id: request_id,
          error: to_string(reason),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp poll_specific_analysis_status(request_id, type, socket, attempts) do
    case Processor.get_status(request_id) do
      {:ok, %{status: :completed, result: result}} ->
        push(socket, "analysis_result", %{
          analysis_id: request_id,
          type: type,
          result: result,
          timestamp: DateTime.utc_now()
        })

      {:ok, %{status: :failed, result: {:error, reason}}} ->
        push(socket, "analysis_error", %{
          analysis_id: request_id,
          error: to_string(reason),
          timestamp: DateTime.utc_now()
        })

      {:ok, %{status: status}} when status in [:pending, :running] ->
        # Continue polling
        if attempts < 120 do  # Max 60 seconds
          Process.sleep(500)
          poll_specific_analysis_status(request_id, type, socket, attempts + 1)
        else
          push(socket, "analysis_error", %{
            analysis_id: request_id,
            error: "Analysis timed out",
            timestamp: DateTime.utc_now()
          })
        end

      {:error, reason} ->
        push(socket, "analysis_error", %{
          analysis_id: request_id,
          error: to_string(reason),
          timestamp: DateTime.utc_now()
        })
    end
  end

  defp stream_analysis_results(socket, analysis_id, results) when is_map(results) do
    # Stream different types of issues if present in the unified result
    if Map.has_key?(results, "semantic_issues") or Map.has_key?(results, :semantic_issues) do
      issues = results["semantic_issues"] || results[:semantic_issues] || []
      push(socket, "analysis_update", %{
        analysis_id: analysis_id,
        type: "semantic",
        issues: issues,
        timestamp: DateTime.utc_now()
      })
    end

    if Map.has_key?(results, "style_issues") or Map.has_key?(results, :style_issues) do
      issues = results["style_issues"] || results[:style_issues] || []
      push(socket, "analysis_update", %{
        analysis_id: analysis_id,
        type: "style",
        issues: issues,
        timestamp: DateTime.utc_now()
      })
    end

    if Map.has_key?(results, "security_issues") or Map.has_key?(results, :security_issues) do
      issues = results["security_issues"] || results[:security_issues] || []
      push(socket, "analysis_update", %{
        analysis_id: analysis_id,
        type: "security",
        issues: issues,
        timestamp: DateTime.utc_now()
      })
    end

    # Stream metadata if available
    metadata = results["metadata"] || results[:metadata]
    if metadata do
      push(socket, "analysis_metadata", %{
        analysis_id: analysis_id,
        metadata: metadata,
        timestamp: DateTime.utc_now()
      })
    end
  end

  defp stream_analysis_results(_socket, _analysis_id, _results) do
    # Handle non-map results gracefully
    :ok
  end

  defp build_summary(results) when is_map(results) do
    semantic_issues = results["semantic_issues"] || results[:semantic_issues] || []
    style_issues = results["style_issues"] || results[:style_issues] || []
    security_issues = results["security_issues"] || results[:security_issues] || []
    metadata = results["metadata"] || results[:metadata] || %{}

    %{
      total_issues: length(semantic_issues) + length(style_issues) + length(security_issues),
      semantic_issues: length(semantic_issues),
      style_issues: length(style_issues),
      security_issues: length(security_issues),
      files_analyzed: metadata["files_analyzed"] || metadata[:files_analyzed] || 0
    }
  end

  defp build_summary(_results) do
    # Fallback for non-map results
    %{
      total_issues: 0,
      semantic_issues: 0,
      style_issues: 0,
      security_issues: 0,
      files_analyzed: 0
    }
  end

  defp authorize_project_access(project_id, _user_id) do
    # TODO: Implement real authorization
    {:ok, %{id: project_id}}
  end

  defp authorize_file_access(file_id, _user_id) do
    # TODO: Implement real authorization
    {:ok, %{id: file_id}}
  end

  defp build_context(socket, params) do
    context_data = %{
      user_id: socket.assigns[:user_id] || "websocket_user_#{socket.id}",
      project_id: socket.assigns[:project_id],
      session_id: "websocket_session_#{socket.id}_#{System.system_time(:millisecond)}",
      permissions: [:read, :write, :execute],
      metadata: %{
        socket_id: socket.id,
        transport: "websocket",
        channel_topic: socket.topic,
        params: params
      }
    }
    
    Context.new(context_data)
  end

  defp build_analysis_args(project_path, options) do
    args = ["analyze", project_path]
    
    # Add type if specified
    args = if options["type"], do: args ++ ["--type", options["type"]], else: args
    
    # Add recursive flag if specified
    args = if options["recursive"], do: args ++ ["--recursive"], else: args
    
    args
  end
end
