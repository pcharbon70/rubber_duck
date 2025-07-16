defmodule RubberDuck.MCP.Client.State do
  @moduledoc """
  State structure for MCP client connections.
  """

  @type transport_config :: 
    {:stdio, command: String.t(), args: [String.t()]} |
    {:http_sse, url: String.t(), headers: map()} |
    {:websocket, url: String.t(), headers: map()}

  @type auth_config ::
    {:oauth2, client_id: String.t(), client_secret: String.t(), token_url: String.t()} |
    {:api_key, key: String.t()} |
    {:certificate, cert: String.t(), key: String.t()}

  @type status :: :initializing | :connecting | :connected | :disconnected | :error

  @type t :: %__MODULE__{
    name: atom(),
    transport: transport_config(),
    capabilities: [atom()],
    auth: auth_config() | nil,
    timeout: pos_integer(),
    auto_reconnect: boolean(),
    connection: any(),
    status: status(),
    last_error: any(),
    connected_at: integer() | nil,
    server_info: map() | nil,
    cached_tools: map() | nil,
    cached_resources: map() | nil,
    cached_prompts: map() | nil
  }

  defstruct [
    :name,
    :transport,
    :capabilities,
    :auth,
    :connection,
    :last_error,
    :connected_at,
    :server_info,
    :cached_tools,
    :cached_resources,
    :cached_prompts,
    timeout: 30_000,
    auto_reconnect: true,
    status: :initializing
  ]
end