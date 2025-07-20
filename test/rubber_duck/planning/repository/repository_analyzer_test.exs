defmodule RubberDuck.Planning.Repository.RepositoryAnalyzerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Repository.RepositoryAnalyzer
  alias RubberDuck.Planning.Repository.DependencyGraph
  
  import ExUnit.CaptureLog
  
  describe "analyze/2" do
    test "analyzes a simple Elixir project structure" do
      # Create a temporary directory with sample files
      tmp_dir = System.tmp_dir!() |> Path.join("repo_analyzer_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        # Create mix.exs with unique project name
        unique_id = :rand.uniform(100000)
        mix_content = """
        defmodule TestProject#{unique_id}.MixProject do
          use Mix.Project
          
          def project do
            [
              app: :test_project_#{unique_id},
              version: "0.1.0",
              deps: deps()
            ]
          end
          
          defp deps do
            [
              {:phoenix, "~> 1.7"},
              {:ecto, "~> 3.0"}
            ]
          end
        end
        """
        File.write!(Path.join(tmp_dir, "mix.exs"), mix_content)
        
        # Create lib directory with sample module
        lib_dir = Path.join(tmp_dir, "lib")
        File.mkdir_p!(lib_dir)
        
        sample_module = """
        defmodule TestProject.MyModule do
          use GenServer
          alias TestProject.OtherModule
          import Ecto.Query
          
          def start_link(opts) do
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          end
          
          def init(state) do
            {:ok, state}
          end
          
          def handle_call(:get_state, _from, state) do
            {:reply, state, state}
          end
        end
        """
        File.write!(Path.join(lib_dir, "my_module.ex"), sample_module)
        
        # Create test directory
        test_dir = Path.join(tmp_dir, "test")
        File.mkdir_p!(test_dir)
        
        test_content = """
        defmodule TestProject.MyModuleTest do
          use ExUnit.Case
          
          alias TestProject.MyModule
          
          test "starts correctly" do
            assert {:ok, _pid} = MyModule.start_link([])
          end
        end
        """
        File.write!(Path.join(test_dir, "my_module_test.exs"), test_content)
        
        # Analyze the repository
        assert {:ok, analysis} = RepositoryAnalyzer.analyze(tmp_dir)
        
        # Verify structure analysis
        assert analysis.structure.type == :mix_project
        assert analysis.structure.root_path == tmp_dir
        assert length(analysis.structure.mix_projects) == 1
        assert length(analysis.structure.deps) == 2
        
        # Verify file analysis
        assert length(analysis.files) >= 2  # at least mix.exs and my_module.ex
        
        lib_file = Enum.find(analysis.files, &String.ends_with?(&1.path, "my_module.ex"))
        assert lib_file.type == :lib
        assert length(lib_file.modules) == 1
        
        module = hd(lib_file.modules)
        assert module.name == "TestProject.MyModule"
        assert module.type == :genserver
        assert "TestProject.OtherModule" in module.aliases
        assert "Ecto.Query" in module.imports
        
        # Verify dependency graph was built
        assert %DependencyGraph{} = analysis.dependencies
        
        # Verify patterns were detected
        assert is_list(analysis.patterns)
        
      after
        File.rm_rf!(tmp_dir)
      end
    end
    
    test "handles parse errors gracefully" do
      tmp_dir = System.tmp_dir!() |> Path.join("repo_analyzer_parse_error_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        # Create a file with invalid syntax
        invalid_file = Path.join(tmp_dir, "invalid.ex")
        File.write!(invalid_file, "defmodule Invalid do\n  # missing end")
        
        log = capture_log(fn ->
          assert {:ok, analysis} = RepositoryAnalyzer.analyze(tmp_dir)
          
          invalid_analysis = Enum.find(analysis.files, &(&1.path == invalid_file))
          assert invalid_analysis.modules == []
          assert invalid_analysis.complexity == :simple
        end)
        
        # Should not crash, just log warnings
        refute String.contains?(log, "ERROR")
      after
        File.rm_rf!(tmp_dir)
      end
    end
    
    test "detects umbrella project structure" do
      tmp_dir = System.tmp_dir!() |> Path.join("umbrella_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)
      
      try do
        # Create apps directory with sub-projects
        apps_dir = Path.join(tmp_dir, "apps")
        File.mkdir_p!(apps_dir)
        
        app1_dir = Path.join(apps_dir, "app1")
        app2_dir = Path.join(apps_dir, "app2")
        File.mkdir_p!(app1_dir)
        File.mkdir_p!(app2_dir)
        
        assert {:ok, analysis} = RepositoryAnalyzer.analyze(tmp_dir)
        
        assert analysis.structure.type == :umbrella_project
        assert length(analysis.structure.mix_projects) == 2
        
        umbrella_pattern = Enum.find(analysis.patterns, &(&1.type == :umbrella_project))
        assert umbrella_pattern
        assert umbrella_pattern.confidence == 1.0
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
  
  describe "analyze_change_impact/2" do
    test "finds affected files through dependency graph" do
      # Create a mock analysis result
      analysis = %{
        dependencies: create_mock_dependency_graph()
      }
      
      assert {:ok, affected} = RepositoryAnalyzer.analyze_change_impact(analysis, ["file1.ex"])
      assert "file2.ex" in affected
      assert "file3.ex" in affected
    end
  end
  
  describe "get_compilation_order/1" do
    test "returns topological sort of dependencies" do
      analysis = %{
        dependencies: create_mock_dependency_graph()
      }
      
      assert {:ok, order} = RepositoryAnalyzer.get_compilation_order(analysis)
      assert is_list(order)
      assert length(order) > 0
    end
  end
  
  describe "find_associated_tests/2" do
    test "finds test files for implementation files" do
      files = [
        %{path: "lib/my_module.ex", type: :lib},
        %{path: "lib/other_module.ex", type: :lib},
        %{path: "test/my_module_test.exs", type: :test},
        %{path: "test/integration_test.exs", type: :test}
      ]
      
      analysis = %{files: files}
      
      tests = RepositoryAnalyzer.find_associated_tests(analysis, ["lib/my_module.ex"])
      assert "test/my_module_test.exs" in tests
      refute "test/integration_test.exs" in tests
    end
  end
  
  # Helper functions
  
  defp create_mock_dependency_graph do
    # Create a simple dependency graph for testing
    file_analyses = [
      %{
        path: "file1.ex",
        modules: [%{
          name: "Module1",
          imports: ["Module2"],
          aliases: [],
          uses: []
        }]
      },
      %{
        path: "file2.ex", 
        modules: [%{
          name: "Module2",
          imports: ["Module3"],
          aliases: [],
          uses: []
        }]
      },
      %{
        path: "file3.ex",
        modules: [%{
          name: "Module3",
          imports: [],
          aliases: [],
          uses: []
        }]
      }
    ]
    
    {:ok, graph} = DependencyGraph.build(file_analyses)
    graph
  end
end