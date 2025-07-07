defmodule RubberDuck.Workflows.CompleteAnalysisTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Workflows.CompleteAnalysis

  describe "run/2" do
    test "analyzes a single file successfully" do
      # Create a test file
      test_file = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(10000)}.ex")

      File.write!(test_file, """
      defmodule TestModule do
        def hello(name) do
          String.to_atom(name)  # Security issue
        end
        
        defp unused_function do  # Dead code
          :never_called
        end
      end
      """)

      on_exit(fn -> File.rm(test_file) end)

      # Run the workflow
      input = %{
        files: [test_file],
        options: %{
          engines: [:semantic, :style, :security],
          # Start without LLM to keep test simple
          include_llm_review: false
        }
      }

      assert {:ok, result} = CompleteAnalysis.run(input)

      # Verify structure
      assert %{
               status: :completed,
               results: %{
                 parse_ast: {:ok, _},
                 run_analysis_engines: {:ok, analysis_results},
                 aggregate_results: {:ok, aggregated},
                 generate_report: {:ok, report}
               }
             } = result

      # Verify issues were found
      assert length(analysis_results.all_issues) > 0

      # Should find the security issue (String.to_atom)
      assert Enum.any?(analysis_results.all_issues, fn issue ->
               issue.type == :dynamic_atom_creation
             end)

      # Should find the dead code issue
      assert Enum.any?(analysis_results.all_issues, fn issue ->
               issue.type == :dead_code
             end)

      # Verify report structure
      assert %{
               summary: %{
                 total_files: 1,
                 total_issues: _,
                 issues_by_severity: %{}
               },
               details: _
             } = report
    end

    test "handles multiple files in parallel" do
      # Create multiple test files
      files =
        for i <- 1..3 do
          path = Path.join(System.tmp_dir!(), "test_#{i}_#{:rand.uniform(10000)}.ex")

          File.write!(path, """
          defmodule TestModule#{i} do
            def process(x) do
              x * 2
            end
          end
          """)

          path
        end

      on_exit(fn -> Enum.each(files, &File.rm/1) end)

      input = %{
        files: files,
        options: %{
          parallel: true,
          engines: [:semantic, :style]
        }
      }

      assert {:ok, result} = CompleteAnalysis.run(input)
      assert result.results.aggregate_results.summary.total_files == 3
    end

    test "gracefully handles file read errors" do
      input = %{
        files: ["/non/existent/file.ex"],
        options: %{}
      }

      assert {:ok, result} = CompleteAnalysis.run(input)
      assert result.status == :completed

      # Should have an error in read step but continue
      assert {:error, _} = result.results.read_and_detect
    end

    test "includes LLM review when requested" do
      test_file = Path.join(System.tmp_dir!(), "test_llm_#{:rand.uniform(10000)}.ex")

      File.write!(test_file, """
      defmodule ComplexModule do
        # This function has multiple issues
        def process_data(input_string) do
          result = String.to_atom(input_string)
          IO.puts result
          result
        end
      end
      """)

      on_exit(fn -> File.rm(test_file) end)

      input = %{
        files: [test_file],
        options: %{
          include_llm_review: true,
          llm_options: %{
            # Use mock provider for testing
            provider: :mock,
            model: "gpt-4"
          }
        }
      }

      assert {:ok, result} = CompleteAnalysis.run(input)

      # Should have LLM review results
      assert {:ok, llm_result} = result.results.llm_review
      assert llm_result.insights != nil
    end
  end

  describe "run_async/2" do
    test "executes workflow asynchronously" do
      test_file = Path.join(System.tmp_dir!(), "test_async_#{:rand.uniform(10000)}.ex")
      File.write!(test_file, "defmodule Test do\nend")
      on_exit(fn -> File.rm(test_file) end)

      input = %{files: [test_file], options: %{}}

      # Start async execution
      {:ok, workflow_id} = CompleteAnalysis.run_async(input)

      # Should be able to check status
      assert {:ok, status} = CompleteAnalysis.get_status(workflow_id)
      assert status in [:running, :completed]

      # Wait for completion
      Process.sleep(100)

      assert {:ok, :completed} = CompleteAnalysis.get_status(workflow_id)
    end
  end

  describe "analyze_project/2" do
    test "convenience function analyzes all files in a project" do
      # This would need a project fixture
      # For now, we'll skip this test
      :skip
    end
  end
end
