defmodule UmbrellaTestHelper do
  @moduledoc """
  Test helper functions for umbrella project integration tests.
  """

  @doc """
  Starts all umbrella applications in the correct order.
  """
  def start_umbrella_apps do
    # Start applications in dependency order
    {:ok, _} = Application.ensure_all_started(:rubber_duck_storage)
    {:ok, _} = Application.ensure_all_started(:rubber_duck_core)
    {:ok, _} = Application.ensure_all_started(:rubber_duck_engines)
    {:ok, _} = Application.ensure_all_started(:rubber_duck_web)
  end

  @doc """
  Stops all umbrella applications.
  """
  def stop_umbrella_apps do
    Application.stop(:rubber_duck_web)
    Application.stop(:rubber_duck_engines)
    Application.stop(:rubber_duck_core)
    Application.stop(:rubber_duck_storage)
  end

  @doc """
  Compiles a specific app in isolation to test independent compilation.
  """
  def compile_app_independently(app_name) do
    app_path = Path.join(["apps", to_string(app_name)])
    
    {output, exit_code} = 
      System.cmd("mix", ["compile"], 
        cd: app_path,
        stderr_to_stdout: true
      )
    
    {exit_code == 0, output}
  end

  @doc """
  Tests configuration loading for a specific environment.
  """
  def test_config_loading(env) do
    original_env = Mix.env()
    
    try do
      Mix.env(env)
      
      # Reload configuration
      Application.stop(:rubber_duck_core)
      Application.stop(:rubber_duck_storage)
      Application.stop(:rubber_duck_engines)
      Application.stop(:rubber_duck_web)
      
      # Test configuration loading
      config_loaded = try do
        RubberDuckCore.Config.validate!()
        true
      rescue
        _ -> false
      end
      
      config_loaded
    after
      Mix.env(original_env)
    end
  end

  @doc """
  Tests that shared modules are accessible across apps.
  """
  def test_shared_module_access do
    tests = [
      # Core -> Storage
      fn -> Code.ensure_loaded(RubberDuckStorage.Repository) end,
      # Core -> Engines  
      fn -> Code.ensure_loaded(RubberDuckEngines.Engine) end,
      # Web -> Core
      fn -> Code.ensure_loaded(RubberDuckCore.ConversationManager) end,
      # Engines -> Core
      fn -> Code.ensure_loaded(RubberDuckCore.PubSub) end,
      # Storage -> Core (for schemas)
      fn -> Code.ensure_loaded(RubberDuckCore.Conversation) end
    ]
    
    Enum.all?(tests, fn test ->
      case test.() do
        {:module, _} -> true
        {:error, _} -> false
      end
    end)
  end

  @doc """
  Tests inter-app communication by sending messages through the PubSub system.
  """
  def test_inter_app_communication do
    topic = "test_inter_app_#{:rand.uniform(10000)}"
    test_pid = self()
    
    # Subscribe to test topic
    :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
    
    # Send a message from core
    :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, {:test_message, test_pid})
    
    # Wait for message
    receive do
      {:test_message, ^test_pid} -> true
    after
      1000 -> false
    end
  end

  @doc """
  Verifies all umbrella apps have proper mix.exs configuration.
  """
  def verify_umbrella_config do
    apps = [:rubber_duck_core, :rubber_duck_storage, :rubber_duck_engines, :rubber_duck_web]
    
    Enum.all?(apps, fn app ->
      # Check if app is loaded
      case Application.load(app) do
        :ok -> true
        {:error, {:already_loaded, ^app}} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Gets compilation time for each app to verify independent compilation.
  """
  def measure_app_compilation_times do
    apps = ["rubber_duck_core", "rubber_duck_storage", "rubber_duck_engines", "rubber_duck_web"]
    
    Enum.map(apps, fn app ->
      start_time = System.monotonic_time(:millisecond)
      {success, _output} = compile_app_independently(app)
      end_time = System.monotonic_time(:millisecond)
      
      {app, success, end_time - start_time}
    end)
  end
end