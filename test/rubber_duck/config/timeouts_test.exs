defmodule RubberDuck.Config.TimeoutsTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Config.Timeouts

  describe "get/2" do
    test "returns configured timeout value" do
      # These should match values in config/timeouts.exs
      assert Timeouts.get([:channels, :conversation]) == 60_000
      assert Timeouts.get([:channels, :mcp_heartbeat]) == 15_000
    end

    test "returns default when path not found" do
      assert Timeouts.get([:non, :existent, :path], 5_000) == 5_000
      assert Timeouts.get([:invalid], 1_000) == 1_000
    end

    test "returns nil when path not found and no default" do
      assert Timeouts.get([:non, :existent, :path]) == nil
    end
  end

  describe "get_category/1" do
    test "returns all timeouts for a category" do
      channels = Timeouts.get_category(:channels)
      assert is_map(channels)
      assert Map.has_key?(channels, :conversation)
      assert Map.has_key?(channels, :mcp_heartbeat)
    end

    test "returns nil for non-existent category" do
      assert Timeouts.get_category(:non_existent) == nil
    end
  end

  describe "all/0" do
    test "returns all configured timeouts" do
      all_timeouts = Timeouts.all()
      assert is_map(all_timeouts)
      assert Map.has_key?(all_timeouts, :channels)
      assert Map.has_key?(all_timeouts, :engines)
      assert Map.has_key?(all_timeouts, :tools)
      assert Map.has_key?(all_timeouts, :llm_providers)
    end
  end

  describe "get_dynamic/3" do
    test "applies model size modifiers" do
      # Base timeout is 60_000 for ollama
      base = Timeouts.get([:llm_providers, :ollama, :request])
      
      # 70b model should double the timeout
      assert Timeouts.get_dynamic(
        [:llm_providers, :ollama, :request],
        %{model: "llama2:70b"}
      ) == round(base * 2)
      
      # 30b model should get 1.5x
      assert Timeouts.get_dynamic(
        [:llm_providers, :ollama, :request],
        %{model: "llama2:30b"}
      ) == round(base * 1.5)
      
      # 13b model should get 1.2x
      assert Timeouts.get_dynamic(
        [:llm_providers, :ollama, :request],
        %{model: "llama2:13b"}
      ) == round(base * 1.2)
    end

    test "applies environment modifiers" do
      base = Timeouts.get([:channels, :conversation])
      
      # Dev environment should get 1.5x
      assert Timeouts.get_dynamic(
        [:channels, :conversation],
        %{env: :dev}
      ) == round(base * 1.5)
      
      # Test environment should get 0.5x
      assert Timeouts.get_dynamic(
        [:channels, :conversation],
        %{env: :test}
      ) == round(base * 0.5)
    end

    test "applies load modifiers" do
      base = Timeouts.get([:engines, :default])
      
      # High load should get 1.5x
      assert Timeouts.get_dynamic(
        [:engines, :default],
        %{load: :high}
      ) == round(base * 1.5)
      
      # Critical load should get 2x
      assert Timeouts.get_dynamic(
        [:engines, :default],
        %{load: :critical}
      ) == round(base * 2)
    end

    test "combines multiple modifiers" do
      base = Timeouts.get([:llm_providers, :ollama, :request])
      
      # 70b model (2x) in dev (1.5x) with high load (1.5x)
      result = Timeouts.get_dynamic(
        [:llm_providers, :ollama, :request],
        %{model: "llama2:70b", env: :dev, load: :high}
      )
      
      # Modifiers are applied in sequence: base * 2 * 1.5 * 1.5
      expected = base |> Kernel.*(2) |> Kernel.*(1.5) |> Kernel.*(1.5) |> round()
      assert result == expected
    end
  end

  describe "exists?/1" do
    test "returns true for existing paths" do
      assert Timeouts.exists?([:channels, :conversation]) == true
      assert Timeouts.exists?([:tools, :default]) == true
      assert Timeouts.exists?([:llm_providers, :ollama, :request]) == true
    end

    test "returns false for non-existent paths" do
      assert Timeouts.exists?([:non, :existent]) == false
      assert Timeouts.exists?([:invalid]) == false
    end
  end

  describe "list_paths/0" do
    test "returns list of all timeout paths" do
      paths = Timeouts.list_paths()
      assert is_list(paths)
      assert [:channels, :conversation] in paths
      assert [:tools, :default] in paths
      assert [:llm_providers, :ollama, :request] in paths
    end

    test "paths are properly nested" do
      paths = Timeouts.list_paths()
      
      # Check for nested paths
      assert Enum.any?(paths, fn path ->
        path == [:tools, :sandbox, :minimal]
      end)
      
      assert Enum.any?(paths, fn path ->
        path == [:chains, :analysis, :steps, :understanding]
      end)
    end
  end

  describe "format/1" do
    test "formats milliseconds correctly" do
      assert Timeouts.format(500) == "500ms"
      assert Timeouts.format(999) == "999ms"
    end

    test "formats seconds correctly" do
      assert Timeouts.format(1_000) == "1s"
      assert Timeouts.format(1_500) == "1.5s"
      assert Timeouts.format(30_000) == "30s"
      assert Timeouts.format(45_500) == "45.5s"
    end

    test "formats minutes correctly" do
      assert Timeouts.format(60_000) == "1m"
      assert Timeouts.format(90_000) == "1m 30s"
      assert Timeouts.format(120_000) == "2m"
      assert Timeouts.format(125_000) == "2m 5s"
    end

    test "handles edge cases" do
      assert Timeouts.format(0) == "0ms"
      assert Timeouts.format(59_999) == "59.999s"
      assert Timeouts.format(3_600_000) == "60m"
    end
  end
end