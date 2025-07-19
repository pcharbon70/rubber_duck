defmodule RubberDuck.Instructions.ContextBridge do
  @moduledoc """
  Bridge module that integrates the instruction system with context building.

  This module coordinates between the hierarchical instruction loading system
  and the context building strategies, enabling instruction-driven context
  enhancement with dynamic system prompts, user preferences, and project-specific
  context rules from AGENTS.md files.

  ## Features

  - **Instruction-Driven Context**: Load relevant instructions for context enhancement
  - **Hierarchical Resolution**: Project → workspace → global instruction inheritance
  - **Template Processing**: Dynamic system prompts with variable interpolation
  - **User Preferences**: Apply instruction-defined preferences to context building
  - **Project-Specific Rules**: Context customization based on project instructions
  - **Cache Integration**: Leverage existing instruction caching for performance

  ## Usage Examples

      # Load instructions for a specific context
      {:ok, instructions} = ContextBridge.load_instructions_for_context(%{
        project_path: "/path/to/project",
        user_id: "user123",
        context_type: :rag
      })
      
      # Enhance context with instructions
      enhanced_context = ContextBridge.enhance_context(base_context, instructions)
      
      # Get instruction-driven system prompt
      {:ok, system_prompt} = ContextBridge.get_system_prompt(instructions, context_variables)
  """

  alias RubberDuck.Instructions.{HierarchicalLoader, TemplateProcessor, Registry, FileManager}
  require Logger

  @type context_options :: %{
          project_path: String.t() | nil,
          user_id: String.t() | nil,
          context_type: atom(),
          workspace_path: String.t() | nil,
          session_id: String.t() | nil
        }

  @type instruction_context :: %{
          instructions: [map()],
          system_prompt: String.t() | nil,
          user_preferences: map(),
          context_rules: map(),
          applied_files: [String.t()],
          metadata: map()
        }

  @type context_enhancement :: %{
          system_prompt: String.t() | nil,
          user_preferences: map(),
          context_rules: map(),
          metadata: map()
        }

  ## Public API

  @doc """
  Loads relevant instructions for a specific context.

  Performs hierarchical instruction loading and filters to instructions
  relevant for the given context type and scope.
  """
  @spec load_instructions_for_context(context_options()) ::
          {:ok, instruction_context()} | {:error, term()}
  def load_instructions_for_context(options) do
    with {:ok, loaded_instructions} <- load_hierarchical_instructions(options),
         filtered_instructions <- filter_instructions_for_context(loaded_instructions, options),
         {:ok, processed_context} <- process_instruction_context(filtered_instructions, options) do
      {:ok, processed_context}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Enhances a base context with instruction-driven content.

  Applies instruction templates, merges system prompts, and includes
  instruction-specific metadata in the context.
  """
  @spec enhance_context(map(), instruction_context()) :: map()
  def enhance_context(base_context, instruction_context) do
    enhanced_metadata =
      Map.merge(
        Map.get(base_context, :metadata, %{}),
        %{
          instruction_context: instruction_context.metadata,
          applied_instructions: instruction_context.applied_files,
          has_instructions: length(instruction_context.instructions) > 0
        }
      )

    enhanced_context = %{
      base_context
      | metadata: enhanced_metadata
    }

    # Add instruction-driven system prompt if available
    case instruction_context.system_prompt do
      nil ->
        enhanced_context

      system_prompt ->
        Map.put(enhanced_context, :instruction_system_prompt, system_prompt)
    end
  end

  @doc """
  Gets a dynamic system prompt from instructions with variable interpolation.

  Processes instruction templates with provided context variables to generate
  a dynamic system prompt.
  """
  @spec get_system_prompt(instruction_context(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def get_system_prompt(instruction_context, context_variables \\ %{}) do
    case find_system_prompt_template(instruction_context.instructions) do
      nil ->
        {:ok, nil}

      template ->
        case TemplateProcessor.process_template(template, context_variables) do
          {:ok, rendered_prompt} -> {:ok, rendered_prompt}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Extracts user preferences from loaded instructions.

  Merges preferences from multiple instruction files with proper precedence
  (project overrides workspace overrides global).
  """
  @spec get_user_preferences(instruction_context()) :: map()
  def get_user_preferences(instruction_context) do
    instruction_context.user_preferences
  end

  @doc """
  Extracts context building rules from instructions.

  Returns rules that influence how context should be built, such as
  file inclusion patterns, retrieval preferences, etc.
  """
  @spec get_context_rules(instruction_context()) :: map()
  def get_context_rules(instruction_context) do
    instruction_context.context_rules
  end

  @doc """
  Determines the preferred context strategy based on instructions.

  Returns the strategy name that instructions suggest should be used
  for the given context type.
  """
  @spec get_preferred_strategy(instruction_context(), atom()) :: atom()
  def get_preferred_strategy(instruction_context, default_strategy) do
    Map.get(instruction_context.context_rules, :preferred_strategy, default_strategy)
  end

  @doc """
  Checks if instructions are available for the given project path.

  Quick check without full loading to determine if instruction enhancement
  is possible.
  """
  @spec has_instructions?(String.t()) :: boolean()
  def has_instructions?(project_path) when is_binary(project_path) do
    case Registry.list_instructions(scope: :project, root_path: project_path) do
      {:ok, instructions} when is_list(instructions) -> length(instructions) > 0
      _ -> false
    end
  end

  def has_instructions?(_), do: false

  ## Private Functions

  defp load_hierarchical_instructions(options) do
    project_path = Map.get(options, :project_path)
    user_id = Map.get(options, :user_id)

    cond do
      project_path ->
        # Load project-specific instructions
        HierarchicalLoader.load_instructions(project_path, include_global: true)

      user_id ->
        # Load user-specific global instructions
        load_user_global_instructions(user_id)

      true ->
        # Load default global instructions
        load_default_instructions()
    end
  end

  defp load_user_global_instructions(_user_id) do
    # Load global instructions for specific user
    # This would typically include ~/.agents.md
    global_paths = [
      Path.expand("~/.agents.md"),
      Path.expand("~/.config/rubberduck/AGENTS.md")
    ]

    load_instructions_from_paths(global_paths)
  end

  defp load_default_instructions() do
    # Load system-wide default instructions
    system_paths = [
      "/etc/rubberduck/AGENTS.md"
    ]

    load_instructions_from_paths(system_paths)
  end

  defp load_instructions_from_paths(paths) do
    loaded_instructions =
      paths
      |> Enum.filter(&File.exists?/1)
      |> Enum.map(fn path ->
        case FileManager.load_file(path) do
          {:ok, instruction} -> instruction
          {:error, _reason} -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    {:ok, %{loaded: loaded_instructions, analysis: %{}}}
  end

  defp filter_instructions_for_context(loaded_result, options) do
    context_type = Map.get(options, :context_type, :general)

    loaded_result.loaded
    |> Enum.filter(fn instruction ->
      instruction_applies_to_context?(instruction, context_type)
    end)
  end

  defp instruction_applies_to_context?(instruction, context_type) do
    # Check if instruction metadata indicates it applies to this context type
    applicable_contexts = Map.get(instruction.metadata, "contexts", ["all"])

    cond do
      "all" in applicable_contexts -> true
      Atom.to_string(context_type) in applicable_contexts -> true
      context_type == :general -> true
      true -> false
    end
  end

  defp process_instruction_context(instructions, options) do
    # Process instructions to extract context-relevant information
    context_variables = build_context_variables(options)

    system_prompt = extract_system_prompt(instructions, context_variables)
    user_preferences = extract_user_preferences(instructions)
    context_rules = extract_context_rules(instructions)
    applied_files = Enum.map(instructions, & &1.file_path)

    metadata = %{
      instruction_count: length(instructions),
      has_system_prompt: system_prompt != nil,
      context_type: Map.get(options, :context_type),
      loaded_at: :os.system_time(:millisecond)
    }

    processed_context = %{
      instructions: instructions,
      system_prompt: system_prompt,
      user_preferences: user_preferences,
      context_rules: context_rules,
      applied_files: applied_files,
      metadata: metadata
    }

    {:ok, processed_context}
  end

  defp build_context_variables(options) do
    project_path = Map.get(options, :project_path)

    base_variables = %{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "context_type" => Map.get(options, :context_type, :general) |> Atom.to_string()
    }

    # Add project-specific variables
    project_variables =
      if project_path do
        %{
          "project_name" => Path.basename(project_path),
          "project_path" => project_path,
          "language" => detect_project_language(project_path)
        }
      else
        %{}
      end

    Map.merge(base_variables, project_variables)
  end

  defp detect_project_language(project_path) do
    # Simple language detection based on project files
    cond do
      File.exists?(Path.join(project_path, "mix.exs")) -> "elixir"
      File.exists?(Path.join(project_path, "package.json")) -> "javascript"
      File.exists?(Path.join(project_path, "Cargo.toml")) -> "rust"
      File.exists?(Path.join(project_path, "go.mod")) -> "go"
      File.exists?(Path.join(project_path, "requirements.txt")) -> "python"
      true -> "unknown"
    end
  end

  defp extract_system_prompt(instructions, context_variables) do
    # Find system prompt template in instructions
    system_prompt_template = find_system_prompt_template(instructions)

    case system_prompt_template do
      nil ->
        nil

      template ->
        case TemplateProcessor.process_template(template, context_variables) do
          {:ok, rendered} -> rendered
          {:error, _reason} -> nil
        end
    end
  end

  defp find_system_prompt_template(instructions) do
    # Look for system prompt in instruction metadata or content
    Enum.find_value(instructions, fn instruction ->
      cond do
        Map.has_key?(instruction.metadata, "system_prompt") ->
          Map.get(instruction.metadata, "system_prompt")

        has_system_prompt_section?(instruction) ->
          extract_system_prompt_from_content(instruction.content)

        true ->
          nil
      end
    end)
  end

  defp has_system_prompt_section?(instruction) do
    String.contains?(instruction.content, "## System Prompt") or
      String.contains?(instruction.content, "# System Prompt")
  end

  defp extract_system_prompt_from_content(content) do
    # Extract system prompt from markdown content
    case Regex.run(~r/##?\s*System Prompt\s*\n(.*?)(?=\n##?|\z)/s, content) do
      [_, prompt] -> String.trim(prompt)
      _ -> nil
    end
  end

  defp extract_user_preferences(instructions) do
    # Merge user preferences from multiple instructions
    instructions
    |> Enum.reduce(%{}, fn instruction, acc ->
      preferences = Map.get(instruction.metadata, "preferences", %{})
      Map.merge(acc, preferences)
    end)
  end

  defp extract_context_rules(instructions) do
    # Extract context building rules from instructions
    default_rules = %{
      preferred_strategy: nil,
      max_context_size: nil,
      include_patterns: [],
      exclude_patterns: [],
      retrieval_focus: []
    }

    instructions
    |> Enum.reduce(default_rules, fn instruction, acc ->
      context_config = Map.get(instruction.metadata, "context", %{})
      Map.merge(acc, context_config)
    end)
  end
end
