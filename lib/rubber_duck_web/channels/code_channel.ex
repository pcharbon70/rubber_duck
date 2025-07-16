defmodule RubberDuckWeb.CodeChannel do
  @moduledoc """
  Channel for real-time code-related operations including streaming
  completions, generation, refactoring, and collaborative features.
  
  This channel now works directly with the various code engines,
  bypassing the removed commands system.
  """

  use RubberDuckWeb, :channel

  alias RubberDuck.Engine.Manager, as: EngineManager
  alias RubberDuck.Workspace

  require Logger

  @impl true
  def join("code:project:" <> project_id, params, socket) do
    with {:ok, project} <- authorize_project_access(project_id, socket.assigns.user_id),
         :ok <- validate_join_params(params) do
      socket =
        socket
        |> assign(:project_id, project_id)
        |> assign(:project, project)
        |> assign(:cursor_position, params["cursor_position"] || %{})

      # Track user presence
      send(self(), :after_join)

      {:ok, %{status: "joined", project_id: project_id}, socket}
    else
      {:error, :unauthorized} ->
        {:error, %{reason: "Unauthorized access to project"}}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  @impl true
  def join("code:file:" <> file_id, params, socket) do
    with {:ok, file} <- authorize_file_access(file_id, socket.assigns.user_id),
         :ok <- validate_join_params(params) do
      socket =
        socket
        |> assign(:file_id, file_id)
        |> assign(:file, file)

      {:ok, %{status: "joined", file_id: file_id}, socket}
    else
      {:error, :unauthorized} ->
        {:error, %{reason: "Unauthorized access to file"}}

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  # Handle presence tracking after join
  @impl true
  def handle_info(:after_join, socket) do
    # Track presence for collaborative features
    if project_id = socket.assigns[:project_id] do
      {:ok, _} =
        RubberDuckWeb.Presence.track(socket, socket.assigns.user_id, %{
          online_at: inspect(System.system_time(:second)),
          project_id: project_id
        })

      push(socket, "presence_state", RubberDuckWeb.Presence.list(socket))
    end

    {:noreply, socket}
  end

  # Handle code generation
  @impl true
  def handle_in("generate", params, socket) do
    prompt = params["prompt"] || ""
    language = params["language"] || "elixir"
    context = build_generation_context(params, socket)
    
    # Build input for generation engine
    input = %{
      prompt: prompt,
      language: String.to_atom(language),
      context: context,
      partial_code: params["partial_code"],
      style: params["style"] && String.to_atom(params["style"])
    }
    
    # Create a unique request ID
    request_id = generate_request_id()
    
    # Start async generation
    Task.start_link(fn ->
      case EngineManager.execute(:generation, input, 30_000) do
        {:ok, result} ->
          push(socket, "generation_complete", %{
            request_id: request_id,
            code: result.code,
            language: result.language,
            imports: result.imports,
            explanation: result.explanation,
            alternatives: Map.get(result, :alternatives, [])
          })
          
        {:error, reason} ->
          push(socket, "generation_error", %{
            request_id: request_id,
            error: format_error(reason)
          })
      end
    end)
    
    {:reply, {:ok, %{request_id: request_id}}, socket}
  end

  # Handle code completion
  @impl true
  def handle_in("complete", params, socket) do
    prefix = params["prefix"] || ""
    suffix = params["suffix"] || ""
    cursor_position = parse_cursor_position(params["cursor_position"])
    file_path = params["file_path"] || get_in(socket.assigns, [:file, :path])
    language = params["language"] || detect_language_from_file(file_path)
    
    # Build input for completion engine
    input = %{
      prefix: prefix,
      suffix: suffix,
      language: String.to_atom(language),
      cursor_position: cursor_position,
      file_path: file_path,
      project_context: build_project_context(socket)
    }
    
    # Create a unique request ID
    request_id = generate_request_id()
    
    # Execute completion synchronously for faster response
    case EngineManager.execute(:completion, input, 5_000) do
      {:ok, suggestions} ->
        {:reply, {:ok, %{
          request_id: request_id,
          suggestions: format_suggestions(suggestions)
        }}, socket}
        
      {:error, reason} ->
        {:reply, {:error, %{
          request_id: request_id,
          error: format_error(reason)
        }}, socket}
    end
  end

  # Handle code refactoring
  @impl true
  def handle_in("refactor", params, socket) do
    code = params["code"] || ""
    refactor_type = params["type"] || "general"
    language = params["language"] || "elixir"
    
    # Build input for refactoring engine
    input = %{
      code: code,
      language: String.to_atom(language),
      refactor_type: String.to_atom(refactor_type),
      options: params["options"] || %{},
      context: build_refactoring_context(params, socket)
    }
    
    # Create a unique request ID
    request_id = generate_request_id()
    
    # Start async refactoring
    Task.start_link(fn ->
      case EngineManager.execute(:refactoring, input, 30_000) do
        {:ok, result} ->
          push(socket, "refactor_complete", %{
            request_id: request_id,
            refactored_code: result.refactored_code,
            changes: result.changes,
            explanation: result.explanation
          })
          
        {:error, reason} ->
          push(socket, "refactor_error", %{
            request_id: request_id,
            error: format_error(reason)
          })
      end
    end)
    
    {:reply, {:ok, %{request_id: request_id}}, socket}
  end

  # Handle code analysis (delegates to analysis channel functionality)
  @impl true
  def handle_in("analyze", params, socket) do
    code = params["code"] || ""
    analysis_type = params["type"] || "general"
    file_path = params["file_path"] || "temp_file"
    language = params["language"] || detect_language_from_file(file_path)
    
    # Build input for analysis engine
    input = %{
      file_path: file_path,
      content: code,
      language: String.to_atom(language),
      options: %{
        analysis_type: String.to_atom(analysis_type),
        project_context: params["context"] || %{}
      }
    }
    
    # Create a unique request ID
    request_id = generate_request_id()
    
    # Start async analysis
    Task.start_link(fn ->
      case EngineManager.execute(:analysis, input, 30_000) do
        {:ok, result} ->
          push(socket, "analysis_complete", %{
            request_id: request_id,
            result: format_analysis_result(result)
          })
          
        {:error, reason} ->
          push(socket, "analysis_error", %{
            request_id: request_id,
            error: format_error(reason)
          })
      end
    end)
    
    {:reply, {:ok, %{request_id: request_id}}, socket}
  end

  # Placeholder handlers
  @impl true
  def handle_in("cancel", %{"request_id" => _request_id}, socket) do
    # TODO: Implement request cancellation
    {:reply, {:error, %{reason: "Cancellation not yet implemented"}}, socket}
  end

  @impl true
  def handle_in("get_status", %{"request_id" => _request_id}, socket) do
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

  defp validate_join_params(params) do
    cond do
      is_map(params) -> :ok
      true -> {:error, "Invalid join parameters"}
    end
  end
  
  defp generate_request_id do
    "req_#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end
  
  defp build_generation_context(params, socket) do
    %{
      project_files: params["project_files"] || [],
      current_file: params["current_file"] || get_in(socket.assigns, [:file, :path]),
      imports: params["imports"] || [],
      dependencies: params["dependencies"] || [],
      examples: params["examples"] || []
    }
  end
  
  defp build_project_context(socket) do
    %{
      project_id: socket.assigns[:project_id],
      project_path: get_in(socket.assigns, [:project, :path]),
      current_file: get_in(socket.assigns, [:file, :path])
    }
  end
  
  defp build_refactoring_context(params, socket) do
    %{
      project_context: build_project_context(socket),
      target_patterns: params["patterns"] || [],
      preserve_behavior: params["preserve_behavior"] != false
    }
  end
  
  defp parse_cursor_position(nil), do: {0, 0}
  defp parse_cursor_position(%{"line" => line, "column" => col}) do
    {line || 0, col || 0}
  end
  defp parse_cursor_position(_), do: {0, 0}
  
  defp detect_language_from_file(nil), do: "unknown"
  defp detect_language_from_file(file_path) do
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
  
  defp format_suggestions(suggestions) when is_list(suggestions) do
    Enum.map(suggestions, fn suggestion ->
      %{
        text: suggestion.text,
        score: suggestion.score,
        type: suggestion.type,
        description: Map.get(suggestion, :description),
        metadata: Map.get(suggestion, :metadata, %{})
      }
    end)
  end
  defp format_suggestions(_), do: []
  
  defp format_analysis_result(result) do
    %{
      file: result.file,
      language: result.language,
      issues: format_issues(result.issues),
      metrics: result.metrics || %{},
      summary: result.summary || %{}
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
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason), do: inspect(reason)
end