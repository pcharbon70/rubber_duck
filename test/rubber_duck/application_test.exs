defmodule RubberDuck.ApplicationTest do
  use ExUnit.Case, async: false

  describe "RubberDuck.Application" do
    test "implements Application behaviour" do
      assert function_exported?(RubberDuck.Application, :start, 2)
      assert function_exported?(RubberDuck.Application, :stop, 1)
    end

    test "stop/1 returns :ok" do
      assert :ok = RubberDuck.Application.stop(:normal)
    end

    test "supervision tree includes Registry" do
      # Registry should be running (started by application)
      assert Process.whereis(RubberDuck.Registry) != nil
    end

    test "supervision tree includes CoreSupervisor" do
      # Find main supervisor
      main_supervisor = Process.whereis(RubberDuck.Supervisor)
      assert main_supervisor != nil
      
      # CoreSupervisor should be running
      children = Supervisor.which_children(main_supervisor)
      assert Enum.any?(children, fn {id, _, _, _} -> id == RubberDuck.CoreSupervisor end)
    end

    test "supervision tree includes TelemetrySupervisor" do
      # Find main supervisor
      main_supervisor = Process.whereis(RubberDuck.Supervisor)
      assert main_supervisor != nil
      
      # TelemetrySupervisor should be running
      children = Supervisor.which_children(main_supervisor)
      assert Enum.any?(children, fn {id, _, _, _} -> id == RubberDuck.TelemetrySupervisor end)
    end

    test "application starts successfully" do
      # Application should already be started
      assert Process.whereis(RubberDuck.Supervisor) != nil
    end
  end
end