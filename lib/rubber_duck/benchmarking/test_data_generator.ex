defmodule RubberDuck.Benchmarking.TestDataGenerator do
  @moduledoc """
  Generates realistic test data for benchmarking code analysis performance.
  
  This module creates code samples of various sizes and complexity levels
  to provide comprehensive benchmarking data across different scenarios.
  """

  @doc """
  Generate a code sample for the specified language and target size.
  """
  def generate_code_sample(language, target_size_bytes) do
    base_code = get_base_code_template(language)
    expand_code_to_size(base_code, target_size_bytes, language)
  end

  @doc """
  Generate a large code sample optimized for streaming analysis testing.
  """
  def generate_large_code_sample(language, target_size_bytes) do
    # For large files, create more complex structures
    base_code = get_complex_code_template(language)
    expand_code_to_size(base_code, target_size_bytes, language)
  end

  @doc """
  Generate code with specific complexity characteristics.
  """
  def generate_complex_code(language, complexity_level, target_size) do
    case complexity_level do
      :low -> generate_simple_code(language, target_size)
      :medium -> generate_medium_complexity_code(language, target_size)
      :high -> generate_high_complexity_code(language, target_size)
    end
  end

  ## Private Functions

  defp get_base_code_template(:elixir) do
    """
    defmodule TestModule do
      @moduledoc "Test module for benchmarking"
      
      def hello_world do
        "Hello, World!"
      end
      
      def fibonacci(n) when n <= 1, do: n
      def fibonacci(n), do: fibonacci(n - 1) + fibonacci(n - 2)
      
      def process_list(list) when is_list(list) do
        list
        |> Enum.map(&(&1 * 2))
        |> Enum.filter(&(&1 > 10))
        |> Enum.sum()
      end
    end
    """
  end

  defp get_base_code_template(:javascript) do
    """
    class TestClass {
      constructor() {
        this.data = [];
      }
      
      helloWorld() {
        return "Hello, World!";
      }
      
      fibonacci(n) {
        if (n <= 1) return n;
        return this.fibonacci(n - 1) + this.fibonacci(n - 2);
      }
      
      processList(list) {
        return list
          .map(x => x * 2)
          .filter(x => x > 10)
          .reduce((sum, x) => sum + x, 0);
      }
    }
    """
  end

  defp get_base_code_template(:python) do
    "class TestClass:\n" <>
    "    def __init__(self):\n" <>
    "        self.data = []\n" <>
    "    \n" <>
    "    def hello_world(self):\n" <>
    "        return \"Hello, World!\"\n" <>
    "    \n" <>
    "    def fibonacci(self, n):\n" <>
    "        if n <= 1:\n" <>
    "            return n\n" <>
    "        return self.fibonacci(n - 1) + self.fibonacci(n - 2)\n" <>
    "    \n" <>
    "    def process_list(self, lst):\n" <>
    "        return sum(x for x in [y * 2 for y in lst] if x > 10)"
  end

  defp get_base_code_template(_), do: "# Generic test code\n"

  defp get_complex_code_template(:elixir) do
    """
    defmodule ComplexTestModule do
      @moduledoc "Complex test module for streaming benchmarks"
      
      use GenServer
      require Logger
      
      defstruct [:data, :config, :state, :metrics]
      
      def start_link(opts \\\\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
      
      def init(opts) do
        state = %__MODULE__{
          data: Keyword.get(opts, :data, []),
          config: build_config(opts),
          state: :initialized,
          metrics: %{}
        }
        {:ok, state}
      end
      
      def handle_call({:process_data, data}, _from, state) do
        case process_complex_data(data, state.config) do
          {:ok, result} ->
            new_metrics = update_metrics(state.metrics, :success)
            new_state = %{state | metrics: new_metrics}
            {:reply, {:ok, result}, new_state}
          {:error, reason} ->
            new_metrics = update_metrics(state.metrics, :error)
            new_state = %{state | metrics: new_metrics}
            {:reply, {:error, reason}, new_state}
        end
      end
      
      defp process_complex_data(data, config) when is_list(data) do
        try do
          result = data
          |> Enum.chunk_every(config.chunk_size)
          |> Enum.map(&process_chunk/1)
          |> Enum.reduce(%{}, &merge_results/2)
          
          {:ok, result}
        rescue
          error -> {:error, error}
        end
      end
      
      defp process_chunk(chunk) do
        chunk
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          case complex_calculation(item, index) do
            {:ok, result} -> result
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      end
      
      defp complex_calculation(item, index) do
        cond do
          rem(index, 2) == 0 -> {:ok, item * index}
          rem(index, 3) == 0 -> {:ok, item + index}
          true -> {:ok, item}
        end
      end
    end
    """
  end

  defp get_complex_code_template(:javascript) do
    """
    class ComplexTestClass {
      constructor(options = {}) {
        this.data = options.data || [];
        this.config = this.buildConfig(options);
        this.state = 'initialized';
        this.metrics = {};
      }
      
      async processData(data) {
        try {
          const result = await this.processComplexData(data);
          this.updateMetrics('success');
          return { ok: true, result };
        } catch (error) {
          this.updateMetrics('error');
          return { ok: false, error };
        }
      }
      
      async processComplexData(data) {
        const chunks = this.chunkArray(data, this.config.chunkSize);
        const results = await Promise.all(
          chunks.map(chunk => this.processChunk(chunk))
        );
        return results.reduce((acc, result) => this.mergeResults(acc, result), {});
      }
      
      processChunk(chunk) {
        return chunk
          .map((item, index) => this.complexCalculation(item, index))
          .filter(result => result !== null);
      }
      
      complexCalculation(item, index) {
        if (index % 2 === 0) return item * index;
        if (index % 3 === 0) return item + index;
        return item;
      }
      
      chunkArray(array, size) {
        const chunks = [];
        for (let i = 0; i < array.length; i += size) {
          chunks.push(array.slice(i, i + size));
        }
        return chunks;
      }
    }
    """
  end

  defp get_complex_code_template(:python) do
    """
    import asyncio
    import logging
    from typing import List, Dict, Any, Optional
    
    class ComplexTestClass:
        def __init__(self, options: Dict[str, Any] = None):
            options = options or {}
            self.data = options.get('data', [])
            self.config = self._build_config(options)
            self.state = 'initialized'
            self.metrics = {}
            
        async def process_data(self, data: List[Any]) -> Dict[str, Any]:
            try:
                result = await self._process_complex_data(data)
                self._update_metrics('success')
                return {'ok': True, 'result': result}
            except Exception as error:
                self._update_metrics('error')
                return {'ok': False, 'error': str(error)}
        
        async def _process_complex_data(self, data: List[Any]) -> Dict[str, Any]:
            chunks = self._chunk_array(data, self.config['chunk_size'])
            tasks = [self._process_chunk(chunk) for chunk in chunks]
            results = await asyncio.gather(*tasks)
            
            final_result = {}
            for result in results:
                final_result = self._merge_results(final_result, result)
            return final_result
        
        def _process_chunk(self, chunk: List[Any]) -> List[Any]:
            results = []
            for index, item in enumerate(chunk):
                result = self._complex_calculation(item, index)
                if result is not None:
                    results.append(result)
            return results
        
        def _complex_calculation(self, item: Any, index: int) -> Optional[Any]:
            if index % 2 == 0:
                return item * index
            elif index % 3 == 0:
                return item + index
            else:
                return item
    """
  end

  defp get_complex_code_template(_), do: get_base_code_template(:elixir)

  defp expand_code_to_size(base_code, target_size, language) do
    current_size = byte_size(base_code)
    
    if current_size >= target_size do
      String.slice(base_code, 0, target_size)
    else
      additional_content = generate_filler_content(language, target_size - current_size)
      base_code <> "\n\n" <> additional_content
    end
  end

  defp generate_filler_content(language, size_needed) do
    filler_function = get_filler_function_template(language)
    filler_size = byte_size(filler_function)
    
    num_functions = div(size_needed, filler_size) + 1
    
    1..num_functions
    |> Enum.map(fn i -> String.replace(filler_function, "FUNCTION_NUMBER", to_string(i)) end)
    |> Enum.join("\n\n")
    |> String.slice(0, size_needed)
  end

  defp get_filler_function_template(:elixir) do
    "def generated_function_FUNCTION_NUMBER(param) do\n" <>
    "  # Generated function for benchmarking\n" <>
    "  case param do\n" <>
    "    x when is_integer(x) and x > 0 ->\n" <>
    "      result = x * 2 + 1\n" <>
    "      if rem(result, 3) == 0 do\n" <>
    "        {:ok, result}\n" <>
    "      else\n" <>
    "        {:error, :not_divisible_by_three}\n" <>
    "      end\n" <>
    "    x when is_binary(x) ->\n" <>
    "      processed = x |> String.upcase() |> String.replace(\" \", \"_\")\n" <>
    "      {:ok, processed}\n" <>
    "    x when is_list(x) ->\n" <>
    "      processed = x |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 10))\n" <>
    "      {:ok, Enum.sum(processed)}\n" <>
    "    _ ->\n" <>
    "      {:error, :unsupported_type}\n" <>
    "  end\n" <>
    "end"
  end

  defp get_filler_function_template(:javascript) do
    "function generatedFunctionFUNCTION_NUMBER(param) {\n" <>
    "  // Generated function for benchmarking\n" <>
    "  if (typeof param === 'number' && param > 0) {\n" <>
    "    const result = param * 2 + 1;\n" <>
    "    if (result % 3 === 0) {\n" <>
    "      return { ok: true, value: result };\n" <>
    "    } else {\n" <>
    "      return { ok: false, error: 'not_divisible_by_three' };\n" <>
    "    }\n" <>
    "  } else if (typeof param === 'string') {\n" <>
    "    const processed = param.toUpperCase().replace(/ /g, '_');\n" <>
    "    return { ok: true, value: processed };\n" <>
    "  } else if (Array.isArray(param)) {\n" <>
    "    const processed = param\n" <>
    "      .map(x => x * 2)\n" <>
    "      .filter(x => x > 10)\n" <>
    "      .reduce((sum, x) => sum + x, 0);\n" <>
    "    return { ok: true, value: processed };\n" <>
    "  } else {\n" <>
    "    return { ok: false, error: 'unsupported_type' };\n" <>
    "  }\n" <>
    "}"
  end

  defp get_filler_function_template(:python) do
    "def generated_function_FUNCTION_NUMBER(param):\n" <>
    "    # Generated function for benchmarking\n" <>
    "    if isinstance(param, int) and param > 0:\n" <>
    "        result = param * 2 + 1\n" <>
    "        if result % 3 == 0:\n" <>
    "            return {'ok': True, 'value': result}\n" <>
    "        else:\n" <>
    "            return {'ok': False, 'error': 'not_divisible_by_three'}\n" <>
    "    elif isinstance(param, str):\n" <>
    "        processed = param.upper().replace(' ', '_')\n" <>
    "        return {'ok': True, 'value': processed}\n" <>
    "    elif isinstance(param, list):\n" <>
    "        processed = [x * 2 for x in param]\n" <>
    "        filtered = [x for x in processed if x > 10]\n" <>
    "        return {'ok': True, 'value': sum(filtered)}\n" <>
    "    else:\n" <>
    "        return {'ok': False, 'error': 'unsupported_type'}"
  end

  defp get_filler_function_template(_), do: get_filler_function_template(:elixir)

  defp generate_simple_code(language, target_size) do
    # Generate simple, linear code
    base = get_base_code_template(language)
    expand_code_to_size(base, target_size, language)
  end

  defp generate_medium_complexity_code(language, target_size) do
    # Generate code with moderate nesting and complexity
    base = get_complex_code_template(language)
    
    # Add some conditional logic and loops
    additional_complexity = get_medium_complexity_additions(language)
    combined = base <> "\n\n" <> additional_complexity
    
    expand_code_to_size(combined, target_size, language)
  end

  defp generate_high_complexity_code(language, target_size) do
    # Generate highly nested, complex code
    base = get_complex_code_template(language)
    high_complexity = get_high_complexity_additions(language)
    combined = base <> "\n\n" <> high_complexity
    
    expand_code_to_size(combined, target_size, language)
  end

  defp get_medium_complexity_additions(:elixir) do
    "defmodule NestedProcessing do\n" <>
    "  def process_data(data) do\n" <>
    "    data\n" <>
    "    |> Enum.map(&process_item/1)\n" <>
    "    |> Enum.filter(&match?({:ok, _}, &1))\n" <>
    "    |> Enum.map(&elem(&1, 1))\n" <>
    "  end\n" <>
    "end"
  end

  defp get_medium_complexity_additions(:javascript) do
    "// Medium complexity JavaScript code\n" <>
    "class NestedProcessing {\n" <>
    "  processData(data) {\n" <>
    "    return data\n" <>
    "      .map(item => this.processItem(item))\n" <>
    "      .filter(result => result.ok)\n" <>
    "      .map(result => result.value);\n" <>
    "  }\n" <>
    "}"
  end

  defp get_medium_complexity_additions(:python) do
    "# Medium complexity Python code\n" <>
    "class NestedProcessing:\n" <>
    "    def process_data(self, data):\n" <>
    "        results = []\n" <>
    "        for item in data:\n" <>
    "            if item.get('type') == 'complex':\n" <>
    "                results.append(self.process_complex(item))\n" <>
    "            else:\n" <>
    "                results.append(self.process_simple(item))\n" <>
    "        return results"
  end

  defp get_medium_complexity_additions(_), do: get_medium_complexity_additions(:elixir)

  defp get_high_complexity_additions(:elixir) do
    "defmodule HighComplexityProcessor do\n" <>
    "  def process_data(data, config) do\n" <>
    "    try do\n" <>
    "      data\n" <>
    "      |> Enum.chunk_every(config.batch_size)\n" <>
    "      |> Enum.map(&process_batch/1)\n" <>
    "      |> Enum.reduce({:ok, []}, &merge_results/2)\n" <>
    "    rescue\n" <>
    "      error -> {:error, {:exception, error}}\n" <>
    "    end\n" <>
    "  end\n" <>
    "end"
  end

  defp get_high_complexity_additions(:javascript) do
    "// High complexity JavaScript code\n" <>
    "class HighComplexityProcessor {\n" <>
    "  async processData(data, config) {\n" <>
    "    try {\n" <>
    "      const results = [];\n" <>
    "      for (const item of data) {\n" <>
    "        const processed = await this.processItem(item);\n" <>
    "        results.push(processed);\n" <>
    "      }\n" <>
    "      return { ok: true, results };\n" <>
    "    } catch (error) {\n" <>
    "      return { ok: false, error: error.message };\n" <>
    "    }\n" <>
    "  }\n" <>
    "}"
  end

  defp get_high_complexity_additions(:python) do
    "# High complexity Python code\n" <>
    "class HighComplexityProcessor:\n" <>
    "    async def process_data(self, data, config):\n" <>
    "        try:\n" <>
    "            results = []\n" <>
    "            for item in data:\n" <>
    "                processed = await self.process_item(item)\n" <>
    "                results.append(processed)\n" <>
    "            return {'ok': True, 'results': results}\n" <>
    "        except Exception as error:\n" <>
    "            return {'ok': False, 'error': str(error)}"
  end

  defp get_high_complexity_additions(_), do: get_high_complexity_additions(:elixir)
end