defmodule RubberDuck.Commands.Adapters.LiveView do
  @moduledoc """
  LiveView adapter for the unified command system.
  
  Provides an interface for Phoenix LiveView components to interact with
  the command processor, handling event parsing and response formatting.
  """

  alias RubberDuck.Commands.{Parser, Processor, Command, Context}

  @doc """
  Handle a LiveView event.
  
  ## Parameters
  - `event` - The LiveView event name
  - `params` - The event parameters from the LiveView form/component
  - `socket` - The LiveView socket for context information
  
  ## Returns
  - `{:ok, formatted_result}` - On successful execution
  - `{:error, reason}` - On failure
  """
  def handle_event(event, params, socket) do
    with {:ok, context} <- build_context(socket),
         {:ok, command} <- parse_liveview_event(event, params, context),
         {:ok, result} <- Processor.execute(command) do
      {:ok, result}
    end
  end

  @doc """
  Handle an async LiveView event.
  
  Returns a request ID for tracking the async execution.
  """
  def handle_async_event(event, params, socket) do
    with {:ok, context} <- build_context(socket),
         {:ok, command} <- parse_liveview_event(event, params, context),
         {:ok, result} <- Processor.execute_async(command) do
      {:ok, result}
    end
  end

  @doc """
  Parse a LiveView event into a Command struct without executing.
  """
  def parse_event(event, params, socket) do
    with {:ok, context} <- build_context(socket),
         {:ok, command} <- parse_liveview_event(event, params, context) do
      {:ok, command}
    end
  end

  @doc """
  Get the status of an async command execution.
  """
  def get_status(request_id) do
    Processor.get_status(request_id)
  end

  @doc """
  Cancel an async command execution.
  """
  def cancel(request_id) do
    Processor.cancel(request_id)
  end

  @doc """
  Build assigns for LiveView socket based on command result.
  
  Formats the result for easy consumption in LiveView templates.
  """
  def build_assigns(result, current_assigns \\ %{}) do
    case result do
      {:ok, data} ->
        assigns = %{
          command_result: data,
          command_status: :success,
          command_error: nil,
          last_command_timestamp: DateTime.utc_now()
        }
        Map.merge(current_assigns, assigns)
        
      {:error, reason} ->
        assigns = %{
          command_result: nil,
          command_status: :error,
          command_error: to_string(reason),
          last_command_timestamp: DateTime.utc_now()
        }
        Map.merge(current_assigns, assigns)
    end
  end

  @doc """
  Build flash messages for LiveView based on command result.
  """
  def build_flash(result) do
    case result do
      {:ok, %{message: message}} when is_binary(message) ->
        {:info, message}
        
      {:ok, _data} ->
        {:info, "Command executed successfully"}
        
      {:error, reason} ->
        {:error, "Command failed: #{reason}"}
    end
  end

  @doc """
  Format command result for display in LiveView templates.
  
  Converts complex data structures into template-friendly formats.
  """
  def format_for_template(result) do
    case result do
      {:ok, data} when is_map(data) ->
        format_map_for_template(data)
        
      {:ok, data} when is_list(data) ->
        Enum.map(data, &format_item_for_template/1)
        
      {:ok, data} ->
        format_item_for_template(data)
        
      {:error, reason} ->
        %{error: to_string(reason)}
    end
  end

  # Private functions

  defp build_context(socket) do
    user_id = get_user_id(socket)
    session_id = get_session_id(socket)
    
    context_data = %{
      user_id: user_id,
      project_id: Map.get(socket.assigns, :project_id),
      conversation_id: Map.get(socket.assigns, :conversation_id),
      session_id: session_id,
      permissions: get_user_permissions(socket),
      metadata: %{
        socket_id: socket.id,
        transport: "liveview",
        view_module: socket.view,
        live_action: Map.get(socket.assigns, :live_action),
        connected?: Phoenix.LiveView.connected?(socket)
      }
    }
    
    Context.new(context_data)
  end

  defp parse_liveview_event(event, params, context) do
    # Convert LiveView event to unified input format
    input = %{
      "event" => event,
      "params" => params
    }
    
    Parser.parse(input, :liveview, context)
  end

  defp get_user_id(socket) do
    case Map.get(socket.assigns, :current_user) do
      %{id: id} -> to_string(id)
      %{user_id: id} -> to_string(id)
      _ -> "liveview_user_#{socket.id}"
    end
  end

  defp get_session_id(socket) do
    case Map.get(socket.assigns, :session_id) do
      nil -> "liveview_session_#{socket.id}_#{System.system_time(:millisecond)}"
      session_id -> session_id
    end
  end

  defp get_user_permissions(socket) do
    case Map.get(socket.assigns, :current_user) do
      %{permissions: permissions} when is_list(permissions) -> permissions
      %{role: "admin"} -> [:read, :write, :execute, :admin]
      %{role: "user"} -> [:read, :write]
      _ -> [:read]
    end
  end

  defp format_map_for_template(data) when is_map(data) do
    data
    |> Enum.map(fn {key, value} -> 
      {normalize_key(key), format_item_for_template(value)}
    end)
    |> Enum.into(%{})
  end

  defp format_item_for_template(item) when is_map(item) do
    format_map_for_template(item)
  end
  defp format_item_for_template(item) when is_list(item) do
    Enum.map(item, &format_item_for_template/1)
  end
  defp format_item_for_template(%DateTime{} = dt) do
    DateTime.to_string(dt)
  end
  defp format_item_for_template(item) when is_binary(item) do
    item
  end
  defp format_item_for_template(item) when is_number(item) do
    item
  end
  defp format_item_for_template(item) when is_boolean(item) do
    item
  end
  defp format_item_for_template(item) do
    to_string(item)
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> key
    end
  end
  defp normalize_key(key), do: key
end