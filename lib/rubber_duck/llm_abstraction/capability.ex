defmodule RubberDuck.LLMAbstraction.Capability do
  @moduledoc """
  Represents a capability or feature that an LLM provider supports.
  
  Capabilities are used for intelligent routing and feature discovery,
  allowing the system to match requests with appropriate providers
  based on required features.
  """

  defstruct [
    :name,
    :type,
    :enabled,
    :version,
    :constraints,
    :metadata
  ]

  @type capability_type :: 
    :chat_completion |
    :text_completion |
    :embeddings |
    :function_calling |
    :vision |
    :streaming |
    :json_mode |
    :system_prompt |
    :multi_turn |
    :context_caching

  @type constraint :: 
    {:max_tokens, pos_integer()} |
    {:max_context_window, pos_integer()} |
    {:supported_models, [String.t()]} |
    {:max_images, pos_integer()} |
    {:max_functions, pos_integer()} |
    {:rate_limit, map()}

  @type t :: %__MODULE__{
    name: atom(),
    type: capability_type(),
    enabled: boolean(),
    version: String.t() | nil,
    constraints: [constraint()],
    metadata: map()
  }

  @doc """
  Define common capabilities with their default constraints.
  """
  def chat_completion(opts \\ []) do
    %__MODULE__{
      name: :chat_completion,
      type: :chat_completion,
      enabled: true,
      version: Keyword.get(opts, :version),
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def text_completion(opts \\ []) do
    %__MODULE__{
      name: :text_completion,
      type: :text_completion,
      enabled: true,
      version: Keyword.get(opts, :version),
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def embeddings(opts \\ []) do
    %__MODULE__{
      name: :embeddings,
      type: :embeddings,
      enabled: true,
      version: Keyword.get(opts, :version),
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def function_calling(opts \\ []) do
    %__MODULE__{
      name: :function_calling,
      type: :function_calling,
      enabled: true,
      version: Keyword.get(opts, :version, "1.0"),
      constraints: Keyword.get(opts, :constraints, [{:max_functions, 128}]),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def vision(opts \\ []) do
    %__MODULE__{
      name: :vision,
      type: :vision,
      enabled: true,
      version: Keyword.get(opts, :version),
      constraints: Keyword.get(opts, :constraints, [{:max_images, 20}]),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  def streaming(opts \\ []) do
    %__MODULE__{
      name: :streaming,
      type: :streaming,
      enabled: true,
      version: Keyword.get(opts, :version),
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Check if a capability satisfies a requirement.
  """
  def satisfies?(capability, requirement) when is_atom(requirement) do
    capability.enabled && capability.name == requirement
  end

  def satisfies?(capability, {requirement, constraints}) when is_atom(requirement) do
    capability.enabled && 
    capability.name == requirement && 
    constraints_satisfied?(capability.constraints, constraints)
  end

  @doc """
  Get a specific constraint value from a capability.
  """
  def get_constraint(capability, constraint_name) do
    Enum.find_value(capability.constraints, fn
      {^constraint_name, value} -> value
      _ -> nil
    end)
  end

  @doc """
  Check if a set of capabilities includes a specific capability.
  """
  def has_capability?(capabilities, capability_name) when is_list(capabilities) do
    Enum.any?(capabilities, &(&1.name == capability_name && &1.enabled))
  end

  @doc """
  Find all capabilities of a specific type.
  """
  def by_type(capabilities, type) when is_list(capabilities) do
    Enum.filter(capabilities, &(&1.type == type && &1.enabled))
  end

  # Private helpers

  defp constraints_satisfied?(capability_constraints, required_constraints) do
    Enum.all?(required_constraints, fn {key, required_value} ->
      case get_constraint_value(capability_constraints, key) do
        nil -> false
        actual_value -> constraint_satisfied?(key, actual_value, required_value)
      end
    end)
  end

  defp get_constraint_value(constraints, key) do
    Enum.find_value(constraints, fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  defp constraint_satisfied?(:max_tokens, actual, required), do: actual >= required
  defp constraint_satisfied?(:max_context_window, actual, required), do: actual >= required
  defp constraint_satisfied?(:max_images, actual, required), do: actual >= required
  defp constraint_satisfied?(:max_functions, actual, required), do: actual >= required
  defp constraint_satisfied?(:supported_models, actual, required) do
    MapSet.subset?(MapSet.new(required), MapSet.new(actual))
  end
  defp constraint_satisfied?(_, _, _), do: true
end

defmodule RubberDuck.LLMAbstraction.CapabilityMatcher do
  @moduledoc """
  Matches requirements with provider capabilities for intelligent routing.
  """

  alias RubberDuck.LLMAbstraction.Capability

  @doc """
  Find providers that satisfy all requirements.
  
  Returns a list of {provider, capabilities} tuples sorted by best match.
  """
  def find_matching_providers(requirements, provider_capabilities) do
    provider_capabilities
    |> Enum.filter(fn {_provider, capabilities} ->
      all_requirements_satisfied?(requirements, capabilities)
    end)
    |> Enum.map(fn {provider, capabilities} ->
      score = calculate_match_score(requirements, capabilities)
      {provider, capabilities, score}
    end)
    |> Enum.sort_by(fn {_, _, score} -> score end, :desc)
    |> Enum.map(fn {provider, capabilities, _} -> {provider, capabilities} end)
  end

  @doc """
  Check if a single provider satisfies requirements.
  """
  def provider_satisfies?(capabilities, requirements) do
    all_requirements_satisfied?(requirements, capabilities)
  end

  # Private helpers

  defp all_requirements_satisfied?(requirements, capabilities) do
    Enum.all?(requirements, fn req ->
      Enum.any?(capabilities, &Capability.satisfies?(&1, req))
    end)
  end

  defp calculate_match_score(requirements, capabilities) do
    # Simple scoring: more capabilities = better
    # Could be enhanced with weighted scoring
    base_score = length(capabilities)
    
    # Bonus for exact matches
    exact_matches = Enum.count(requirements, fn req ->
      req_name = case req do
        atom when is_atom(atom) -> atom
        {atom, _} -> atom
      end
      
      Enum.any?(capabilities, &(&1.name == req_name))
    end)
    
    base_score + (exact_matches * 10)
  end
end