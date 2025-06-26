defmodule RubberDuckWeb.ClientAdaptersTest do
  use ExUnit.Case, async: true

  alias RubberDuckWeb.ClientAdapters

  describe "client type detection" do
    test "detects web client from browser user agent" do
      metadata = %{"user_agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
      assert ClientAdapters.detect_client_type(metadata) == :web
    end

    test "detects CLI client from curl user agent" do
      metadata = %{"user_agent" => "curl/7.68.0"}
      assert ClientAdapters.detect_client_type(metadata) == :cli
    end

    test "detects CLI client from explicit client type" do
      metadata = %{"client_type" => "cli"}
      assert ClientAdapters.detect_client_type(metadata) == :cli
    end

    test "detects TUI client from explicit client type" do
      metadata = %{"client_type" => "tui"}
      assert ClientAdapters.detect_client_type(metadata) == :tui
    end

    test "defaults to web for unknown clients" do
      metadata = %{}
      assert ClientAdapters.detect_client_type(metadata) == :web
    end
  end

  describe "message formatting" do
    setup do
      message = %{
        content: "Hello world",
        content_type: :text,
        timestamp: ~U[2024-06-26 15:30:00Z],
        role: :user
      }
      %{message: message}
    end

    test "formats message for web client", %{message: message} do
      formatted = ClientAdapters.format_message(message, :web)
      
      assert formatted.client_type == :web
      assert formatted.formatted_content.type == "text"
      assert formatted.formatted_content.markdown == true
      assert formatted.timestamp_display == "2024-06-26T15:30:00Z"
    end

    test "formats message for CLI client", %{message: message} do
      formatted = ClientAdapters.format_message(message, :cli)
      
      assert formatted.client_type == :cli
      assert formatted.formatted_content == "Hello world"
      assert is_binary(formatted.timestamp_display)
    end

    test "formats message for TUI client", %{message: message} do
      formatted = ClientAdapters.format_message(message, :tui)
      
      assert formatted.client_type == :tui
      assert formatted.formatted_content.content == "Hello world"
      assert formatted.formatted_content.box_style == "normal"
      assert formatted.color_scheme == "default"
    end

    test "formats code content for web client", %{message: message} do
      code_message = %{message | content: "def hello, do: :world", content_type: :code}
      formatted = ClientAdapters.format_message(code_message, :web)
      
      assert formatted.formatted_content.type == "code"
      assert formatted.formatted_content.highlight == true
      assert formatted.formatted_content.syntax == "elixir"
    end

    test "formats error content for CLI client", %{message: message} do
      error_message = %{message | content: "Something went wrong", content_type: :error}
      formatted = ClientAdapters.format_message(error_message, :cli)
      
      assert formatted.formatted_content == "ERROR: Something went wrong"
    end

    test "formats error content for TUI client", %{message: message} do
      error_message = %{message | content: "Something went wrong", content_type: :error}
      formatted = ClientAdapters.format_message(error_message, :tui)
      
      assert formatted.formatted_content.box_style == "error"
      assert formatted.color_scheme == "red"
    end
  end
end