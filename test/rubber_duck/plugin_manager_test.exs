defmodule RubberDuck.PluginManagerTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.PluginManager
  alias RubberDuck.ExamplePlugins.{TextEnhancer, WordCounter, TextProcessor}
  
  setup do
    # Clean up any registered plugins
    PluginManager.list_plugins()
    |> Enum.each(fn %{name: name} ->
      PluginManager.unregister_plugin(name)
    end)
    
    :ok
  end
  
  describe "plugin registration" do
    test "registers a valid plugin" do
      assert {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer)
      
      plugins = PluginManager.list_plugins()
      assert length(plugins) == 1
      assert hd(plugins).name == :text_enhancer
    end
    
    test "prevents duplicate registration" do
      assert {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer)
      assert {:error, :already_registered} = PluginManager.register_plugin(TextEnhancer)
    end
    
    test "registers plugin with config" do
      config = [prefix: "[[", suffix: "]]"]
      assert {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer, config)
      
      {:ok, info} = PluginManager.get_plugin(:text_enhancer)
      assert info.config == config
    end
    
    test "unregisters a plugin" do
      {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer)
      assert :ok = PluginManager.unregister_plugin(:text_enhancer)
      assert PluginManager.list_plugins() == []
    end
  end
  
  describe "plugin lifecycle" do
    setup do
      {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer)
      :ok
    end
    
    test "starts a plugin" do
      assert :ok = PluginManager.start_plugin(:text_enhancer)
      {:ok, info} = PluginManager.get_plugin(:text_enhancer)
      assert info.status == :started
    end
    
    test "stops a plugin" do
      :ok = PluginManager.start_plugin(:text_enhancer)
      assert :ok = PluginManager.stop_plugin(:text_enhancer)
      {:ok, info} = PluginManager.get_plugin(:text_enhancer)
      assert info.status == :stopped
    end
    
    test "prevents starting an already started plugin" do
      :ok = PluginManager.start_plugin(:text_enhancer)
      assert {:error, :already_started} = PluginManager.start_plugin(:text_enhancer)
    end
    
    test "prevents stopping a non-started plugin" do
      assert {:error, :not_started} = PluginManager.stop_plugin(:text_enhancer)
    end
  end
  
  describe "plugin execution" do
    setup do
      {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer, [prefix: "->", suffix: "<-"])
      {:ok, :word_counter} = PluginManager.register_plugin(WordCounter)
      :ok = PluginManager.start_plugin(:text_enhancer)
      :ok = PluginManager.start_plugin(:word_counter)
      :ok
    end
    
    test "executes a plugin" do
      assert {:ok, "->hello<-"} = PluginManager.execute(:text_enhancer, "hello")
    end
    
    test "maintains plugin state across executions" do
      assert {:ok, %{word_count: 2, total_processed: 2}} = 
        PluginManager.execute(:word_counter, "hello world")
        
      assert {:ok, %{word_count: 3, total_processed: 5}} = 
        PluginManager.execute(:word_counter, "one two three")
    end
    
    test "returns error for non-existent plugin" do
      assert {:error, :not_found} = PluginManager.execute(:non_existent, "input")
    end
    
    test "returns error for stopped plugin" do
      PluginManager.stop_plugin(:text_enhancer)
      assert {:error, :not_started} = PluginManager.execute(:text_enhancer, "input")
    end
  end
  
  describe "plugin discovery" do
    test "finds plugins by supported type" do
      {:ok, _} = PluginManager.register_plugin(TextEnhancer)
      {:ok, _} = PluginManager.register_plugin(WordCounter)
      :ok = PluginManager.start_plugin(:text_enhancer)
      :ok = PluginManager.start_plugin(:word_counter)
      
      text_plugins = PluginManager.find_plugins_by_type(:text)
      assert :text_enhancer in text_plugins
      assert :word_counter in text_plugins
      
      any_plugins = PluginManager.find_plugins_by_type(:any)
      assert :text_enhancer in any_plugins
    end
  end
  
  describe "plugin information" do
    test "gets plugin information" do
      {:ok, :text_enhancer} = PluginManager.register_plugin(TextEnhancer)
      
      assert {:ok, info} = PluginManager.get_plugin(:text_enhancer)
      assert info.name == :text_enhancer
      assert info.version == "1.0.0"
      assert info.module == TextEnhancer
      assert info.status == :loaded
    end
    
    test "returns error for non-existent plugin" do
      assert {:error, :not_found} = PluginManager.get_plugin(:non_existent)
    end
  end
end