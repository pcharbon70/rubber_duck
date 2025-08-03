defmodule RubberDuck.Tools.CodeGenerator do
  @moduledoc """
  Generates Elixir code from a given description or signature.
  
  This tool uses the configured LLM provider to generate code based on
  the provided description, context, and constraints.
  """
  
  use RubberDuck.Tool
  
  alias RubberDuck.LLM.Service
  alias RubberDuck.Context.Builder
  
  tool do
    name :code_generator
    description "Generates Elixir code from a given description or signature"
    category :code_generation
    version "1.0.0"
    tags [:generation, :code, :elixir, :ai]
    
    parameter :description do
      type :string
      required true
      description "Natural language description of the code to generate"
      constraints [
        min_length: 10,
        max_length: 2000
      ]
    end
    
    parameter :signature do
      type :string
      required false
      description "Optional function signature or module structure"
    end
    
    parameter :context do
      type :map
      required false
      description "Additional context like module name, dependencies, or constraints"
      default %{}
    end
    
    parameter :style do
      type :string
      required false
      description "Code style preferences (e.g., 'functional', 'defensive', 'concise')"
      default "idiomatic"
      constraints [
        enum: ["idiomatic", "functional", "defensive", "concise", "verbose"]
      ]
    end
    
    parameter :include_tests do
      type :boolean
      required false
      description "Whether to generate accompanying tests"
      default false
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 2
    end
    
    security do
      sandbox :strict
      capabilities [:llm_access, :code_generation]
      rate_limit [max_requests: 100, window_seconds: 60]
    end
  end
  
  @doc """
  Executes the code generation based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, prompt} <- build_prompt(params),
         {:ok, llm_response} <- generate_code(prompt, context),
         {:ok, extracted_code} <- extract_code(llm_response),
         {:ok, validated_code} <- validate_code(extracted_code) do
      
      result = %{
        code: validated_code,
        language: "elixir",
        description: params.description
      }
      
      result = if params.include_tests do
        case generate_tests(validated_code, params.description, context) do
          {:ok, tests} -> Map.put(result, :tests, tests)
          _ -> result
        end
      else
        result
      end
      
      {:ok, result}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp build_prompt(params) do
    prompt = """
    Generate Elixir code based on the following description:
    
    #{params.description}
    """
    
    prompt = if params.signature do
      prompt <> "\n\nFunction/Module signature:\n#{params.signature}"
    else
      prompt
    end
    
    prompt = if map_size(params.context) > 0 do
      context_str = params.context
      |> Enum.map(fn {k, v} -> "- #{k}: #{v}" end)
      |> Enum.join("\n")
      
      prompt <> "\n\nAdditional context:\n#{context_str}"
    else
      prompt
    end
    
    prompt = prompt <> "\n\nCode style: #{params.style}"
    prompt = prompt <> "\n\nPlease provide clean, well-documented Elixir code with proper error handling."
    
    {:ok, prompt}
  end
  
  defp generate_code(prompt, context) do
    # Build enhanced context if available
    enhanced_context = case Builder.build(%{
      type: :code_generation,
      content: prompt,
      max_tokens: 2000
    }) do
      {:ok, ctx} -> ctx
      _ -> %{}
    end
    
    # Call LLM service
    Service.generate(%{
      prompt: prompt,
      context: enhanced_context,
      max_tokens: 2000,
      temperature: 0.7,
      model: context[:llm_model] || "gpt-4"
    })
  end
  
  defp extract_code(llm_response) do
    # Extract code from the LLM response
    # Looking for code blocks or direct code
    code = case Regex.run(~r/```(?:elixir|ex)?\n(.*?)\n```/s, llm_response, capture: :all_but_first) do
      [code] -> String.trim(code)
      _ -> 
        # If no code block, assume the entire response is code
        # (after removing any explanatory text)
        llm_response
        |> String.split("\n")
        |> Enum.drop_while(&(!String.starts_with?(&1, "def")))
        |> Enum.join("\n")
        |> String.trim()
    end
    
    if code == "" do
      {:error, "No code found in response"}
    else
      {:ok, code}
    end
  end
  
  defp validate_code(code) do
    # Basic syntax validation
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> {:ok, code}
      {:error, {line, error, _}} -> 
        {:error, "Syntax error on line #{line}: #{error}"}
    end
  end
  
  defp generate_tests(code, description, context) do
    test_prompt = """
    Generate ExUnit tests for the following Elixir code:
    
    ```elixir
    #{code}
    ```
    
    Original description: #{description}
    
    Generate comprehensive tests including:
    - Happy path tests
    - Edge cases
    - Error handling tests
    """
    
    case generate_code(test_prompt, context) do
      {:ok, test_response} -> extract_code(test_response)
      error -> error
    end
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end