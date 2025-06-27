defmodule RubberDuckWeb.ClientAdapters do
  @moduledoc """
  Client adapters for different interface types in the RubberDuck system.

  These adapters provide specialized formatting and handling for different
  client types: web, CLI, and TUI interfaces.
  """

  @type client_type :: :web | :cli | :tui
  @type message_data :: map()
  @type formatted_message :: map()

  @doc """
  Formats a message for a specific client type.
  """
  @spec format_message(message_data(), client_type()) :: formatted_message()
  def format_message(message, client_type) do
    case client_type do
      :web -> RubberDuckWeb.ClientAdapters.WebAdapter.format_message(message)
      :cli -> RubberDuckWeb.ClientAdapters.CLIAdapter.format_message(message)
      :tui -> RubberDuckWeb.ClientAdapters.TUIAdapter.format_message(message)
    end
  end

  @doc """
  Detects client type from socket or connection metadata.
  """
  @spec detect_client_type(map()) :: client_type()
  def detect_client_type(metadata) do
    case metadata do
      %{"client_type" => "cli"} ->
        :cli

      %{"client_type" => "tui"} ->
        :tui

      %{"user_agent" => user_agent} when is_binary(user_agent) ->
        if String.contains?(user_agent, "curl") or String.contains?(user_agent, "httpie") do
          :cli
        else
          :web
        end

      _ ->
        :web
    end
  end
end

defmodule RubberDuckWeb.ClientAdapters.WebAdapter do
  @moduledoc """
  Web client adapter for browser-based interfaces.
  """

  @spec format_message(map()) :: map()
  def format_message(message) do
    Map.merge(message, %{
      formatted_content: format_web_content(message.content, message.content_type),
      timestamp_display: format_web_timestamp(message.timestamp),
      client_type: :web
    })
  end

  defp format_web_content(content, :code) do
    %{
      type: "code",
      content: content,
      highlight: true,
      syntax: detect_syntax(content)
    }
  end

  defp format_web_content(content, :error) do
    %{
      type: "error",
      content: content,
      severity: "error",
      dismissible: true
    }
  end

  defp format_web_content(content, _type) do
    %{
      type: "text",
      content: content,
      markdown: true
    }
  end

  defp format_web_timestamp(timestamp) do
    DateTime.to_iso8601(timestamp)
  end

  defp detect_syntax(content) do
    cond do
      String.contains?(content, "def ") -> "elixir"
      String.contains?(content, "function ") -> "javascript"
      String.contains?(content, "class ") -> "python"
      true -> "text"
    end
  end
end

defmodule RubberDuckWeb.ClientAdapters.CLIAdapter do
  @moduledoc """
  CLI client adapter for command-line interfaces.
  """

  @spec format_message(map()) :: map()
  def format_message(message) do
    Map.merge(message, %{
      formatted_content: format_cli_content(message.content, message.content_type),
      timestamp_display: format_cli_timestamp(message.timestamp),
      client_type: :cli
    })
  end

  defp format_cli_content(content, :code) do
    # Simple formatting for CLI - no syntax highlighting
    """
    ```
    #{content}
    ```
    """
  end

  defp format_cli_content(content, :error) do
    "ERROR: #{content}"
  end

  defp format_cli_content(content, _type) do
    content
  end

  defp format_cli_timestamp(timestamp) do
    timestamp
    |> DateTime.truncate(:second)
    |> DateTime.to_string()
  end
end

defmodule RubberDuckWeb.ClientAdapters.TUIAdapter do
  @moduledoc """
  TUI (Terminal User Interface) client adapter.
  """

  @spec format_message(map()) :: map()
  def format_message(message) do
    Map.merge(message, %{
      formatted_content: format_tui_content(message.content, message.content_type),
      timestamp_display: format_tui_timestamp(message.timestamp),
      client_type: :tui,
      color_scheme: determine_color_scheme(message.content_type)
    })
  end

  defp format_tui_content(content, :code) do
    %{
      content: content,
      box_style: "code",
      scrollable: true
    }
  end

  defp format_tui_content(content, :error) do
    %{
      content: content,
      box_style: "error",
      urgency: "high"
    }
  end

  defp format_tui_content(content, _type) do
    %{
      content: content,
      box_style: "normal",
      word_wrap: true
    }
  end

  defp format_tui_timestamp(timestamp) do
    timestamp
    |> DateTime.to_time()
    |> Time.to_string()
    # HH:MM:SS
    |> String.slice(0..7)
  end

  defp determine_color_scheme(:error), do: "red"
  defp determine_color_scheme(:code), do: "cyan"
  defp determine_color_scheme(_), do: "default"
end
