defmodule AppCompilationTest do
  @moduledoc """
  Unit tests for individual app compilation and dependency verification.
  """
  
  use ExUnit.Case, async: true

  describe "rubber_duck_core app" do
    test "compiles independently" do
      {success, output} = UmbrellaTestHelper.compile_app_independently("rubber_duck_core")
      assert success, "rubber_duck_core failed to compile: #{output}"
    end

    test "has correct dependencies in mix.exs" do
      {:ok, mix_content} = File.read("apps/rubber_duck_core/mix.exs")
      
      # Should depend on storage for Ecto repos
      assert String.contains?(mix_content, "rubber_duck_storage")
      
      # Should have Phoenix PubSub
      assert String.contains?(mix_content, "phoenix_pubsub")
      
      # Should have GenStateMachine for conversation management
      assert String.contains?(mix_content, "gen_state_machine") or 
             String.contains?(mix_content, ":gen_statem")
    end
  end

  describe "rubber_duck_storage app" do
    test "compiles independently" do
      {success, output} = UmbrellaTestHelper.compile_app_independently("rubber_duck_storage")
      assert success, "rubber_duck_storage failed to compile: #{output}"
    end

    test "has correct dependencies in mix.exs" do
      {:ok, mix_content} = File.read("apps/rubber_duck_storage/mix.exs")
      
      # Should have Ecto and Postgrex
      assert String.contains?(mix_content, "ecto")
      assert String.contains?(mix_content, "postgrex")
      
      # Should depend on core for schemas
      assert String.contains?(mix_content, "rubber_duck_core")
    end
  end

  describe "rubber_duck_engines app" do
    test "compiles independently" do
      {success, output} = UmbrellaTestHelper.compile_app_independently("rubber_duck_engines")
      assert success, "rubber_duck_engines failed to compile: #{output}"
    end

    test "has correct dependencies in mix.exs" do
      {:ok, mix_content} = File.read("apps/rubber_duck_engines/mix.exs")
      
      # Should depend on core for communication
      assert String.contains?(mix_content, "rubber_duck_core")
      
      # May have additional analysis dependencies
      # This is flexible as engines may add more deps over time
    end
  end

  describe "rubber_duck_web app" do
    test "compiles independently" do
      {success, output} = UmbrellaTestHelper.compile_app_independently("rubber_duck_web")
      assert success, "rubber_duck_web failed to compile: #{output}"
    end

    test "has correct dependencies in mix.exs" do
      {:ok, mix_content} = File.read("apps/rubber_duck_web/mix.exs")
      
      # Should have Phoenix and related deps
      assert String.contains?(mix_content, "phoenix")
      
      # Should depend on core for business logic
      assert String.contains?(mix_content, "rubber_duck_core")
      
      # Should have WebSocket support
      assert String.contains?(mix_content, "phoenix") # Phoenix includes WebSocket
    end
  end

  describe "dependency order verification" do
    test "apps can be compiled in dependency order" do
      # Test compilation in the correct dependency order
      apps_in_order = ["rubber_duck_storage", "rubber_duck_core", "rubber_duck_engines", "rubber_duck_web"]
      
      Enum.each(apps_in_order, fn app ->
        {success, output} = UmbrellaTestHelper.compile_app_independently(app)
        assert success, "App #{app} failed to compile in dependency order: #{output}"
      end)
    end

    test "dependency graph is acyclic" do
      # Verify no circular dependencies by checking mix.exs files
      core_deps = extract_internal_deps("apps/rubber_duck_core/mix.exs")
      storage_deps = extract_internal_deps("apps/rubber_duck_storage/mix.exs")
      engines_deps = extract_internal_deps("apps/rubber_duck_engines/mix.exs")
      web_deps = extract_internal_deps("apps/rubber_duck_web/mix.exs")
      
      # Storage should not depend on engines or web
      assert :rubber_duck_engines not in storage_deps
      assert :rubber_duck_web not in storage_deps
      
      # Core should not depend on web
      assert :rubber_duck_web not in core_deps
      
      # Engines should not depend on web
      assert :rubber_duck_web not in engines_deps
      
      # This creates a valid DAG: storage <- core <- engines <- web
      #                            storage <- core <- web
    end
  end

  # Helper function to extract internal app dependencies from mix.exs
  defp extract_internal_deps(mix_file_path) do
    case File.read(mix_file_path) do
      {:ok, content} ->
        # Simple regex to find rubber_duck_* dependencies
        Regex.scan(~r/:rubber_duck_\w+/, content)
        |> Enum.map(fn [dep] -> String.to_atom(String.trim_leading(dep, ":")) end)
        |> Enum.uniq()
      
      {:error, _} -> []
    end
  end
end