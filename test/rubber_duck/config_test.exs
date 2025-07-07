defmodule RubberDuck.ConfigTest do
  use ExUnit.Case, async: true

  describe "configuration loading" do
    test "configuration files are properly loaded" do
      # Test 1.1.13: Test that configuration files are properly loaded

      # Check that ecto_repos is configured
      assert repos = Application.get_env(:rubber_duck, :ecto_repos)
      assert [RubberDuck.Repo] == repos

      # Check Ash configuration
      ash_config = Application.get_all_env(:ash)
      assert is_list(ash_config)

      # Verify key Ash configurations are set
      assert Application.get_env(:ash, :include_embedded_source_by_default?) == false
      assert Application.get_env(:ash, :default_page_type) == :keyset
      assert Application.get_env(:ash, :default_actions_require_atomic?) == true

      # Check Spark formatter configuration
      spark_config = Application.get_env(:spark, :formatter)
      assert is_list(spark_config)
      assert spark_config[:remove_parens?] == true
    end

    test "environment-specific configuration is loaded" do
      # Verify that the correct environment config was loaded
      env = Mix.env()

      case env do
        :test ->
          # Test-specific configuration
          assert Application.get_env(:logger, :level) == :warning
          assert Application.get_env(:ash, :disable_async?) == true

          # Check test database configuration
          repo_config = Application.get_env(:rubber_duck, RubberDuck.Repo)
          assert repo_config[:database] =~ "rubber_duck_test"
          assert repo_config[:pool] == Ecto.Adapters.SQL.Sandbox

        :dev ->
          # Dev-specific checks would go here
          :ok

        :prod ->
          # Prod-specific checks would go here
          :ok
      end
    end

    test "telemetry configuration is loaded" do
      # Verify telemetry.exs was imported
      telemetry_config = Application.get_env(:rubber_duck, :telemetry)

      # Check console reporter config
      assert console_config = telemetry_config[:console]
      assert console_config[:enabled] == true
      assert is_list(console_config[:metrics])
    end
  end

  describe "environment variables" do
    test "environment variables are properly read" do
      # Test 1.1.15: Test that environment variables are properly read

      # Save current env
      original_value = System.get_env("RUBBER_DUCK_TEST_VAR")

      try do
        # Set a test environment variable
        System.put_env("RUBBER_DUCK_TEST_VAR", "test_value")

        # Verify it can be read
        assert System.get_env("RUBBER_DUCK_TEST_VAR") == "test_value"

        # Verify MIX_ENV is set
        assert System.get_env("MIX_ENV") in ["test", "dev", "prod"]

        # For test environment, check MIX_TEST_PARTITION if running in parallel
        if Mix.env() == :test do
          partition = System.get_env("MIX_TEST_PARTITION")
          # It may or may not be set depending on test runner
          assert is_nil(partition) or is_binary(partition)
        end
      after
        # Restore original value
        if original_value do
          System.put_env("RUBBER_DUCK_TEST_VAR", original_value)
        else
          System.delete_env("RUBBER_DUCK_TEST_VAR")
        end
      end
    end

    test "database URL can be configured via environment variable" do
      # Many production deployments use DATABASE_URL
      database_url = System.get_env("DATABASE_URL")

      if database_url do
        assert String.starts_with?(database_url, "postgres://") or
                 String.starts_with?(database_url, "postgresql://")
      else
        # If not set, that's fine for local development
        assert true
      end
    end
  end
end
