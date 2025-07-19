defmodule RubberDuck.MCP.Server.Resources.SystemStateTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.Server.Resources.SystemState
  alias Hermes.Server.Frame

  @moduletag :mcp_server

  describe "read/2" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, frame: frame}
    end

    test "reads system overview", %{frame: frame} do
      params = %{component: "overview"}

      assert {:ok, result, _frame} = SystemState.read(params, frame)

      assert result["mime_type"] == "application/json"
      assert result["component"] == "overview"

      # Parse the JSON content
      {:ok, data} = Jason.decode(result["content"])

      assert Map.has_key?(data, "system")
      assert data["system"]["name"] == "RubberDuck"
      assert data["system"]["version"] == "0.1.0"
      assert Map.has_key?(data["system"], "elixir_version")
      assert Map.has_key?(data["system"], "uptime_seconds")

      assert Map.has_key?(data, "node")
      assert Map.has_key?(data, "applications")
    end

    test "reads workflow information", %{frame: frame} do
      params = %{component: "workflows"}

      assert {:ok, result, _frame} = SystemState.read(params, frame)

      {:ok, data} = Jason.decode(result["content"])

      assert Map.has_key?(data, "workflows")
      assert Map.has_key?(data["workflows"], "available")
      assert Map.has_key?(data["workflows"], "active")
      assert Map.has_key?(data["workflows"], "recent_executions")
    end

    test "reads module information", %{frame: frame} do
      params = %{component: "modules"}

      assert {:ok, result, _frame} = SystemState.read(params, frame)

      {:ok, data} = Jason.decode(result["content"])

      assert Map.has_key?(data, "modules")
      assert Map.has_key?(data["modules"], "rubber_duck_modules")
      assert Map.has_key?(data["modules"], "total_loaded")

      # Should include at least this test module
      module_names = Enum.map(data["modules"]["rubber_duck_modules"], & &1["name"])
      assert Enum.any?(module_names, &String.contains?(&1, "RubberDuck"))
    end

    test "reads system metrics", %{frame: frame} do
      params = %{component: "metrics"}

      assert {:ok, result, _frame} = SystemState.read(params, frame)

      {:ok, data} = Jason.decode(result["content"])

      assert Map.has_key?(data, "metrics")

      metrics = data["metrics"]
      assert Map.has_key?(metrics, "memory")
      assert Map.has_key?(metrics["memory"], "total_mb")
      assert Map.has_key?(metrics["memory"], "processes_mb")

      assert Map.has_key?(metrics, "processes")
      assert Map.has_key?(metrics["processes"], "count")
      assert Map.has_key?(metrics["processes"], "limit")

      assert Map.has_key?(metrics, "schedulers")
      assert Map.has_key?(metrics, "reductions")
    end

    test "reads system configuration", %{frame: frame} do
      params = %{component: "config"}

      assert {:ok, result, _frame} = SystemState.read(params, frame)

      {:ok, data} = Jason.decode(result["content"])

      assert Map.has_key?(data, "config")

      config = data["config"]
      assert Map.has_key?(config, "environment")
      assert Map.has_key?(config, "paths")
      assert Map.has_key?(config, "features")

      # Verify sensitive data is not exposed
      refute String.contains?(result["content"], "secret")
      refute String.contains?(result["content"], "password")
    end
  end

  describe "list/1" do
    test "lists all available system components" do
      frame = Hermes.Server.Frame.new()

      assert {:ok, components, _frame} = SystemState.list(frame)

      assert length(components) == 5

      uris = Enum.map(components, & &1["uri"])
      assert "system://overview" in uris
      assert "system://workflows" in uris
      assert "system://modules" in uris
      assert "system://metrics" in uris
      assert "system://config" in uris

      # All should have descriptions
      assert Enum.all?(components, & &1["description"])
    end
  end

  describe "resource metadata" do
    test "has correct URI" do
      assert SystemState.uri() == "system://"
    end

    test "has correct MIME type" do
      assert SystemState.mime_type() == "application/json"
    end
  end

  describe "error handling" do
    test "handles invalid component gracefully" do
      frame = Hermes.Server.Frame.new()
      params = %{component: "invalid"}

      # Should not crash, but return some default
      assert {:ok, result, _frame} = SystemState.read(params, frame)
      assert result["mime_type"] == "application/json"
    end
  end
end
