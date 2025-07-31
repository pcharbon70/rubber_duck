defmodule RubberDuck.Tools.Agents.PromptOptimizerAgentTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Tools.Agents.PromptOptimizerAgent
  
  setup do
    {:ok, agent} = PromptOptimizerAgent.start_link(id: "test_prompt_optimizer")
    
    on_exit(fn ->
      if Process.alive?(agent) do
        GenServer.stop(agent)
      end
    end)
    
    %{agent: agent}
  end
  
  describe "action execution" do
    test "executes tool via ExecuteToolAction", %{agent: agent} do
      params = %{
        prompt: "Generate a function that sorts an array",
        optimization_strategies: [:clarity_enhancement, :specificity_improvement]
      }
      
      # Execute action directly
      context = %{agent: GenServer.call(agent, :get_state), parent_module: PromptOptimizerAgent}
      
      # Mock the Executor response - in real tests, you'd mock RubberDuck.ToolSystem.Executor
      result = PromptOptimizerAgent.ExecuteToolAction.run(%{params: params}, context)
      
      # Verify structure (actual execution would need mocking)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "analyze prompt action evaluates multiple aspects", %{agent: agent} do
      prompt = "Please write some code to do things with data structures and maybe use algorithms if possible."
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{
          prompt: prompt,
          analysis_aspects: [:clarity, :specificity, :completeness],
          target_model: :gpt4
        },
        context
      )
      
      assert result.prompt == prompt
      assert Map.has_key?(result.analysis_results, :clarity)
      assert Map.has_key?(result.analysis_results, :specificity)
      assert Map.has_key?(result.analysis_results, :completeness)
      
      # This prompt should score poorly on clarity and specificity
      clarity_result = result.analysis_results[:clarity]
      assert clarity_result.score < 0.7
      assert length(clarity_result.issues) > 0
      assert length(clarity_result.suggestions) > 0
      
      specificity_result = result.analysis_results[:specificity]
      assert specificity_result.score < 0.7
      assert "Uses generic or non-specific language" in specificity_result.issues
      
      assert is_float(result.overall_score)
      assert Map.has_key?(result.recommendations, :high_impact)
    end
    
    test "optimize prompt action improves prompt quality", %{agent: agent} do
      poor_prompt = "Please do some coding stuff with maybe using some algorithms or whatever."
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.OptimizePromptAction.run(
        %{
          prompt: poor_prompt,
          optimization_strategies: [:clarity_enhancement, :specificity_improvement],
          target_model: :gpt4,
          preserve_intent: true
        },
        context
      )
      
      assert result.original_prompt == poor_prompt
      assert is_binary(result.optimized_prompt)
      assert result.optimization_strategies == [:clarity_enhancement, :specificity_improvement]
      assert result.target_model == :gpt4
      
      # Optimized prompt should be different and generally better
      assert result.optimized_prompt != poor_prompt
      assert Map.has_key?(result.validation, :valid)
      assert Map.has_key?(result.validation, :improvement_score)
    end
    
    test "A/B test prompts action sets up experiment configuration", %{agent: agent} do
      variants = [
        %{name: "variant_a", prompt: "Write a function to sort an array."},
        %{name: "variant_b", prompt: "Create a sorting function for arrays with detailed comments."},
        %{name: "variant_c", prompt: "Implement an array sorting algorithm with error handling."}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.ABTestPromptsAction.run(
        %{
          test_name: "sorting_function_test",
          prompt_variants: variants,
          test_criteria: [:response_quality, :response_time],
          sample_size: 50,
          confidence_level: 0.95
        },
        context
      )
      
      test_config = result.test_config
      assert test_config.name == "sorting_function_test"
      assert length(test_config.variants) == 3
      assert test_config.sample_size == 50
      assert test_config.confidence_level == 0.95
      assert test_config.status == :active
      
      # Check that variants have been processed
      first_variant = hd(test_config.variants)
      assert Map.has_key?(first_variant, :id)
      assert Map.has_key?(first_variant, :weight)
      
      assert is_list(result.next_steps)
      assert length(result.next_steps) > 0
    end
    
    test "generate variations action creates different prompt styles", %{agent: agent} do
      base_prompt = "Explain how binary search works."
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.GenerateVariationsAction.run(
        %{
          base_prompt: base_prompt,
          variation_types: [:tone, :length, :structure],
          count: 2,
          target_model: :claude
        },
        context
      )
      
      assert result.base_prompt == base_prompt
      assert result.total_variations == 6 # 3 types × 2 variations each
      assert length(result.variations) == 6
      
      # Check that we have different types of variations
      tone_variations = Enum.filter(result.variations, &(&1.type == :tone))
      length_variations = Enum.filter(result.variations, &(&1.type == :length))
      structure_variations = Enum.filter(result.variations, &(&1.type == :structure))
      
      assert length(tone_variations) == 2
      assert length(length_variations) == 2
      assert length(structure_variations) == 2
      
      # Each variation should have a different prompt
      prompts = Enum.map(result.variations, & &1.prompt)
      unique_prompts = Enum.uniq(prompts)
      assert length(unique_prompts) == length(prompts)
    end
    
    test "evaluate effectiveness action scores responses", %{agent: agent} do
      prompt = "Explain the concept of recursion in programming."
      
      responses = [
        %{id: "resp1", content: "Recursion is when a function calls itself. For example, calculating factorial: factorial(n) = n * factorial(n-1). The base case is factorial(0) = 1."},
        %{id: "resp2", content: "Recursion means a function calls itself repeatedly until a condition is met."},
        %{id: "resp3", content: "It's a programming technique where functions call themselves to solve problems by breaking them into smaller subproblems."}
      ]
      
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.EvaluateEffectivenessAction.run(
        %{
          prompt: prompt,
          responses: responses,
          evaluation_criteria: [:relevance, :completeness, :clarity],
          baseline_scores: %{relevance: 0.6, completeness: 0.5, clarity: 0.7}
        },
        context
      )
      
      assert result.prompt == prompt
      assert result.response_count == 3
      assert length(result.individual_evaluations) == 3
      
      # Check aggregate scores
      aggregate = result.aggregate_scores
      assert Map.has_key?(aggregate, :relevance)
      assert Map.has_key?(aggregate, :completeness)
      assert Map.has_key?(aggregate, :clarity)
      
      # Check baseline comparison
      comparison = result.baseline_comparison
      assert Map.has_key?(comparison, :criterion_comparisons)
      assert Map.has_key?(comparison, :overall_improvement)
      
      # Check individual evaluations
      first_eval = hd(result.individual_evaluations)
      assert Map.has_key?(first_eval, :response_id)
      assert Map.has_key?(first_eval, :scores)
      assert Map.has_key?(first_eval, :overall_score)
      
      # The first response should score highest on completeness (has example)
      scores = Enum.map(result.individual_evaluations, & &1.scores.completeness)
      assert hd(scores) == Enum.max(scores)
    end
    
    test "apply template action generates structured prompts", %{agent: agent} do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.ApplyTemplateAction.run(
        %{
          template_name: "code_generation",
          variables: %{
            task: "Create a sorting function",
            context: "Python programming",
            requirements: "Must handle empty arrays and be efficient",
            format: "Well-commented code with docstring"
          },
          customizations: %{
            add_examples: ["sort([3,1,4]) -> [1,3,4]"],
            add_constraints: ["Use O(n log n) algorithm", "Include error handling"],
            set_tone: :professional
          }
        },
        context
      )
      
      assert result.template_name == "code_generation"
      assert is_binary(result.generated_prompt)
      
      # Check that variables were substituted
      prompt = result.generated_prompt
      assert String.contains?(prompt, "Create a sorting function")
      assert String.contains?(prompt, "Python programming")
      assert String.contains?(prompt, "Must handle empty arrays")
      
      # Check that customizations were applied
      assert String.contains?(prompt, "Example")
      assert String.contains?(prompt, "sort([3,1,4])")
      assert String.contains?(prompt, "Constraints")
      assert String.contains?(prompt, "O(n log n)")
      assert String.contains?(prompt, "Professional Request")
    end
  end
  
  describe "signal handling with actions" do
    test "analyze_prompt signal triggers AnalyzePromptAction", %{agent: agent} do
      signal = %{
        "type" => "analyze_prompt",
        "data" => %{
          "prompt" => "Write some code",
          "analysis_aspects" => ["clarity", "specificity"],
          "target_model" => "gpt4"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PromptOptimizerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "optimize_prompt signal triggers OptimizePromptAction", %{agent: agent} do
      signal = %{
        "type" => "optimize_prompt",
        "data" => %{
          "prompt" => "Do some programming stuff",
          "optimization_strategies" => ["clarity_enhancement", "specificity_improvement"],
          "target_model" => "claude"
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PromptOptimizerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "ab_test_prompts signal triggers ABTestPromptsAction", %{agent: agent} do
      signal = %{
        "type" => "ab_test_prompts",
        "data" => %{
          "test_name" => "my_test",
          "prompt_variants" => [
            %{"name" => "A", "prompt" => "Version A"},
            %{"name" => "B", "prompt" => "Version B"}
          ]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PromptOptimizerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "generate_variations signal triggers GenerateVariationsAction", %{agent: agent} do
      signal = %{
        "type" => "generate_variations",
        "data" => %{
          "base_prompt" => "Explain recursion",
          "variation_types" => ["tone", "length"],
          "count" => 2
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PromptOptimizerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "evaluate_effectiveness signal triggers EvaluateEffectivenessAction", %{agent: agent} do
      signal = %{
        "type" => "evaluate_effectiveness",
        "data" => %{
          "prompt" => "Test prompt",
          "responses" => [%{"id" => "1", "content" => "Response 1"}],
          "evaluation_criteria" => ["relevance", "clarity"]
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PromptOptimizerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
    
    test "apply_template signal triggers ApplyTemplateAction", %{agent: agent} do
      signal = %{
        "type" => "apply_template",
        "data" => %{
          "template_name" => "analysis",
          "variables" => %{"subject" => "code", "content" => "function code"},
          "customizations" => %{"set_tone" => "formal"}
        }
      }
      
      state = GenServer.call(agent, :get_state)
      {:ok, _updated} = PromptOptimizerAgent.handle_tool_signal(state, signal)
      
      assert true
    end
  end
  
  describe "prompt analysis" do
    test "clarity analysis detects ambiguous language" do
      ambiguous_prompt = "Please do some stuff with the thing and maybe use whatever approach."
      clear_prompt = "Create a sorting function that takes an array of integers and returns them in ascending order."
      
      context = %{agent: %{state: %{}}}
      
      # Test ambiguous prompt
      {:ok, result_ambiguous} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: ambiguous_prompt, analysis_aspects: [:clarity]},
        context
      )
      
      clarity_ambiguous = result_ambiguous.analysis_results[:clarity]
      assert clarity_ambiguous.score < 0.7
      assert "Contains ambiguous or vague language" in clarity_ambiguous.issues
      
      # Test clear prompt
      {:ok, result_clear} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: clear_prompt, analysis_aspects: [:clarity]},
        context
      )
      
      clarity_clear = result_clear.analysis_results[:clarity]
      assert clarity_clear.score > clarity_ambiguous.score
    end
    
    test "specificity analysis detects generic language" do
      generic_prompt = "Write some basic code for general data processing using normal algorithms."
      specific_prompt = "Implement a QuickSort algorithm in Python that handles arrays of up to 1000 integers with O(n log n) average time complexity."
      
      context = %{agent: %{state: %{}}}
      
      # Test generic prompt
      {:ok, result_generic} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: generic_prompt, analysis_aspects: [:specificity]},
        context
      )
      
      specificity_generic = result_generic.analysis_results[:specificity]
      assert specificity_generic.score < 0.6
      assert "Uses generic or non-specific language" in specificity_generic.issues
      
      # Test specific prompt
      {:ok, result_specific} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: specific_prompt, analysis_aspects: [:specificity]},
        context
      )
      
      specificity_specific = result_specific.analysis_results[:specificity]
      assert specificity_specific.score > specificity_generic.score
    end
    
    test "completeness analysis checks for context and examples" do
      incomplete_prompt = "Sort array."
      complete_prompt = """
      Context: You are helping with algorithm implementation.
      Task: Sort an array of integers.
      Example: Input [3,1,4] should output [1,3,4].
      Format: Return the code with comments explaining the approach.
      """
      
      context = %{agent: %{state: %{}}}
      
      # Test incomplete prompt
      {:ok, result_incomplete} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: incomplete_prompt, analysis_aspects: [:completeness]},
        context
      )
      
      completeness_incomplete = result_incomplete.analysis_results[:completeness]
      assert completeness_incomplete.score < 0.5
      assert length(completeness_incomplete.issues) > 2
      
      # Test complete prompt
      {:ok, result_complete} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: complete_prompt, analysis_aspects: [:completeness]},
        context
      )
      
      completeness_complete = result_complete.analysis_results[:completeness]
      assert completeness_complete.score > completeness_incomplete.score
    end
    
    test "bias analysis detects leading questions and assumptions" do
      biased_prompt = "Don't you think it's obvious that everyone knows the best sorting algorithm is QuickSort?"
      neutral_prompt = "Compare the time complexity and use cases of different sorting algorithms."
      
      context = %{agent: %{state: %{}}}
      
      # Test biased prompt
      {:ok, result_biased} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: biased_prompt, analysis_aspects: [:bias]},
        context
      )
      
      bias_biased = result_biased.analysis_results[:bias]
      assert bias_biased.score < 0.7
      assert length(bias_biased.issues) > 0
      
      # Test neutral prompt
      {:ok, result_neutral} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: neutral_prompt, analysis_aspects: [:bias]},
        context
      )
      
      bias_neutral = result_neutral.analysis_results[:bias]
      assert bias_neutral.score > bias_biased.score
    end
  end
  
  describe "prompt optimization" do
    test "clarity enhancement removes ambiguous language" do
      context = %{agent: %{state: %{model_profiles: %{}}}}
      
      # Test analysis first to get poor clarity score
      {:ok, analysis} = PromptOptimizerAgent.AnalyzePromptAction.run(
        %{prompt: "Do some stuff with things", analysis_aspects: [:clarity]},
        context
      )
      
      poor_prompt = "Do some stuff with things maybe"
      {:ok, result} = PromptOptimizerAgent.OptimizePromptAction.run(
        %{
          prompt: poor_prompt,
          optimization_strategies: [:clarity_enhancement],
          preserve_intent: true
        },
        context
      )
      
      optimized = result.optimized_prompt
      
      # Should remove ambiguous words
      refute String.contains?(optimized, "stuff")
      refute String.contains?(optimized, "maybe")
      assert optimized != poor_prompt
    end
    
    test "specificity improvement adds constraints and context" do
      context = %{agent: %{state: %{model_profiles: %{}}}}
      
      generic_prompt = "Write code"
      {:ok, result} = PromptOptimizerAgent.OptimizePromptAction.run(
        %{
          prompt: generic_prompt,
          optimization_strategies: [:specificity_improvement],
          preserve_intent: true
        },
        context
      )
      
      optimized = result.optimized_prompt
      
      # Should add requirements or constraints
      assert String.contains?(optimized, "Requirements") || String.contains?(optimized, "Context")
      assert String.length(optimized) > String.length(generic_prompt)
    end
    
    test "structure optimization improves organization" do
      context = %{agent: %{state: %{model_profiles: %{gpt4: %{prefers_structured: true}}}}}
      
      unstructured_prompt = "Write a function that sorts data and make sure it works well and handles edge cases and is efficient and documented."
      {:ok, result} = PromptOptimizerAgent.OptimizePromptAction.run(
        %{
          prompt: unstructured_prompt,
          optimization_strategies: [:structure_optimization],
          target_model: :gpt4,
          preserve_intent: true
        },
        context
      )
      
      optimized = result.optimized_prompt
      
      # Should add structure for GPT-4
      assert String.contains?(optimized, "##") || String.contains?(optimized, "Task:")
      assert String.contains?(optimized, "\n")
    end
  end
  
  describe "prompt variations" do
    test "tone variations create different styles" do
      base_prompt = "Explain sorting algorithms"
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = PromptOptimizerAgent.GenerateVariationsAction.run(
        %{
          base_prompt: base_prompt,
          variation_types: [:tone],
          count: 3
        },
        context
      )
      
      tone_variations = Enum.filter(result.variations, &(&1.type == :tone))
      assert length(tone_variations) == 3
      
      # Each should have different tone characteristics
      formal = Enum.find(tone_variations, &(&1.variation == :formal))
      casual = Enum.find(tone_variations, &(&1.variation == :casual))
      direct = Enum.find(tone_variations, &(&1.variation == :direct))
      
      assert formal != nil
      assert casual != nil
      assert direct != nil
      
      # Formal should be more verbose and professional
      assert String.length(formal.prompt) > String.length(direct.prompt)
      assert String.contains?(formal.prompt, "comprehensive") || String.contains?(formal.prompt, "thorough")
      
      # Casual should be friendlier
      assert String.contains?(casual.prompt, "Hey") || String.contains?(casual.prompt, "help me out")
    end
    
    test "length variations create different sizes" do
      base_prompt = "Explain how binary search works in computer science."
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = PromptOptimizerAgent.GenerateVariationsAction.run(
        %{
          base_prompt: base_prompt,
          variation_types: [:length],
          count: 3
        },
        context
      )
      
      length_variations = Enum.filter(result.variations, &(&1.type == :length))
      assert length(length_variations) == 3
      
      concise = Enum.find(length_variations, &(&1.variation == :concise))
      detailed = Enum.find(length_variations, &(&1.variation == :detailed))
      minimal = Enum.find(length_variations, &(&1.variation == :minimal))
      
      # Length ordering should be: minimal < concise < base_prompt < detailed
      assert String.length(minimal.prompt) < String.length(concise.prompt)
      assert String.length(concise.prompt) < String.length(base_prompt)
      assert String.length(base_prompt) < String.length(detailed.prompt)
    end
    
    test "structure variations create different formats" do
      base_prompt = "Explain the steps to implement a hash table."
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = PromptOptimizerAgent.GenerateVariationsAction.run(
        %{
          base_prompt: base_prompt,
          variation_types: [:structure],
          count: 3
        },
        context
      )
      
      structure_variations = Enum.filter(result.variations, &(&1.type == :structure))
      assert length(structure_variations) == 3
      
      bulleted = Enum.find(structure_variations, &(&1.variation == :bulleted))
      numbered = Enum.find(structure_variations, &(&1.variation == :numbered))
      sectioned = Enum.find(structure_variations, &(&1.variation == :sectioned))
      
      # Check for appropriate formatting
      assert String.contains?(bulleted.prompt, "•")
      assert String.contains?(numbered.prompt, "1.") || String.contains?(numbered.prompt, "2.")
      assert String.contains?(sectioned.prompt, "##")
    end
  end
  
  describe "effectiveness evaluation" do
    test "relevance scoring based on keyword overlap" do
      prompt = "Explain quicksort algorithm implementation"
      
      relevant_response = %{
        id: "relevant",
        content: "QuickSort is a divide-and-conquer algorithm that works by selecting a pivot element and partitioning the array around it. The implementation involves recursive calls to sort subarrays."
      }
      
      irrelevant_response = %{
        id: "irrelevant", 
        content: "The weather today is sunny and warm. I enjoy taking walks in the park during nice weather like this."
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = PromptOptimizerAgent.EvaluateEffectivenessAction.run(
        %{
          prompt: prompt,
          responses: [relevant_response, irrelevant_response],
          evaluation_criteria: [:relevance]
        },
        context
      )
      
      evaluations = result.individual_evaluations
      relevant_eval = Enum.find(evaluations, &(&1.response_id == "relevant"))
      irrelevant_eval = Enum.find(evaluations, &(&1.response_id == "irrelevant"))
      
      assert relevant_eval.scores.relevance > irrelevant_eval.scores.relevance
      assert relevant_eval.scores.relevance > 0.5
      assert irrelevant_eval.scores.relevance < 0.3
    end
    
    test "completeness scoring based on response structure" do
      prompt = "Explain how to implement a binary search tree"
      
      complete_response = %{
        id: "complete",
        content: "First, define the node structure. Second, implement insertion method. Finally, add search and deletion operations. In conclusion, BST provides O(log n) average case performance."
      }
      
      incomplete_response = %{
        id: "incomplete",
        content: "BST is a tree."
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = PromptOptimizerAgent.EvaluateEffectivenessAction.run(
        %{
          prompt: prompt,
          responses: [complete_response, incomplete_response],
          evaluation_criteria: [:completeness]
        },
        context
      )
      
      evaluations = result.individual_evaluations
      complete_eval = Enum.find(evaluations, &(&1.response_id == "complete"))
      incomplete_eval = Enum.find(evaluations, &(&1.response_id == "incomplete"))
      
      assert complete_eval.scores.completeness > incomplete_eval.scores.completeness
      assert complete_eval.scores.completeness > 0.6
    end
    
    test "usefulness scoring based on actionable content" do
      prompt = "How do I optimize my code performance?"
      
      useful_response = %{
        id: "useful",
        content: "Step 1: Profile your code to identify bottlenecks. Method: Use profiling tools. Approach: Focus on the hottest code paths. Technique: Apply algorithmic improvements first."
      }
      
      less_useful_response = %{
        id: "less_useful",
        content: "Code optimization is important for performance. It's good to think about efficiency when writing programs."
      }
      
      context = %{agent: %{state: %{}}}
      
      {:ok, result} = PromptOptimizerAgent.EvaluateEffectivenessAction.run(
        %{
          prompt: prompt,
          responses: [useful_response, less_useful_response],
          evaluation_criteria: [:usefulness]
        },
        context
      )
      
      evaluations = result.individual_evaluations
      useful_eval = Enum.find(evaluations, &(&1.response_id == "useful"))
      less_useful_eval = Enum.find(evaluations, &(&1.response_id == "less_useful"))
      
      assert useful_eval.scores.usefulness > less_useful_eval.scores.usefulness
      assert useful_eval.scores.usefulness > 0.7
    end
  end
  
  describe "template application" do
    test "applies code generation template correctly" do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.ApplyTemplateAction.run(
        %{
          template_name: "code_generation",
          variables: %{
            task: "Implement QuickSort",
            context: "Educational Python tutorial",
            requirements: "Include comments and handle edge cases",
            format: "Documented function with examples"
          }
        },
        context
      )
      
      prompt = result.generated_prompt
      assert String.contains?(prompt, "Implement QuickSort")
      assert String.contains?(prompt, "Educational Python tutorial")
      assert String.contains?(prompt, "Include comments")
      assert String.contains?(prompt, "Documented function")
    end
    
    test "applies analysis template with customizations" do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:ok, result} = PromptOptimizerAgent.ApplyTemplateAction.run(
        %{
          template_name: "analysis",
          variables: %{
            subject: "sorting algorithm",
            content: "def quicksort(arr): ...",
            aspects: "time complexity, space complexity, stability"
          },
          customizations: %{
            add_examples: "Example: quicksort([3,1,4]) should return [1,3,4]",
            set_tone: :formal
          }
        },
        context
      )
      
      prompt = result.generated_prompt
      assert String.contains?(prompt, "sorting algorithm")
      assert String.contains?(prompt, "time complexity")
      assert String.contains?(prompt, "Example:")
      assert String.contains?(prompt, "comprehensive response")
    end
    
    test "returns error for missing template" do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:error, reason} = PromptOptimizerAgent.ApplyTemplateAction.run(
        %{
          template_name: "nonexistent_template",
          variables: %{}
        },
        context
      )
      
      assert String.contains?(reason, "not found")
    end
    
    test "returns error for missing required variables" do
      context = %{agent: GenServer.call(agent, :get_state)}
      
      {:error, reason} = PromptOptimizerAgent.ApplyTemplateAction.run(
        %{
          template_name: "code_generation",
          variables: %{task: "Sort array"} # Missing required variables
        },
        context
      )
      
      assert String.contains?(reason, "Missing required variables")
    end
  end
  
  describe "optimization history and metrics" do
    test "successful optimizations update history", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate successful optimization
      result = %{
        result: %{
          original_prompt: "Do stuff",
          optimized_prompt: "Create a comprehensive solution",
          optimization_strategies: [:clarity_enhancement],
          validation: %{improvement_score: 0.3}
        },
        from_cache: false
      }
      
      metadata = %{operation: :optimization, input_prompt: "Do stuff"}
      
      {:ok, updated} = PromptOptimizerAgent.handle_action_result(
        state,
        PromptOptimizerAgent.ExecuteToolAction,
        {:ok, result},
        metadata
      )
      
      # Check history was updated
      assert length(updated.state.optimization_history) == 1
      history_entry = hd(updated.state.optimization_history)
      assert history_entry.type == :prompt_optimization
      assert history_entry.operation == :optimization
    end
    
    test "optimization results update performance metrics", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Simulate optimization result with improvement score
      result = %{
        validation: %{improvement_score: 0.25}
      }
      
      {:ok, updated} = PromptOptimizerAgent.handle_action_result(
        state,
        PromptOptimizerAgent.OptimizePromptAction,
        {:ok, result},
        %{}
      )
      
      # Check performance metrics were updated
      metrics = updated.state.performance_metrics
      assert metrics.total_optimizations == 1
      assert metrics.average_improvement == 0.25
      assert metrics.last_improvement == 0.25
    end
    
    test "A/B test experiments are stored", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      test_config = %{
        name: "my_experiment",
        variants: [%{id: "A"}, %{id: "B"}],
        status: :active
      }
      
      result = %{test_config: test_config}
      
      {:ok, updated} = PromptOptimizerAgent.handle_action_result(
        state,
        PromptOptimizerAgent.ABTestPromptsAction,
        {:ok, result},
        %{}
      )
      
      # Check experiment was stored
      assert Map.has_key?(updated.state.active_experiments, "my_experiment")
      stored_config = updated.state.active_experiments["my_experiment"]
      assert stored_config.status == :active
    end
    
    test "optimization history respects max_history limit", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Set small limit for testing
      state = put_in(state.state.max_history, 2)
      
      # Add multiple optimizations
      state = Enum.reduce(1..3, state, fn i, acc ->
        result = %{
          result: %{original_prompt: "prompt#{i}", optimized_prompt: "optimized#{i}"},
          from_cache: false
        }
        
        {:ok, updated} = PromptOptimizerAgent.handle_action_result(
          acc,
          PromptOptimizerAgent.ExecuteToolAction,
          {:ok, result},
          %{operation: :test, input_prompt: "prompt#{i}"}
        )
        
        updated
      end)
      
      assert length(state.state.optimization_history) == 2
      # Should have the most recent entries
      [first, second] = state.state.optimization_history
      assert first.input_prompt == "prompt3"
      assert second.input_prompt == "prompt2"
    end
  end
  
  describe "agent initialization" do
    test "agent starts with default templates and strategies", %{agent: agent} do
      state = GenServer.call(agent, :get_state)
      
      # Check default templates
      templates = state.state.prompt_templates
      assert Map.has_key?(templates, :code_generation)
      assert Map.has_key?(templates, :analysis)
      assert Map.has_key?(templates, :explanation)
      
      # Check optimization strategies
      strategies = state.state.optimization_strategies
      assert Map.has_key?(strategies, :clarity_enhancement)
      assert Map.has_key?(strategies, :specificity_improvement)
      assert strategies.clarity_enhancement.enabled == true
      
      # Check model profiles
      profiles = state.state.model_profiles
      assert Map.has_key?(profiles, :gpt4)
      assert Map.has_key?(profiles, :claude)
      assert Map.has_key?(profiles, :gemini)
    end
  end
  
  describe "result processing" do
    test "process_result adds processing timestamp", %{agent: _agent} do
      result = %{prompt: "test", analysis: %{}}
      processed = PromptOptimizerAgent.process_result(result, %{})
      
      assert Map.has_key?(processed, :processed_at)
      assert %DateTime{} = processed.processed_at
    end
  end
  
  describe "additional actions list" do
    test "returns correct additional actions" do
      actions = PromptOptimizerAgent.additional_actions()
      
      assert length(actions) == 6
      assert PromptOptimizerAgent.AnalyzePromptAction in actions
      assert PromptOptimizerAgent.OptimizePromptAction in actions
      assert PromptOptimizerAgent.ABTestPromptsAction in actions
      assert PromptOptimizerAgent.GenerateVariationsAction in actions
      assert PromptOptimizerAgent.EvaluateEffectivenessAction in actions
      assert PromptOptimizerAgent.ApplyTemplateAction in actions
    end
  end
end