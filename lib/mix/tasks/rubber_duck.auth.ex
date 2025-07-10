defmodule Mix.Tasks.RubberDuck.Auth do
  @moduledoc """
  Mix task for managing API keys for CLI authentication.

  ## Usage

      mix rubber_duck.auth generate
      mix rubber_duck.auth list
      mix rubber_duck.auth revoke KEY

  ## Examples

      # Generate a new API key
      $ mix rubber_duck.auth generate
      Generated API key: a1b2c3d4e5f6...
      
      # List all API keys
      $ mix rubber_duck.auth list
      
      # Revoke an API key
      $ mix rubber_duck.auth revoke a1b2c3d4e5f6...
  """

  use Mix.Task

  @shortdoc "Manage API keys for CLI authentication"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["generate" | opts] -> generate_key(opts)
      ["list" | opts] -> list_keys(opts)
      ["revoke", key | _] -> revoke_key(key)
      _ -> show_help()
    end
  end

  defp generate_key(opts) do
    description = Keyword.get(parse_opts(opts), :description, "CLI access")
    
    key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    
    # TODO: Store the key in database
    # For now, just display it
    Mix.shell().info("""
    Generated API key: #{key}
    Description: #{description}
    
    Add this key to your CLI configuration:
      rubber_duck auth setup
      
    Or set the RUBBER_DUCK_API_KEY environment variable.
    """)
  end

  defp list_keys(_opts) do
    # TODO: Fetch keys from database
    Mix.shell().info("API Keys:")
    Mix.shell().info("(No keys configured yet)")
  end

  defp revoke_key(key) do
    # TODO: Revoke key in database
    Mix.shell().info("Revoked API key: #{String.slice(key, 0, 8)}...")
  end

  defp show_help do
    Mix.shell().info(@moduledoc)
  end

  defp parse_opts(opts) do
    {parsed, _, _} = OptionParser.parse(opts, 
      switches: [description: :string],
      aliases: [d: :description]
    )
    parsed
  end
end