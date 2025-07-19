defmodule RubberDuck.MCP.Capability do
  @moduledoc """
  Manages MCP server capabilities and negotiation.

  Capabilities define what features the MCP server supports. During
  the initialization handshake, the server advertises its capabilities
  to the client, which helps the client understand what operations
  are available.

  ## Standard Capabilities

  - **tools**: Tool discovery and execution
  - **resources**: Resource listing and reading
  - **prompts**: Prompt templates
  - **logging**: Logging configuration
  - **experimental**: Experimental features
  """

  @doc """
  Builds the default server capabilities.

  Returns a map of capability names to their configuration.
  """
  def default_capabilities do
    %{
      "tools" => %{
        # Server can notify when tool list changes
        "listChanged" => true
      },
      "resources" => %{
        # Clients can subscribe to resource changes
        "subscribe" => true,
        # Server can notify when resource list changes
        "listChanged" => true
      },
      "prompts" => %{
        # Server can notify when prompt list changes
        "listChanged" => true
      },
      "logging" =>
        %{
          # Logging capabilities
        },
      "experimental" => %{
        # Support for streaming responses
        "streaming" => true
      }
    }
  end

  @doc """
  Merges custom capabilities with defaults.

  Custom capabilities override default ones.
  """
  def merge_capabilities(custom_capabilities) do
    Map.merge(default_capabilities(), custom_capabilities)
  end

  @doc """
  Validates that requested client capabilities are supported.

  Returns {:ok, negotiated_capabilities} or {:error, unsupported_capabilities}.
  """
  def negotiate_capabilities(server_capabilities, _client_capabilities) do
    # For now, simple negotiation - we support what we advertise
    # In future, could validate specific client requirements
    {:ok, server_capabilities}
  end

  @doc """
  Checks if a specific capability is enabled.
  """
  def capability_enabled?(capabilities, path) when is_binary(path) do
    capability_enabled?(capabilities, String.split(path, "."))
  end

  def capability_enabled?(capabilities, [key | rest]) when is_map(capabilities) do
    case Map.get(capabilities, key) do
      nil -> false
      value when rest == [] -> truthy?(value)
      nested when is_map(nested) -> capability_enabled?(nested, rest)
      _ -> false
    end
  end

  def capability_enabled?(_, _), do: false

  @doc """
  Gets the server information to include in initialization response.
  """
  def server_info do
    %{
      "name" => "RubberDuck MCP Server",
      "version" => version(),
      "vendor" => "RubberDuck AI"
    }
  end

  @doc """
  Gets the protocol version supported by this server.
  """
  def protocol_version do
    "2024-11-05"
  end

  @doc """
  Validates protocol version compatibility.

  Returns true if the client version is compatible with server version.
  """
  def compatible_version?(client_version, server_version \\ protocol_version()) do
    # For now, exact match required
    # In future, implement semantic version comparison
    client_version == server_version
  end

  # Private functions

  defp version do
    case :application.get_key(:rubber_duck, :vsn) do
      {:ok, vsn} -> to_string(vsn)
      _ -> "0.1.0"
    end
  end

  defp truthy?(true), do: true
  defp truthy?(%{} = map) when map_size(map) > 0, do: true
  defp truthy?(_), do: false
end
