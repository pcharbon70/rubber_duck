defmodule RubberDuck.Interface.TransformerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Interface.Transformer
  
  describe "normalize_request/3" do
    test "normalizes CLI request" do
      cli_request = %{
        "command" => "chat",
        "message" => "Hello world",
        "options" => %{"model" => "gpt-4"}
      }
      
      {:ok, normalized} = Transformer.normalize_request(cli_request, :cli)
      
      assert normalized.operation == :chat
      assert normalized.interface == :cli
      assert normalized.params[:message] == "Hello world"
      assert normalized.params[:model] == "gpt-4"
      assert is_binary(normalized.id)
      assert %DateTime{} = normalized.timestamp
    end
    
    test "normalizes web request" do
      web_request = %{
        "method" => "POST",
        "body" => %{"message" => "Hello"},
        "query" => %{"model" => "claude"}
      }
      
      {:ok, normalized} = Transformer.normalize_request(web_request, :web)
      
      assert normalized.operation == :post
      assert normalized.interface == :web
      assert normalized.params[:message] == "Hello"
      assert normalized.params[:model] == "claude"
    end
    
    test "normalizes LSP request" do
      lsp_request = %{
        "method" => "textDocument/completion",
        "params" => %{"textDocument" => %{"uri" => "file:///test.txt"}}
      }
      
      {:ok, normalized} = Transformer.normalize_request(lsp_request, :lsp)
      
      assert normalized.operation == :"textDocument/completion"
      assert normalized.interface == :lsp
      assert normalized.params["textDocument"]["uri"] == "file:///test.txt"
    end
    
    test "handles string input by parsing JSON" do
      json_request = Jason.encode!(%{"operation" => "test", "params" => %{}})
      
      {:ok, normalized} = Transformer.normalize_request(json_request, :generic)
      
      assert normalized["operation"] == "test"
      assert normalized["params"] == %{}
    end
    
    test "handles invalid input gracefully" do
      invalid_request = "not json"
      
      {:ok, normalized} = Transformer.normalize_request(invalid_request, :generic)
      
      assert normalized[:raw] == "not json"
    end
    
    test "applies custom field mappings" do
      request = %{"custom_op" => "test", "data" => %{}}
      config = %{
        field_mappings: [
          {"custom_op", :operation},
          {"data", :params}
        ]
      }
      
      {:ok, normalized} = Transformer.normalize_request(request, :generic, config)
      
      assert normalized.operation == "test"
      assert normalized.params == %{}
    end
    
    test "applies type conversions" do
      request = %{"operation" => "test", "count" => "42"}
      config = %{
        type_conversions: %{
          operation: :atom,
          count: :integer
        }
      }
      
      {:ok, normalized} = Transformer.normalize_request(request, :generic, config)
      
      assert normalized.operation == :test
      assert normalized.count == 42
    end
  end
  
  describe "denormalize_response/4" do
    test "denormalizes response for CLI interface" do
      response = %{
        id: "req_123",
        status: :ok,
        data: %{message: "Response"},
        metadata: %{duration: 100}
      }
      
      {:ok, denormalized} = Transformer.denormalize_response(response, :cli)
      
      assert denormalized.id == "req_123"
      assert denormalized.status == :ok
      assert denormalized.data.message == "Response"
      assert denormalized.metadata.interface == :cli
      assert %DateTime{} = denormalized.metadata.processed_at
    end
    
    test "applies interface-specific transformations" do
      response = %{id: "123", status: :ok, data: "test"}
      config = %{
        cli_response_mappings: [
          {:status, "result_status"},
          {:data, "result_data"}
        ]
      }
      
      {:ok, denormalized} = Transformer.denormalize_response(response, :cli, %{}, config)
      
      assert denormalized["result_status"] == :ok
      assert denormalized["result_data"] == "test"
    end
    
    test "sanitizes sensitive data" do
      response = %{
        id: "123",
        status: :ok,
        data: %{
          message: "Hello",
          password: "secret123",
          auth_token: "token456"
        }
      }
      
      {:ok, denormalized} = Transformer.denormalize_response(response, :web)
      
      assert denormalized.data.message == "Hello"
      assert denormalized.data.password == "[REDACTED]"
      assert denormalized.data.auth_token == "[REDACTED]"
    end
  end
  
  describe "extract_context/2" do
    test "extracts CLI context" do
      request = %{
        "user" => "alice",
        "session" => "sess_123",
        "cwd" => "/home/alice",
        "env" => %{"PATH" => "/usr/bin"},
        "args" => ["--verbose", "--model", "gpt-4"]
      }
      
      {:ok, context} = Transformer.extract_context(request, :cli)
      
      assert context.user_id == "alice"
      assert context.session_id == "sess_123"
      assert context.working_directory == "/home/alice"
      assert context.environment["PATH"] == "/usr/bin"
      assert context.arguments == ["--verbose", "--model", "gpt-4"]
    end
    
    test "extracts web context" do
      request = %{
        "headers" => %{
          "x-user-id" => "user123",
          "x-session-id" => "sess456",
          "authorization" => "Bearer token789",
          "user-agent" => "Mozilla/5.0",
          "x-forwarded-for" => "192.168.1.1"
        }
      }
      
      {:ok, context} = Transformer.extract_context(request, :web)
      
      assert context.user_id == "user123"
      assert context.session_id == "sess456"
      assert context.auth_token == "token789"
      assert context.user_agent == "Mozilla/5.0"
      assert context.source_ip == "192.168.1.1"
    end
    
    test "extracts LSP context" do
      request = %{
        "workspaceUri" => "file:///workspace",
        "textDocument" => %{"uri" => "file:///test.ex"},
        "clientInfo" => %{"name" => "VS Code", "version" => "1.70.0"},
        "capabilities" => %{"completion" => true}
      }
      
      {:ok, context} = Transformer.extract_context(request, :lsp)
      
      assert context.workspace_uri == "file:///workspace"
      assert context.document_uri == "file:///test.ex"
      assert context.client_name == "VS Code"
      assert context.client_version == "1.70.0"
      assert context.capabilities["completion"] == true
    end
    
    test "extracts generic context" do
      request = %{
        "user_id" => "user123",
        "session_id" => "sess456",
        "metadata" => %{"custom" => "data"}
      }
      
      {:ok, context} = Transformer.extract_context(request, :generic)
      
      assert context.user_id == "user123"
      assert context.session_id == "sess456"
      assert context.metadata == %{"custom" => "data"}
    end
  end
  
  describe "merge_metadata/2" do
    test "merges simple metadata" do
      request_meta = %{source: "cli", timing: %{start: 100}}
      response_meta = %{timing: %{end: 200}, result: "success"}
      
      merged = Transformer.merge_metadata(request_meta, response_meta)
      
      assert merged.source == "cli"
      assert merged.timing.start == 100
      assert merged.timing.end == 200
      assert merged.result == "success"
    end
    
    test "handles nil metadata" do
      merged = Transformer.merge_metadata(nil, %{key: "value"})
      
      assert merged == %{key: "value"}
    end
    
    test "response metadata takes precedence" do
      request_meta = %{status: "pending", timestamp: 1}
      response_meta = %{status: "complete", timestamp: 2}
      
      merged = Transformer.merge_metadata(request_meta, response_meta)
      
      assert merged.status == "complete"
      assert merged.timestamp == 2
    end
  end
  
  describe "sanitize_data/2" do
    test "sanitizes password fields" do
      data = %{
        username: "alice",
        password: "secret123",
        nested: %{
          api_key: "key456",
          message: "hello"
        }
      }
      
      sanitized = Transformer.sanitize_data(data)
      
      assert sanitized.username == "alice"
      assert sanitized.password == "[REDACTED]"
      assert sanitized.nested.message == "hello"
      assert sanitized.nested.api_key == "[REDACTED]"
    end
    
    test "sanitizes custom sensitive fields" do
      data = %{
        username: "alice",  
        credit_card: "1234-5678-9012-3456",
        message: "hello"
      }
      
      sanitized = Transformer.sanitize_data(data, [:credit_card])
      
      assert sanitized.username == "alice"
      assert sanitized.credit_card == "[REDACTED]"
      assert sanitized.message == "hello"
    end
    
    test "sanitizes lists of data" do
      data = [
        %{name: "alice", password: "secret1"},
        %{name: "bob", password: "secret2"}
      ]
      
      sanitized = Transformer.sanitize_data(data)
      
      assert length(sanitized) == 2
      assert Enum.at(sanitized, 0).name == "alice"
      assert Enum.at(sanitized, 0).password == "[REDACTED]"
      assert Enum.at(sanitized, 1).name == "bob"
      assert Enum.at(sanitized, 1).password == "[REDACTED]"
    end
    
    test "handles non-map, non-list data" do
      assert Transformer.sanitize_data("string") == "string"
      assert Transformer.sanitize_data(123) == 123
      assert Transformer.sanitize_data(:atom) == :atom
    end
  end
  
  describe "field transformations" do
    test "transforms CLI args to params" do
      cli_request = %{
        "command" => "chat",
        "args" => ["--model", "gpt-4", "--temperature", "0.7", "--verbose"]
      }
      
      {:ok, normalized} = Transformer.normalize_request(cli_request, :cli)
      
      # Args should be transformed into structured params
      assert normalized.operation == :chat
      params = normalized.params
      assert params[:model] == "gpt-4"
      assert params[:temperature] == "0.7"
      assert params[:verbose] == true
    end
    
    test "handles type conversions" do
      request = %{
        "operation" => "calculate",
        "count" => "42",
        "rate" => "3.14",
        "enabled" => "true"
      }
      
      config = %{
        type_conversions: %{
          operation: :atom,
          count: :integer,
          rate: :float,
          enabled: :boolean
        }
      }
      
      {:ok, normalized} = Transformer.normalize_request(request, :generic, config)
      
      assert normalized.operation == :calculate
      assert normalized.count == 42
      assert normalized.rate == 3.14
      assert normalized.enabled == true
    end
    
    test "applies field mapping with transformation function" do
      request = %{"timestamp" => "2023-01-01T12:00:00Z"}
      
      config = %{
        field_mappings: [
          {"timestamp", :created_at, fn ts -> 
            {:ok, dt, _} = DateTime.from_iso8601(ts)
            dt
          end}
        ]
      }
      
      {:ok, normalized} = Transformer.normalize_request(request, :generic, config)
      
      assert %DateTime{} = normalized.created_at
      refute Map.has_key?(normalized, :timestamp)
    end
  end
end