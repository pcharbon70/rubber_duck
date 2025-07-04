defmodule RubberDuck.ApplicationTest do
  use ExUnit.Case, async: false

  describe "application startup" do
    test "application starts successfully" do
      # Test 1.1.11: Test that application starts successfully
      assert {:ok, _pid} = Application.ensure_started(:rubber_duck)
      assert List.keymember?(Application.started_applications(), :rubber_duck, 0)
    end

    test "required dependencies are available" do
      # Test 1.1.12: Test that required dependencies are available (Phoenix, Ash, Ecto)
      started_apps = Application.started_applications()
      
      # Check Ash is available
      assert List.keymember?(started_apps, :ash, 0), "Ash should be started"
      
      # Check Ecto is available
      assert List.keymember?(started_apps, :ecto, 0), "Ecto should be started"
      
      # Check Phoenix is available (when we add it)
      # Currently Phoenix is not a dependency, so we check for phoenix_pubsub
      assert List.keymember?(started_apps, :phoenix_pubsub, 0), "Phoenix PubSub should be started"
      
      # Check AshPostgres is available
      assert List.keymember?(started_apps, :ash_postgres, 0), "AshPostgres should be started"
    end

    test "supervision tree is correctly structured" do
      # Test 1.1.14: Test that supervision tree is correctly structured
      # Get the main supervisor
      {:ok, sup_pid} = :application_controller.get_master(:rubber_duck)
      
      # Check children are started
      children = Supervisor.which_children(sup_pid)
      
      # Verify expected children
      child_names = Enum.map(children, fn {name, _, _, _} -> name end)
      
      assert RubberDuck.Repo in child_names, "Repo should be supervised"
      assert RubberDuck.Telemetry in child_names, "Telemetry should be supervised"
      
      # Verify all children are running
      for {name, pid, type, _modules} <- children do
        assert is_pid(pid), "#{inspect(name)} should have a valid pid"
        assert Process.alive?(pid), "#{inspect(name)} process should be alive"
        assert type in [:worker, :supervisor], "#{inspect(name)} should have valid type"
      end
    end

    test "supervisor strategy is one_for_one" do
      # Additional test to verify supervisor strategy
      {:ok, sup_pid} = :application_controller.get_master(:rubber_duck)
      
      # Get supervisor info
      {:status, _pid, {:module, :gen_server}, info} = :sys.get_status(sup_pid)
      
      # Extract state from the info
      [_pdict, _state, _parent, _dbg, misc] = info
      
      # The strategy is in the misc data
      strategy = 
        misc
        |> Keyword.get(:data)
        |> Keyword.get(:"$supervisor")
        |> elem(0)
      
      assert strategy == :one_for_one, "Supervisor should use one_for_one strategy"
    end
  end
end