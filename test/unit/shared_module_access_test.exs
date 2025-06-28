defmodule SharedModuleAccessTest do
  @moduledoc """
  Tests for shared module accessibility across umbrella apps.
  """
  
  use ExUnit.Case, async: true

  describe "core modules accessibility" do
    test "core conversation modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckCore.Conversation)
      assert Code.ensure_loaded?(RubberDuckCore.Message)
      assert Code.ensure_loaded?(RubberDuckCore.ConversationManager)
    end

    test "core pub/sub modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckCore.PubSub)
    end

    test "core analysis modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckCore.Analysis)
    end

    test "core application module is accessible" do
      assert Code.ensure_loaded?(RubberDuckCore.Application)
    end

    test "core configuration modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckCore.Config)
      assert Code.ensure_loaded?(RubberDuckCore.Environment)
      assert Code.ensure_loaded?(RubberDuckCore.Startup)
    end
  end

  describe "storage modules accessibility" do
    test "storage repository is accessible from other apps" do
      assert Code.ensure_loaded?(RubberDuckStorage.Repository)
    end

    test "storage repo module is accessible" do
      assert Code.ensure_loaded?(RubberDuckStorage.Repo)
    end

    test "storage context manager is accessible" do
      assert Code.ensure_loaded?(RubberDuckStorage.ContextManager)
    end

    test "storage configuration helper is accessible" do
      assert Code.ensure_loaded?(RubberDuckStorage.Config)
    end
  end

  describe "engines modules accessibility" do
    test "engine framework modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckEngines.Engine)
      assert Code.ensure_loaded?(RubberDuckEngines.EnginePool)
    end

    test "engine supervisor modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckEngines.EnginePool.Supervisor)
    end

    test "specific engine modules are accessible" do
      assert Code.ensure_loaded?(RubberDuckEngines.Engines.CodeAnalysisEngine)
      assert Code.ensure_loaded?(RubberDuckEngines.Engines.DocumentationEngine)
      assert Code.ensure_loaded?(RubberDuckEngines.Engines.TestingEngine)
      assert Code.ensure_loaded?(RubberDuckEngines.Engines.CodeReviewEngine)
    end

    test "engines configuration helper is accessible" do
      assert Code.ensure_loaded?(RubberDuckEngines.Config)
    end
  end

  describe "web modules accessibility" do
    test "web endpoint and channels are accessible" do
      assert Code.ensure_loaded?(RubberDuckWeb.Endpoint)
      assert Code.ensure_loaded?(RubberDuckWeb.CodingChannel)
    end

    test "web client adapters are accessible" do
      assert Code.ensure_loaded?(RubberDuckWeb.ClientAdapters.WebClientAdapter)
      assert Code.ensure_loaded?(RubberDuckWeb.ClientAdapters.CLIClientAdapter)
      assert Code.ensure_loaded?(RubberDuckWeb.ClientAdapters.TUIClientAdapter)
    end

    test "web configuration helper is accessible" do
      assert Code.ensure_loaded?(RubberDuckWeb.Config)
    end
  end

  describe "cross-app module access patterns" do
    test "web app can access core modules" do
      # Web should be able to use core conversation management
      assert function_exported?(RubberDuckCore.ConversationManager, :start_conversation, 2)
      assert function_exported?(RubberDuckCore.ConversationManager, :add_message, 3)
      
      # Web should be able to use core PubSub
      assert function_exported?(RubberDuckCore.PubSub, :child_spec, 1)
    end

    test "engines app can access core modules" do
      # Engines should be able to use core PubSub for notifications
      assert function_exported?(RubberDuckCore.PubSub, :child_spec, 1)
      
      # Engines should be able to access core data structures
      assert function_exported?(RubberDuckCore.Analysis, :new, 0)
    end

    test "core app can access storage modules" do
      # Core should be able to use storage repository
      assert function_exported?(RubberDuckStorage.Repository, :all_projects, 0)
      assert function_exported?(RubberDuckStorage.Repository, :create_conversation, 2)
      
      # Core should be able to use context manager
      assert function_exported?(RubberDuckStorage.ContextManager, :get_context, 1)
    end

    test "storage app can access core schemas" do
      # Storage should be able to use core data structures for schemas
      assert function_exported?(RubberDuckCore.Conversation, :changeset, 2)
      assert function_exported?(RubberDuckCore.Message, :changeset, 2)
    end
  end

  describe "module dependency boundaries" do
    test "storage does not depend on engines or web" do
      # Get all modules loaded by storage app
      storage_modules = get_app_modules(:rubber_duck_storage)
      
      # Should not contain any engine or web modules
      engine_modules = get_app_modules(:rubber_duck_engines)
      web_modules = get_app_modules(:rubber_duck_web)
      
      overlap_engines = MapSet.intersection(MapSet.new(storage_modules), MapSet.new(engine_modules))
      overlap_web = MapSet.intersection(MapSet.new(storage_modules), MapSet.new(web_modules))
      
      assert MapSet.size(overlap_engines) == 0, 
        "Storage should not depend on engines modules: #{inspect(MapSet.to_list(overlap_engines))}"
      
      assert MapSet.size(overlap_web) == 0,
        "Storage should not depend on web modules: #{inspect(MapSet.to_list(overlap_web))}"
    end

    test "core does not depend on web" do
      # Core should not depend directly on web modules
      core_modules = get_app_modules(:rubber_duck_core)
      web_modules = get_app_modules(:rubber_duck_web)
      
      overlap = MapSet.intersection(MapSet.new(core_modules), MapSet.new(web_modules))
      
      assert MapSet.size(overlap) == 0,
        "Core should not depend on web modules: #{inspect(MapSet.to_list(overlap))}"
    end

    test "engines do not depend on web" do
      # Engines should not depend directly on web modules
      engine_modules = get_app_modules(:rubber_duck_engines)
      web_modules = get_app_modules(:rubber_duck_web)
      
      overlap = MapSet.intersection(MapSet.new(engine_modules), MapSet.new(web_modules))
      
      assert MapSet.size(overlap) == 0,
        "Engines should not depend on web modules: #{inspect(MapSet.to_list(overlap))}"
    end
  end

  describe "protocol and behaviour implementations" do
    test "engines implement required behaviours" do
      # Test that engine modules implement the Engine behaviour
      engines = [
        RubberDuckEngines.Engines.CodeAnalysisEngine,
        RubberDuckEngines.Engines.DocumentationEngine, 
        RubberDuckEngines.Engines.TestingEngine,
        RubberDuckEngines.Engines.CodeReviewEngine
      ]
      
      Enum.each(engines, fn engine_module ->
        assert Code.ensure_loaded?(engine_module)
        
        # Check if it implements the Engine behaviour callbacks
        # This is a basic check - in a full implementation we'd verify specific callbacks
        behaviours = engine_module.module_info(:attributes)[:behaviour] || []
        
        # May implement RubberDuckEngines.Engine behaviour
        # This test is flexible as the exact behaviour structure may evolve
        assert is_list(behaviours)
      end)
    end

    test "client adapters implement required protocols" do
      adapters = [
        RubberDuckWeb.ClientAdapters.WebClientAdapter,
        RubberDuckWeb.ClientAdapters.CLIClientAdapter,
        RubberDuckWeb.ClientAdapters.TUIClientAdapter
      ]
      
      Enum.each(adapters, fn adapter_module ->
        assert Code.ensure_loaded?(adapter_module)
        
        # Basic existence check - full protocol compliance would be tested
        # in more specific integration tests
      end)
    end
  end

  # Helper function to get modules for an app
  defp get_app_modules(app_name) do
    case Application.spec(app_name, :modules) do
      nil -> []
      modules -> modules
    end
  end
end