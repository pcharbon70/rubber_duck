defmodule RubberDuck.Jido.Signals.SignalCategory do
  @moduledoc """
  Defines the standardized signal categories for the RubberDuck platform.
  
  This module provides a taxonomy of signal types with clear semantics,
  enabling consistent signal handling across the system. All signals
  are CloudEvents-compliant through Jido.Signal.
  
  ## Categories
  
  - **Request**: Signals that initiate actions or workflows
  - **Event**: Signals that indicate state changes or occurrences
  - **Command**: Signals that directly command actions
  - **Query**: Signals that request information retrieval
  - **Notification**: Signals that provide alerts or status updates
  """
  
  @type category :: :request | :event | :command | :query | :notification
  
  @type signal_spec :: %{
    category: category(),
    domain: String.t(),
    action: String.t(),
    priority: priority(),
    routing_key: String.t(),
    metadata: map()
  }
  
  @type priority :: :low | :normal | :high | :critical
  
  @categories [:request, :event, :command, :query, :notification]
  
  @doc """
  Returns all available signal categories.
  """
  @spec categories() :: [category()]
  def categories, do: @categories
  
  @doc """
  Validates if a given atom is a valid signal category.
  """
  @spec valid_category?(any()) :: boolean()
  def valid_category?(category) when category in @categories, do: true
  def valid_category?(_), do: false
  
  @doc """
  Returns the semantic definition for a category.
  """
  @spec category_definition(category()) :: String.t()
  def category_definition(:request) do
    "Signals that initiate actions, workflows, or processes. Typically expect a response."
  end
  
  def category_definition(:event) do
    "Signals that indicate something has happened. Past-tense, immutable facts."
  end
  
  def category_definition(:command) do
    "Signals that directly command an action to be taken. Imperative and immediate."
  end
  
  def category_definition(:query) do
    "Signals that request information retrieval. Read-only operations."
  end
  
  def category_definition(:notification) do
    "Signals that provide alerts, warnings, or status updates. Informational."
  end
  
  @doc """
  Returns the typical signal patterns for a category.
  """
  @spec category_patterns(category()) :: [String.t()]
  def category_patterns(:request) do
    ["*.request", "*.request.*", "*.initiate", "*.start", "*.begin"]
  end
  
  def category_patterns(:event) do
    ["*.created", "*.updated", "*.deleted", "*.completed", "*.failed", "*.changed"]
  end
  
  def category_patterns(:command) do
    ["*.execute", "*.run", "*.stop", "*.restart", "*.cancel", "*.pause", "*.resume"]
  end
  
  def category_patterns(:query) do
    ["*.query", "*.fetch", "*.get", "*.list", "*.search", "*.find"]
  end
  
  def category_patterns(:notification) do
    ["*.notify", "*.alert", "*.warning", "*.info", "*.error", "*.status"]
  end
  
  @doc """
  Infers the category from a signal type string.
  
  ## Examples
  
      iex> infer_category("user.created")
      :event
      
      iex> infer_category("analysis.request")
      :request
      
      iex> infer_category("system.alert")
      :notification
  """
  @spec infer_category(String.t()) :: {:ok, category()} | {:error, :unknown_category}
  def infer_category(signal_type) when is_binary(signal_type) do
    lowered = String.downcase(signal_type)
    
    cond do
      matches_patterns?(lowered, category_patterns(:request)) -> {:ok, :request}
      matches_patterns?(lowered, category_patterns(:event)) -> {:ok, :event}
      matches_patterns?(lowered, category_patterns(:command)) -> {:ok, :command}
      matches_patterns?(lowered, category_patterns(:query)) -> {:ok, :query}
      matches_patterns?(lowered, category_patterns(:notification)) -> {:ok, :notification}
      true -> {:error, :unknown_category}
    end
  end
  
  @doc """
  Returns the default priority for a category.
  """
  @spec default_priority(category()) :: priority()
  def default_priority(:request), do: :normal
  def default_priority(:event), do: :normal
  def default_priority(:command), do: :high
  def default_priority(:query), do: :low
  def default_priority(:notification), do: :normal
  
  @doc """
  Creates a signal specification with category metadata.
  """
  @spec create_signal_spec(String.t(), category(), keyword()) :: signal_spec()
  def create_signal_spec(signal_type, category, opts \\ []) do
    [domain, action | _] = String.split(signal_type, ".")
    
    %{
      category: category,
      domain: domain,
      action: action,
      priority: Keyword.get(opts, :priority, default_priority(category)),
      routing_key: Keyword.get(opts, :routing_key, generate_routing_key(domain, category)),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @doc """
  Validates a signal specification.
  """
  @spec validate_signal_spec(map()) :: {:ok, signal_spec()} | {:error, term()}
  def validate_signal_spec(spec) do
    with :ok <- validate_required_fields(spec),
         :ok <- validate_category(spec.category),
         :ok <- validate_priority(spec.priority) do
      {:ok, spec}
    end
  end
  
  # Private functions
  
  defp matches_patterns?(signal_type, patterns) do
    Enum.any?(patterns, fn pattern ->
      regex = pattern
        |> String.replace("*", ".*")
        |> Regex.compile!()
      
      Regex.match?(regex, signal_type)
    end)
  end
  
  defp generate_routing_key(domain, category) do
    "#{domain}.#{category}"
  end
  
  defp validate_required_fields(spec) do
    required = [:category, :domain, :action, :priority, :routing_key]
    missing = required -- Map.keys(spec)
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end
  
  defp validate_category(category) do
    if valid_category?(category) do
      :ok
    else
      {:error, {:invalid_category, category}}
    end
  end
  
  defp validate_priority(priority) when priority in [:low, :normal, :high, :critical], do: :ok
  defp validate_priority(priority), do: {:error, {:invalid_priority, priority}}
end