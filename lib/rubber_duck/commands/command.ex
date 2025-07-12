defmodule RubberDuck.Commands.Command do
  @moduledoc """
  Unified command structure used across all client interfaces.
  
  This struct represents a command that can be executed by the system,
  regardless of whether it originated from CLI, WebSocket, LiveView, or TUI.
  """

  @type client_type :: :cli | :liveview | :tui | :websocket
  @type format :: :json | :text | :table | :markdown
  
  @type t :: %__MODULE__{
    name: atom(),
    subcommand: atom() | nil,
    args: map(),
    options: map(),
    context: RubberDuck.Commands.Context.t(),
    client_type: client_type(),
    format: format()
  }
  
  @enforce_keys [:name, :context, :client_type, :format]
  defstruct [
    :name,
    :subcommand,
    :context,
    :client_type,
    :format,
    args: %{},
    options: %{}
  ]

  @doc """
  Creates a new command struct with validation.
  """
  def new(attrs) do
    attrs = Map.new(attrs)
    
    with :ok <- validate_client_type(attrs[:client_type]),
         :ok <- validate_format(attrs[:format]),
         :ok <- validate_name(attrs[:name]) do
      {:ok, struct!(__MODULE__, attrs)}
    end
  end

  defp validate_client_type(type) when type in [:cli, :liveview, :tui, :websocket], do: :ok
  defp validate_client_type(type), do: {:error, "Invalid client_type: #{inspect(type)}"}

  defp validate_format(format) when format in [:json, :text, :table, :markdown], do: :ok
  defp validate_format(format), do: {:error, "Invalid format: #{inspect(format)}"}

  defp validate_name(name) when is_atom(name) and not is_nil(name), do: :ok
  defp validate_name(name), do: {:error, "Invalid name: #{inspect(name)}"}
end