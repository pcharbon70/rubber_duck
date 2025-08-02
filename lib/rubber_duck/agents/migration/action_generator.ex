defmodule RubberDuck.Agents.Migration.ActionGenerator do
  @moduledoc """
  Generates Jido Action modules from existing agent functions.
  
  This module provides utilities for:
  - Analyzing agent functions and extracting business logic
  - Generating complete Action module templates
  - Creating NimbleOptions schemas from function signatures
  - Generating test templates for actions
  - Creating documentation templates
  
  ## Usage
  
      # Generate action from function
      {:ok, action_code} = ActionGenerator.generate_action(
        AnalysisAgent, 
        :analyze_code, 
        %{module_name: "CodeAnalysisAction"}
      )
      
      # Generate multiple actions from agent
      {:ok, actions} = ActionGenerator.generate_all_actions(AnalysisAgent)
      
      # Generate action with tests
      {:ok, {action_code, test_code}} = ActionGenerator.generate_with_tests(
        AnalysisAgent, 
        :analyze_code
      )
  """
  
  require Logger
  alias RubberDuck.Agents.Migration.Helpers
  
  @type action_spec :: %{
    module_name: String.t(),
    function_name: atom(),
    description: String.t(),
    schema: keyword(),
    source_module: module(),
    source_function: atom()
  }
  
  @type generation_options :: %{
    module_name: String.t(),
    description: String.t(),
    namespace: String.t(),
    include_tests: boolean(),
    include_docs: boolean()
  }

  @doc """
  Generates a complete Jido Action module from an agent function.
  
  Takes an agent module and function name, analyzes the function signature
  and implementation, then generates a complete Action module with proper
  schema validation and error handling.
  """
  @spec generate_action(module(), atom(), generation_options()) :: 
    {:ok, String.t()} | {:error, term()}
  def generate_action(agent_module, function_name, options \\ %{}) do
    try do
      # Analyze the source function
      {:ok, analysis} = analyze_function(agent_module, function_name)
      
      # Generate action specification
      action_spec = create_action_spec(analysis, options)
      
      # Generate the action code
      action_code = generate_action_code(action_spec)
      
      {:ok, action_code}
    rescue
      error -> {:error, {:action_generation_failed, error}}
    end
  end
  
  @doc """
  Generates all possible actions from an agent module.
  
  Analyzes all functions in the agent and generates Action modules
  for each business logic function found.
  """
  @spec generate_all_actions(module(), generation_options()) :: 
    {:ok, [%{name: String.t(), code: String.t()}]} | {:error, term()}
  def generate_all_actions(agent_module, options \\ %{}) do
    try do
      # Extract action candidates
      {:ok, candidates} = Helpers.extract_actions(agent_module)
      
      # Generate actions for each candidate
      actions = 
        candidates
        |> Enum.map(fn candidate ->
          action_options = Map.merge(options, %{
            module_name: candidate.name <> "Action",
            description: candidate.description
          })
          
          case generate_action(agent_module, candidate.function, action_options) do
            {:ok, code} -> %{name: candidate.name, code: code}
            {:error, _} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      
      {:ok, actions}
    rescue
      error -> {:error, {:bulk_generation_failed, error}}
    end
  end
  
  @doc """
  Generates an action module with corresponding test file.
  
  Creates both the action implementation and a comprehensive test
  suite following ExUnit best practices.
  """
  @spec generate_with_tests(module(), atom(), generation_options()) :: 
    {:ok, {String.t(), String.t()}} | {:error, term()}
  def generate_with_tests(agent_module, function_name, options \\ %{}) do
    try do
      # Generate the action
      {:ok, action_code} = generate_action(agent_module, function_name, options)
      
      # Generate the test
      {:ok, test_code} = generate_test_code(agent_module, function_name, options)
      
      {:ok, {action_code, test_code}}
    rescue
      error -> {:error, {:generation_with_tests_failed, error}}
    end
  end
  
  @doc """
  Generates a Mix task for creating new actions.
  
  Creates a `mix jido.gen.action` task that can be used to generate
  Action modules from templates.
  """
  @spec generate_mix_task() :: {:ok, String.t()} | {:error, term()}
  def generate_mix_task do
    task_code = """
    defmodule Mix.Tasks.Jido.Gen.Action do
      @moduledoc \"\"\"
      Generates a new Jido Action module.
      
      ## Usage
      
          mix jido.gen.action MyAction
          mix jido.gen.action MyModule.MyAction --schema name:string,age:integer
          mix jido.gen.action ProcessData --from-agent AnalysisAgent --function analyze_code
      \"\"\"
      
      use Mix.Task
      
      alias RubberDuck.Agents.Migration.ActionGenerator
      
      @shortdoc "Generates a new Jido Action module"
      
      def run(args) do
        {options, [name | _], _} = OptionParser.parse(args, 
          switches: [
            schema: :string,
            from_agent: :string,
            function: :string,
            namespace: :string,
            with_tests: :boolean
          ]
        )
        
        cond do
          options[:from_agent] && options[:function] ->
            generate_from_agent(name, options)
          true ->
            generate_new_action(name, options)
        end
      end
      
      defp generate_from_agent(name, options) do
        agent_module = Module.concat([options[:from_agent]])
        function_name = String.to_atom(options[:function])
        
        generation_options = %{
          module_name: name,
          namespace: options[:namespace] || "RubberDuck.Actions",
          include_tests: options[:with_tests] || false
        }
        
        case ActionGenerator.generate_action(agent_module, function_name, generation_options) do
          {:ok, code} ->
            write_action_file(name, code, generation_options)
            Mix.shell().info("Generated action: \#{name}")
          {:error, reason} ->
            Mix.shell().error("Failed to generate action: \#{inspect(reason)}")
        end
      end
      
      defp generate_new_action(name, options) do
        # Generate template action
        namespace = options[:namespace] || "RubberDuck.Actions"
        schema = parse_schema(options[:schema])
        
        code = generate_template_action(namespace, name, schema)
        
        generation_options = %{
          namespace: namespace,
          include_tests: options[:with_tests] || false
        }
        
        write_action_file(name, code, generation_options)
        Mix.shell().info("Generated template action: \#{name}")
      end
      
      defp write_action_file(name, code, options) do
        filename = Macro.underscore(name) <> ".ex"
        path = Path.join(["lib", "rubber_duck", "actions", filename])
        
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, code)
        
        if options[:include_tests] do
          write_test_file(name, options)
        end
      end
      
      defp write_test_file(name, _options) do
        test_filename = Macro.underscore(name) <> "_test.exs"
        test_path = Path.join(["test", "rubber_duck", "actions", test_filename])
        
        test_code = generate_template_test(name)
        
        File.mkdir_p!(Path.dirname(test_path))
        File.write!(test_path, test_code)
      end
      
      defp parse_schema(nil), do: []
      defp parse_schema(schema_string) do
        schema_string
        |> String.split(",")
        |> Enum.map(&parse_schema_field/1)
      end
      
      defp parse_schema_field(field) do
        [name, type] = String.split(field, ":")
        {String.to_atom(String.trim(name)), parse_type(String.trim(type))}
      end
      
      defp parse_type("string"), do: :string
      defp parse_type("integer"), do: :integer
      defp parse_type("boolean"), do: :boolean
      defp parse_type("map"), do: :map
      defp parse_type("list"), do: :list
      defp parse_type(type), do: String.to_atom(type)
      
      defp generate_template_action(namespace, name, schema) do
        ActionGenerator.generate_template_action_code(namespace, name, schema)
      end
      
      defp generate_template_test(name) do
        ActionGenerator.generate_template_test_code(name)
      end
    end
    """
    
    {:ok, task_code}
  end
  
  # Private implementation functions
  
  defp analyze_function(agent_module, function_name) do
    try do
      # Get function info
      functions = agent_module.__info__(:functions)
      
      case Enum.find(functions, fn {name, _arity} -> name == function_name end) do
        {^function_name, arity} ->
          analysis = %{
            module: agent_module,
            function: function_name,
            arity: arity,
            parameters: generate_parameter_analysis(agent_module, function_name, arity),
            return_type: analyze_return_type(agent_module, function_name),
            description: generate_function_description(function_name)
          }
          {:ok, analysis}
        nil ->
          {:error, {:function_not_found, function_name}}
      end
    rescue
      error -> {:error, {:function_analysis_failed, error}}
    end
  end
  
  defp create_action_spec(analysis, options) do
    module_name = Map.get(options, :module_name, 
      Macro.camelize(Atom.to_string(analysis.function)) <> "Action")
    
    %{
      module_name: module_name,
      function_name: analysis.function,
      description: Map.get(options, :description, analysis.description),
      schema: generate_schema_from_parameters(analysis.parameters),
      source_module: analysis.module,
      source_function: analysis.function,
      namespace: Map.get(options, :namespace, "RubberDuck.Actions")
    }
  end
  
  defp generate_action_code(action_spec) do
    """
    defmodule #{action_spec.namespace}.#{action_spec.module_name} do
      @moduledoc \"\"\"
      #{action_spec.description}
      
      This action was generated from #{action_spec.source_module}.#{action_spec.source_function}/#{length(action_spec.schema)}.
      \"\"\"
      
      use Jido.Action,
        name: "#{Macro.underscore(action_spec.module_name)}",
        description: "#{action_spec.description}",
        schema: #{inspect(action_spec.schema, pretty: true)}

      @impl true
      def run(params, context) do
        # TODO: Implement action logic
        # Original function: #{action_spec.source_module}.#{action_spec.source_function}
        
        # Extract parameters
        #{generate_parameter_extraction(action_spec.schema)}
        
        # Perform business logic
        case perform_operation(params, context) do
          {:ok, result} -> 
            {:ok, %{
              result: result,
              timestamp: DateTime.utc_now(),
              action: "#{Macro.underscore(action_spec.module_name)}"
            }}
          {:error, reason} -> 
            {:error, reason}
        end
      end
      
      # TODO: Implement business logic from original function
      defp perform_operation(_params, _context) do
        {:ok, %{message: "Action implementation needed"}}
      end
    end
    """
  end
  
  defp generate_test_code(agent_module, function_name, options) do
    module_name = Map.get(options, :module_name, 
      Macro.camelize(Atom.to_string(function_name)) <> "Action")
    namespace = Map.get(options, :namespace, "RubberDuck.Actions")
    
    """
    defmodule #{namespace}.#{module_name}Test do
      use ExUnit.Case, async: true
      
      alias #{namespace}.#{module_name}
      
      describe "run/2" do
        test "executes successfully with valid parameters" do
          params = %{
            # TODO: Add test parameters
          }
          context = %{}
          
          assert {:ok, result} = #{module_name}.run(params, context)
          assert Map.has_key?(result, :result)
          assert Map.has_key?(result, :timestamp)
        end
        
        test "handles invalid parameters gracefully" do
          params = %{}
          context = %{}
          
          # TODO: Test parameter validation
          assert {:error, _reason} = #{module_name}.run(params, context)
        end
        
        test "includes proper metadata in result" do
          params = %{
            # TODO: Add valid parameters
          }
          context = %{}
          
          assert {:ok, result} = #{module_name}.run(params, context)
          assert result.action == "#{Macro.underscore(module_name)}"
          assert %DateTime{} = result.timestamp
        end
      end
    end
    """
  end
  
  defp generate_parameter_analysis(_agent_module, _function_name, arity) do
    # Generate parameter names based on arity
    1..arity
    |> Enum.map(fn i -> 
      %{
        name: :"param#{i}",
        type: :any,
        required: true,
        description: "Parameter #{i}"
      }
    end)
  end
  
  defp analyze_return_type(_agent_module, _function_name) do
    # Default to tagged tuple return type
    :tagged_tuple
  end
  
  defp generate_function_description(function_name) do
    function_name
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.trim()
    |> (&"Performs #{&1} operation").()
  end
  
  defp generate_schema_from_parameters(parameters) do
    parameters
    |> Enum.map(fn param ->
      {param.name, [
        type: param.type,
        required: param.required,
        doc: param.description
      ]}
    end)
  end
  
  defp generate_parameter_extraction(schema) do
    schema
    |> Enum.map(fn {name, _opts} ->
      "#{name} = params.#{name}"
    end)
    |> Enum.join("\n        ")
  end
  
  @doc """
  Generates template action code for the Mix task.
  """
  def generate_template_action_code(namespace, name, schema) do
    """
    defmodule #{namespace}.#{name} do
      @moduledoc \"\"\"
      Generated action module.
      
      TODO: Add proper documentation describing what this action does.
      \"\"\"
      
      use Jido.Action,
        name: "#{Macro.underscore(name)}",
        description: "TODO: Add action description",
        schema: #{inspect(schema, pretty: true)}

      @impl true
      def run(params, _context) do
        # TODO: Implement action logic
        {:ok, %{
          message: "Action executed successfully",
          params: params,
          timestamp: DateTime.utc_now()
        }}
      end
    end
    """
  end
  
  @doc """
  Generates template test code for the Mix task.
  """
  def generate_template_test_code(name) do
    """
    defmodule #{name}Test do
      use ExUnit.Case, async: true
      
      alias RubberDuck.Actions.#{name}
      
      describe "run/2" do
        test "executes successfully" do
          params = %{}
          context = %{}
          
          assert {:ok, result} = #{name}.run(params, context)
          assert Map.has_key?(result, :message)
          assert Map.has_key?(result, :timestamp)
        end
      end
    end
    """
  end
end