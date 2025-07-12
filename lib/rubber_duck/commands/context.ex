defmodule RubberDuck.Commands.Context do
  @moduledoc """
  Context information for command execution.
  
  This struct carries user identification, permissions, and metadata
  that is used for authorization and tracking across all command executions.
  """

  @type t :: %__MODULE__{
    user_id: String.t(),
    project_id: String.t() | nil,
    conversation_id: String.t() | nil,
    session_id: String.t(),
    permissions: list(atom()),
    metadata: map()
  }
  
  @enforce_keys [:user_id, :session_id]
  defstruct [
    :user_id,
    :project_id,
    :conversation_id,
    :session_id,
    permissions: [],
    metadata: %{}
  ]

  @doc """
  Creates a new context struct with validation.
  """
  def new(attrs) do
    attrs = Map.new(attrs)
    
    with :ok <- validate_user_id(attrs[:user_id]),
         :ok <- validate_session_id(attrs[:session_id]),
         :ok <- validate_permissions(attrs[:permissions] || []) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  @doc """
  Checks if the context has a specific permission.
  """
  def has_permission?(%__MODULE__{permissions: permissions}, permission) do
    permission in permissions
  end

  @doc """
  Adds metadata to the context.
  """
  def put_metadata(%__MODULE__{metadata: metadata} = context, key, value) do
    %{context | metadata: Map.put(metadata, key, value)}
  end

  defp validate_user_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
  defp validate_user_id(_), do: {:error, "user_id must be a non-empty string"}

  defp validate_session_id(id) when is_binary(id) and byte_size(id) > 0, do: :ok
  defp validate_session_id(_), do: {:error, "session_id must be a non-empty string"}

  defp validate_permissions(perms) when is_list(perms) do
    if Enum.all?(perms, &is_atom/1) do
      :ok
    else
      {:error, "permissions must be a list of atoms"}
    end
  end
  defp validate_permissions(_), do: {:error, "permissions must be a list"}
end