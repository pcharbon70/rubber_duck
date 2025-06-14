defmodule RubberDuck.LLMAbstraction.Capability do
  @moduledoc """
  Capability definition and matching for LLM providers.
  
  This module defines the structure for provider capabilities and provides
  utilities for capability-based provider selection and matching.
  """

  defstruct [:type, :constraints, :metadata]

  @type capability_type :: 
    :chat_completion | 
    :text_completion | 
    :embeddings | 
    :streaming | 
    :function_calling | 
    :multimodal | 
    :fine_tuning |
    :moderation

  @type constraint :: 
    {:max_tokens, pos_integer()} |
    {:max_context_window, pos_integer()} |
    {:supported_models, [String.t()]} |
    {:max_functions, pos_integer()} |
    {:supported_formats, [String.t()]} |
    {:rate_limit_rpm, pos_integer()} |
    {:rate_limit_tpm, pos_integer()}

  @type t :: %__MODULE__{
    type: capability_type(),
    constraints: [constraint()],
    metadata: map()
  }

  @doc """
  Create a chat completion capability.
  """
  def chat_completion(opts \\ []) do
    %__MODULE__{
      type: :chat_completion,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a text completion capability.
  """
  def text_completion(opts \\ []) do
    %__MODULE__{
      type: :text_completion,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create an embeddings capability.
  """
  def embeddings(opts \\ []) do
    %__MODULE__{
      type: :embeddings,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a streaming capability.
  """
  def streaming(opts \\ []) do
    %__MODULE__{
      type: :streaming,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a function calling capability.
  """
  def function_calling(opts \\ []) do
    %__MODULE__{
      type: :function_calling,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a multimodal capability.
  """
  def multimodal(opts \\ []) do
    %__MODULE__{
      type: :multimodal,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a fine-tuning capability.
  """
  def fine_tuning(opts \\ []) do
    %__MODULE__{
      type: :fine_tuning,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Create a content moderation capability.
  """
  def moderation(opts \\ []) do
    %__MODULE__{
      type: :moderation,
      constraints: Keyword.get(opts, :constraints, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Check if a capability matches given requirements.
  """
  def matches?(%__MODULE__{} = capability, requirements) when is_list(requirements) do
    Enum.all?(requirements, fn requirement ->
      matches_single?(capability, requirement)
    end)
  end

  def matches?(%__MODULE__{} = capability, requirement) do
    matches_single?(capability, requirement)
  end

  @doc """
  Get the value of a constraint.
  """
  def get_constraint(%__MODULE__{} = capability, constraint_key) do
    Enum.find_value(capability.constraints, fn
      {^constraint_key, value} -> value
      _ -> nil
    end)
  end

  @doc """
  Check if a capability has a specific constraint.
  """
  def has_constraint?(%__MODULE__{} = capability, constraint_key) do
    Enum.any?(capability.constraints, fn
      {^constraint_key, _} -> true
      _ -> false
    end)
  end

  @doc """
  Add or update a constraint.
  """
  def put_constraint(%__MODULE__{} = capability, constraint_key, value) do
    new_constraints = Keyword.put(capability.constraints, constraint_key, value)
    %{capability | constraints: new_constraints}
  end

  @doc """
  Remove a constraint.
  """
  def delete_constraint(%__MODULE__{} = capability, constraint_key) do
    new_constraints = Keyword.delete(capability.constraints, constraint_key)
    %{capability | constraints: new_constraints}
  end

  # Private Functions

  defp matches_single?(%__MODULE__{type: type}, %__MODULE__{type: type}) do
    true
  end

  defp matches_single?(%__MODULE__{type: provider_type}, %__MODULE__{type: required_type}) do
    # Check for compatible types
    compatible_types(provider_type, required_type)
  end

  defp matches_single?(%__MODULE__{} = capability, {constraint_key, required_value}) do
    case get_constraint(capability, constraint_key) do
      nil -> false
      provider_value -> constraint_satisfied?(constraint_key, provider_value, required_value)
    end
  end

  defp matches_single?(_, _), do: false

  defp compatible_types(:chat_completion, :text_completion), do: true
  defp compatible_types(:text_completion, :chat_completion), do: true
  defp compatible_types(_, _), do: false

  defp constraint_satisfied?(:max_tokens, provider_max, required_max) do
    provider_max >= required_max
  end

  defp constraint_satisfied?(:max_context_window, provider_max, required_max) do
    provider_max >= required_max
  end

  defp constraint_satisfied?(:supported_models, provider_models, required_model) when is_binary(required_model) do
    required_model in provider_models
  end

  defp constraint_satisfied?(:supported_models, provider_models, required_models) when is_list(required_models) do
    Enum.all?(required_models, fn model -> model in provider_models end)
  end

  defp constraint_satisfied?(:max_functions, provider_max, required_max) do
    provider_max >= required_max
  end

  defp constraint_satisfied?(:supported_formats, provider_formats, required_format) when is_binary(required_format) do
    required_format in provider_formats
  end

  defp constraint_satisfied?(:supported_formats, provider_formats, required_formats) when is_list(required_formats) do
    Enum.all?(required_formats, fn format -> format in provider_formats end)
  end

  defp constraint_satisfied?(:rate_limit_rpm, provider_limit, required_limit) do
    provider_limit >= required_limit
  end

  defp constraint_satisfied?(:rate_limit_tpm, provider_limit, required_limit) do
    provider_limit >= required_limit
  end

  defp constraint_satisfied?(_, _, _), do: false
end

defmodule RubberDuck.LLMAbstraction.CapabilityMatcher do
  @moduledoc """
  Advanced capability matching and scoring for provider selection.
  """

  alias RubberDuck.LLMAbstraction.Capability

  @doc """
  Find providers that match the given capability requirements.
  """
  def find_matching_providers(requirements, provider_capabilities) do
    provider_capabilities
    |> Enum.filter(fn {_provider, capabilities} ->
      matches_requirements?(capabilities, requirements)
    end)
    |> Enum.map(fn {provider, _capabilities} -> provider end)
  end

  @doc """
  Calculate match quality between requirements and provider capabilities.
  """
  def calculate_match_quality(requirements, provider_capabilities) do
    if Enum.empty?(requirements) do
      :perfect
    else
      scores = requirements
      |> Enum.map(fn requirement ->
        score_requirement_match(requirement, provider_capabilities)
      end)
      
      average_score = Enum.sum(scores) / length(scores)
      
      cond do
        average_score >= 0.9 -> :perfect
        average_score >= 0.7 -> :good
        average_score >= 0.5 -> :partial
        average_score >= 0.3 -> :minimal
        true -> :none
      end
    end
  end

  @doc """
  Score how well a specific requirement is met by provider capabilities.
  """
  def score_requirement_match(requirement, provider_capabilities) do
    matching_capabilities = provider_capabilities
    |> Enum.filter(fn capability -> Capability.matches?(capability, requirement) end)
    
    if Enum.empty?(matching_capabilities) do
      0.0
    else
      # Score based on how well the best matching capability fulfills the requirement
      best_match = Enum.max_by(matching_capabilities, fn capability ->
        detailed_capability_score(capability, requirement)
      end)
      
      detailed_capability_score(best_match, requirement)
    end
  end

  # Private Functions

  defp matches_requirements?(capabilities, requirements) do
    Enum.all?(requirements, fn requirement ->
      Enum.any?(capabilities, fn capability ->
        Capability.matches?(capability, requirement)
      end)
    end)
  end

  defp detailed_capability_score(capability, requirement) do
    base_score = if Capability.matches?(capability, requirement), do: 0.7, else: 0.0
    
    # Add bonus points for exceeding requirements
    constraint_bonus = calculate_constraint_bonus(capability, requirement)
    
    min(1.0, base_score + constraint_bonus)
  end

  defp calculate_constraint_bonus(%Capability{type: cap_type}, %Capability{type: req_type}) when cap_type == req_type do
    0.3  # Perfect type match bonus
  end

  defp calculate_constraint_bonus(%Capability{} = capability, {constraint_key, required_value}) do
    case Capability.get_constraint(capability, constraint_key) do
      nil -> 0.0
      provider_value -> constraint_bonus(constraint_key, provider_value, required_value)
    end
  end

  defp calculate_constraint_bonus(_, _), do: 0.0

  defp constraint_bonus(:max_tokens, provider_max, required_max) when provider_max > required_max do
    # Bonus for having more tokens than required (up to 0.2)
    min(0.2, (provider_max - required_max) / required_max * 0.1)
  end

  defp constraint_bonus(:max_context_window, provider_max, required_max) when provider_max > required_max do
    # Bonus for larger context window
    min(0.2, (provider_max - required_max) / required_max * 0.1)
  end

  defp constraint_bonus(:rate_limit_rpm, provider_limit, required_limit) when provider_limit > required_limit do
    # Bonus for higher rate limits
    min(0.1, (provider_limit - required_limit) / required_limit * 0.05)
  end

  defp constraint_bonus(_, _, _), do: 0.0
end