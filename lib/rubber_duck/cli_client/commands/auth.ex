defmodule RubberDuck.CLIClient.Commands.Auth do
  @moduledoc """
  Authentication command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Auth

  def run(args, opts) do
    case args do
      %{subcommand: {subcommand, subargs}} ->
        handle_subcommand(subcommand, subargs, opts)
        
      _ ->
        handle_subcommand(:status, %{}, opts)
    end
  end

  defp handle_subcommand(:setup, args, _opts) do
    server_url = args[:server] || prompt_server_url()
    api_key = prompt_api_key() || Auth.generate_api_key()
    
    case Auth.save_credentials(api_key, server_url) do
      :ok ->
        IO.puts("""
        Authentication configured successfully!
        
        Server: #{server_url}
        API Key: #{api_key}
        
        Your credentials have been saved to ~/.rubber_duck/config.json
        
        To use the CLI, the server must be configured to accept this API key.
        Add it to your server's configuration or environment variables.
        """)
        
      {:error, reason} ->
        IO.puts(:stderr, "Failed to save credentials: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp handle_subcommand(:status, _args, _opts) do
    if Auth.configured?() do
      api_key = Auth.get_api_key()
      server_url = Auth.get_server_url()
      
      # Mask API key for security
      masked_key = if api_key do
        String.slice(api_key, 0, 8) <> "..." <> String.slice(api_key, -4, 4)
      else
        "Not configured"
      end
      
      IO.puts("""
      Authentication Status:
      
      Configured: Yes
      Server: #{server_url}
      API Key: #{masked_key}
      Config Location: ~/.rubber_duck/config.json
      """)
    else
      IO.puts("""
      Authentication Status:
      
      Configured: No
      
      Run 'rubber_duck auth setup' to configure authentication.
      """)
    end
  end

  defp handle_subcommand(:clear, _args, _opts) do
    case Auth.clear_credentials() do
      :ok ->
        IO.puts("Authentication credentials cleared successfully.")
        
      {:error, reason} ->
        IO.puts(:stderr, "Failed to clear credentials: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp prompt_server_url do
    default = "ws://localhost:4000/socket/websocket"
    
    IO.gets("Enter RubberDuck server URL [#{default}]: ")
    |> String.trim()
    |> case do
      "" -> default
      url -> url
    end
  end

  defp prompt_api_key do
    IO.gets("Enter API key (leave blank to generate): ")
    |> String.trim()
    |> case do
      "" -> nil
      key -> key
    end
  end
end