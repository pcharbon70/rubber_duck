defmodule Mix.Tasks.CreateDefaultUser do
  @moduledoc """
  Creates a default user with username 'duck' and password 'duckduck'.
  
  ## Usage
  
      mix create_default_user
      
  ## Default credentials
  
  - Username: duck
  - Email: duck@rubberduck.local  
  - Password: duckduck
  """
  
  use Mix.Task
  
  @shortdoc "Creates a default user (username: duck, password: duckduck)"
  
  @impl Mix.Task
  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")
    
    # Create the user
    case create_default_user() do
      {:ok, user} ->
        Mix.shell().info("✅ Default user created successfully!")
        Mix.shell().info("   Username: duck")
        Mix.shell().info("   Email: duck@rubberduck.local")
        Mix.shell().info("   Password: duckduck")
        Mix.shell().info("   User ID: #{user.id}")
        
      {:error, %Ash.Error.Invalid{errors: errors}} ->
        Mix.shell().error("❌ Failed to create default user:")
        
        Enum.each(errors, fn error ->
          case error do
            %Ash.Error.Changes.InvalidAttribute{field: field, message: message} ->
              Mix.shell().error("   #{field}: #{message}")
            _ ->
              Mix.shell().error("   #{inspect(error)}")
          end
        end)
        
      {:error, error} ->
        Mix.shell().error("❌ Failed to create default user: #{inspect(error)}")
    end
  end
  
  defp create_default_user do
    RubberDuck.Accounts.User
    |> Ash.Changeset.for_create(:register_with_password, %{
      username: "duck",
      email: "duck@rubberduck.local",
      password: "duckduck",
      password_confirmation: "duckduck"
    })
    |> Ash.create(authorize?: false)
  end
end