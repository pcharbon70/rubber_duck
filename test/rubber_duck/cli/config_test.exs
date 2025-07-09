defmodule RubberDuck.CLI.ConfigTest do
  use ExUnit.Case, async: true

  alias RubberDuck.CLI.Config

  describe "from_parsed_args/1" do
    test "creates config with default values" do
      parsed = %{
        options: %{},
        flags: %{}
      }

      config = Config.from_parsed_args(parsed)

      assert config.format == :plain
      assert config.verbose == false
      assert config.quiet == false
      assert config.debug == false
      assert config.config_file == nil
    end

    test "creates config with specified values" do
      parsed = %{
        options: %{
          format: :json,
          config: "/path/to/config"
        },
        flags: %{
          verbose: true,
          quiet: false,
          debug: true
        }
      }

      config = Config.from_parsed_args(parsed)

      assert config.format == :json
      assert config.verbose == true
      assert config.quiet == false
      assert config.debug == true
      assert config.config_file == "/path/to/config"
    end
  end

  describe "load_config_file/2" do
    test "loads valid JSON config" do
      config = %Config{}
      json_content = ~s({"theme": "dark", "editor": "vim"})

      in_tmp(fn path ->
        config_file = Path.join(path, "config.json")
        File.write!(config_file, json_content)

        loaded = Config.load_config_file(config, config_file)

        assert loaded.user_preferences["theme"] == "dark"
        assert loaded.user_preferences["editor"] == "vim"
      end)
    end

    test "handles missing config file gracefully" do
      config = %Config{}

      output =
        capture_io(:stderr, fn ->
          loaded = Config.load_config_file(config, "/nonexistent/config.json")
          assert loaded == config
        end)

      assert output =~ "Config file not found"
    end

    test "handles invalid JSON gracefully" do
      config = %Config{}

      in_tmp(fn path ->
        config_file = Path.join(path, "config.json")
        File.write!(config_file, "invalid json")

        output =
          capture_io(:stderr, fn ->
            loaded = Config.load_config_file(config, config_file)
            assert loaded == config
          end)

        assert output =~ "Failed to parse config file"
      end)
    end
  end

  describe "get_preference/3" do
    test "returns preference value when present" do
      config = %Config{
        user_preferences: %{"theme" => "dark", "timeout" => 30}
      }

      assert Config.get_preference(config, "theme") == "dark"
      assert Config.get_preference(config, "timeout") == 30
    end

    test "returns default when preference not found" do
      config = %Config{user_preferences: %{}}

      assert Config.get_preference(config, "missing", "default") == "default"
      assert Config.get_preference(config, "missing") == nil
    end
  end

  describe "merge_options/2" do
    test "merges options into config" do
      config = %Config{format: :plain, verbose: false}
      options = [format: :json, verbose: true, new_option: "value"]

      merged = Config.merge_options(config, options)

      assert merged.format == :json
      assert merged.verbose == true
      assert merged.new_option == "value"
    end
  end

  defp in_tmp(fun) do
    path = Path.join(System.tmp_dir!(), "cli_config_test_#{System.unique_integer()}")
    File.mkdir_p!(path)

    try do
      fun.(path)
    after
      File.rm_rf!(path)
    end
  end

  defp capture_io(device \\ :stdio, fun) do
    ExUnit.CaptureIO.capture_io(device, fun)
  end
end
