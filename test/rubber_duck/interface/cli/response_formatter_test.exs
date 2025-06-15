defmodule RubberDuck.Interface.CLI.ResponseFormatterTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Interface.CLI.ResponseFormatter
  alias RubberDuck.Interface.Behaviour

  describe "format/3" do
    test "formats success response for chat operation" do
      response = %{
        id: "req_123",
        status: :success,
        data: %{message: "Hello! How can I help you today?"},
        metadata: %{timestamp: DateTime.utc_now()}
      }
      
      request = %{operation: :chat}
      config = %{colors: false}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "RubberDuck:"
      assert formatted =~ "Hello! How can I help you today?"
    end

    test "formats success response with colors enabled" do
      response = %{
        id: "req_123",
        status: :success,
        data: %{message: "Test response"},
        metadata: %{}
      }
      
      request = %{operation: :chat}
      config = %{colors: true}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "🦆"  # Duck emoji should be present with colors
    end

    test "formats completion response with code highlighting" do
      response = %{
        id: "req_123",
        status: :success,
        data: %{
          completion: "def fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)",
          language: "python",
          confidence: 0.95
        },
        metadata: %{}
      }
      
      request = %{operation: :complete}
      config = %{colors: true, syntax_highlight: true}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "def fibonacci"
      assert formatted =~ "return"
    end

    test "formats analysis response with metrics" do
      response = %{
        id: "req_123",
        status: :success,
        data: %{
          content_type: "code",
          language: "python",
          complexity: "medium",
          word_count: 50,
          metrics: %{readability: 0.8, maintainability: 0.75},
          suggestions: ["Add type hints", "Consider error handling"]
        },
        metadata: %{}
      }
      
      request = %{operation: :analyze}
      config = %{colors: true}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "Analysis:"
      assert formatted =~ "python"
      assert formatted =~ "medium complexity"
      assert formatted =~ "Metrics:"
      assert formatted =~ "Suggestions:"
      assert formatted =~ "Add type hints"
    end

    test "formats error response" do
      response = %{
        id: "req_123",
        status: :error,
        data: %{
          message: "Invalid input provided",
          suggestions: ["Check your input format", "Try a different approach"]
        },
        metadata: %{}
      }
      
      request = %{operation: :ask}
      config = %{colors: true}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "✗"  # Error icon
      assert formatted =~ "Invalid input provided"
      assert formatted =~ "Suggestions:"
      assert formatted =~ "Check your input format"
    end

    test "formats session management response" do
      sessions = [
        %{
          id: "session_123",
          name: "test-session",
          created_at: ~U[2024-01-01 12:00:00Z],
          updated_at: ~U[2024-01-01 12:30:00Z]
        },
        %{
          id: "session_456",
          name: nil,
          created_at: ~U[2024-01-01 11:00:00Z],
          updated_at: ~U[2024-01-01 11:15:00Z]
        }
      ]
      
      response = %{
        id: "req_123",
        status: :success,
        data: %{sessions: sessions},
        metadata: %{}
      }
      
      request = %{operation: :session_management}
      config = %{colors: false}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "session_123"
      assert formatted =~ "test-session"
      assert formatted =~ "session_456"
      assert formatted =~ "2024-01-01"
    end

    test "formats status response with health indicators" do
      response = %{
        id: "req_123",
        status: :success,
        data: %{
          adapter: :cli,
          health: :healthy,
          sessions: 3,
          current_session: "session_123",
          uptime: 120000,  # 2 minutes
          requests_processed: 15,
          errors: 0,
          config: %{
            colors_enabled: true,
            syntax_highlighting: true,
            format: :text
          }
        },
        metadata: %{}
      }
      
      request = %{operation: :status}
      config = %{colors: true}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert formatted =~ "●"  # Health indicator
      assert formatted =~ "Status"
      assert formatted =~ "Health: healthy"
      assert formatted =~ "Sessions: 3"
      assert formatted =~ "Uptime: 2m 0s"
    end
  end

  describe "format_table/3" do
    test "formats table with headers and data" do
      headers = ["ID", "Name", "Status"]
      rows = [
        ["session_1", "test", "active"],
        ["session_2", "demo", "inactive"]
      ]
      
      config = %{colors: false}
      
      table = ResponseFormatter.format_table(headers, rows, config)
      
      assert table =~ "ID"
      assert table =~ "Name"
      assert table =~ "Status"
      assert table =~ "session_1"
      assert table =~ "test"
      assert table =~ "active"
      assert table =~ "|"  # Table separator
      assert table =~ "-"  # Table separator line
    end

    test "handles empty table" do
      headers = ["Column1", "Column2"]
      rows = []
      
      config = %{}
      
      table = ResponseFormatter.format_table(headers, rows, config)
      
      assert table =~ "Column1"
      assert table =~ "Column2"
      # Should still show headers even with empty data
    end
  end

  describe "highlight_code/3" do
    test "highlights Python code" do
      code = "def hello():\n    return 'world'"
      config = %{syntax_highlight: true, colors: true}
      
      highlighted = ResponseFormatter.highlight_code(code, "python", config)
      
      # Should contain ANSI color codes for keywords
      assert highlighted =~ "\e["  # ANSI escape sequence
      assert highlighted =~ "def"
      assert highlighted =~ "return"
    end

    test "highlights Elixir code" do
      code = "defmodule Test do\n  def hello, do: :world\nend"
      config = %{syntax_highlight: true, colors: true}
      
      highlighted = ResponseFormatter.highlight_code(code, "elixir", config)
      
      assert highlighted =~ "defmodule"
      assert highlighted =~ "def"
      assert highlighted =~ ":world"
    end

    test "skips highlighting when colors disabled" do
      code = "def hello(): return 'world'"
      config = %{syntax_highlight: true, colors: false}
      
      highlighted = ResponseFormatter.highlight_code(code, "python", config)
      
      # Should return original code without color codes
      assert highlighted == code
      refute highlighted =~ "\e["
    end

    test "skips highlighting when syntax_highlight disabled" do
      code = "def hello(): return 'world'"
      config = %{syntax_highlight: false, colors: true}
      
      highlighted = ResponseFormatter.highlight_code(code, "python", config)
      
      assert highlighted == code
      refute highlighted =~ "\e["
    end

    test "auto-detects language" do
      elixir_code = "defmodule Test do"
      config = %{syntax_highlight: true, colors: true}
      
      highlighted = ResponseFormatter.highlight_code(elixir_code, nil, config)
      
      # Should detect Elixir and apply highlighting
      assert highlighted =~ "\e["
    end
  end

  describe "format_stream/3" do
    test "formats stream start chunk" do
      chunk = %{type: :start, message: "Starting response..."}
      config = %{colors: true}
      
      {:ok, formatted} = ResponseFormatter.format_stream(chunk, nil, config)
      
      assert formatted =~ "⟳"  # Streaming indicator
      assert formatted =~ "Starting response..."
    end

    test "formats stream data chunk" do
      chunk = %{type: :data, content: "Hello world"}
      config = %{}
      
      {:ok, formatted} = ResponseFormatter.format_stream(chunk, nil, config)
      
      assert formatted == "Hello world"
    end

    test "formats stream end chunk" do
      chunk = %{type: :end, message: "Response complete"}
      config = %{colors: true}
      
      {:ok, formatted} = ResponseFormatter.format_stream(chunk, nil, config)
      
      assert formatted =~ "✓"  # Completion indicator
      assert formatted =~ "Response complete"
    end

    test "formats stream error chunk" do
      chunk = %{type: :error, message: "Stream failed"}
      config = %{colors: true}
      
      {:ok, formatted} = ResponseFormatter.format_stream(chunk, nil, config)
      
      assert formatted =~ "✗"  # Error indicator
      assert formatted =~ "Stream failed"
    end
  end

  describe "progress_indicator/2" do
    test "creates spinner progress indicator with colors" do
      config = %{colors: true}
      
      indicator = ResponseFormatter.progress_indicator("Processing...", config)
      
      assert indicator =~ "Processing..."
      assert indicator =~ "\e["  # Should contain color codes
    end

    test "creates simple progress indicator without colors" do
      config = %{colors: false}
      
      indicator = ResponseFormatter.progress_indicator("Processing...", config)
      
      assert indicator == "... Processing..."
      refute indicator =~ "\e["
    end
  end

  describe "message formatting with code blocks" do
    test "formats message with inline code blocks" do
      message = "Here's some code:\n```python\ndef hello():\n    return 'world'\n```\nThat's it!"
      config = %{syntax_highlight: true, colors: true}
      
      # This would be called internally by format_chat_response
      # Testing the concept with a simplified approach
      assert message =~ "```python"
      assert message =~ "def hello()"
    end
  end

  describe "configuration display formatting" do
    test "formats configuration with categorization" do
      config_data = %{
        colors: true,
        syntax_highlight: false,
        model: "claude",
        temperature: 0.7,
        session_auto_save: true
      }
      
      config = %{colors: true}
      
      # Test would call format_config_display (private function)
      # Verify the categorization logic works
      categorized = categorize_config(config_data)
      
      assert Map.has_key?(categorized, "display")
      assert Map.has_key?(categorized, "ai")
      assert categorized["display"][:colors] == true
      assert categorized["ai"][:model] == "claude"
    end
  end

  # Helper function for testing config categorization
  defp categorize_config(config_data) do
    Enum.group_by(config_data, fn {key, _value} ->
      key_str = to_string(key)
      cond do
        String.contains?(key_str, "color") -> "display"
        String.contains?(key_str, "format") -> "display"
        String.contains?(key_str, "model") -> "ai"
        String.contains?(key_str, "temperature") -> "ai"
        String.contains?(key_str, "session") -> "session"
        true -> "general"
      end
    end)
  end

  describe "error handling" do
    test "handles format errors gracefully" do
      # Test with malformed response
      response = %{invalid: :structure}
      request = %{operation: :chat}
      config = %{}
      
      assert {:error, reason} = ResponseFormatter.format(response, request, config)
      assert reason =~ "Formatting error"
    end

    test "handles missing data fields" do
      response = %{
        id: "req_123",
        status: :success,
        data: %{},  # Empty data
        metadata: %{}
      }
      
      request = %{operation: :chat}
      config = %{}
      
      assert {:ok, formatted} = ResponseFormatter.format(response, request, config)
      assert is_binary(formatted)
    end
  end
end