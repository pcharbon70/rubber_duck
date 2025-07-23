defmodule Mix.Tasks.RubberDuck.CreateAdmin do
  @moduledoc """
  Creates an admin user with the specified username and password.
  
  ## Usage
  
      mix rubber_duck.create_admin --username USERNAME --password PASSWORD [--email EMAIL]
      
  ## Options
  
    * `--username` - Required. The username for the admin user
    * `--password` - Required. The password for the admin user (minimum 8 characters)
    * `--email` - Optional. The email for the admin user (defaults to username@rubberduck.local)
    
  ## Examples
  
      mix rubber_duck.create_admin --username admin --password supersecret123
      mix rubber_duck.create_admin --username admin --password supersecret123 --email admin@example.com
  """
  
  use Mix.Task
  
  @shortdoc "Creates an admin user with specified credentials"
  
  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")
    
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, 
      strict: [username: :string, password: :string, email: :string]
    )
    
    # Validate required arguments
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)
    email = Keyword.get(opts, :email, "#{username}@rubberduck.local")
    
    cond do
      is_nil(username) ->
        Mix.shell().error("❌ Error: --username is required")
        Mix.shell().info("")
        Mix.shell().info("Usage: mix rubber_duck.create_admin --username USERNAME --password PASSWORD [--email EMAIL]")
        exit(:normal)
        
      is_nil(password) ->
        Mix.shell().error("❌ Error: --password is required")
        Mix.shell().info("")
        Mix.shell().info("Usage: mix rubber_duck.create_admin --username USERNAME --password PASSWORD [--email EMAIL]")
        exit(:normal)
        
      String.length(password) < 8 ->
        Mix.shell().error("❌ Error: Password must be at least 8 characters long")
        exit(:normal)
        
      true ->
        create_admin_user(username, password, email)
    end
  end
  
  defp create_admin_user(username, password, email) do
    require Ash.Query
    
    Mix.shell().info("Creating admin user...")
    
    # Check if user already exists
    existing_user = RubberDuck.Accounts.User
    |> Ash.Query.filter(username: username)
    |> Ash.read_one(authorize?: false)
    
    case existing_user do
      {:ok, user} when not is_nil(user) ->
        Mix.shell().error("❌ Error: User with username '#{username}' already exists")
        Mix.shell().info("   User ID: #{user.id}")
        Mix.shell().info("")
        Mix.shell().info("To reset this user's password, use:")
        Mix.shell().info("   mix rubber_duck.reset_user --username #{username} --password NEW_PASSWORD")
        exit(:normal)
        
      _ ->
        # Create the user
        case create_user(username, password, email) do
          {:ok, user} ->
            Mix.shell().info("✅ Admin user created successfully!")
            Mix.shell().info("   Username: #{user.username}")
            Mix.shell().info("   Email: #{user.email}")
            Mix.shell().info("   User ID: #{user.id}")
            Mix.shell().info("   Confirmed: #{not is_nil(user.confirmed_at)}")
            
          {:error, %Ash.Error.Invalid{errors: errors}} ->
            Mix.shell().error("❌ Failed to create admin user:")
            
            Enum.each(errors, fn error ->
              case error do
                %Ash.Error.Changes.InvalidAttribute{field: field, message: message} ->
                  Mix.shell().error("   #{field}: #{message}")
                _ ->
                  Mix.shell().error("   #{inspect(error)}")
              end
            end)
            
          {:error, error} ->
            Mix.shell().error("❌ Failed to create admin user: #{inspect(error)}")
        end
    end
  end
  
  defp create_user(username, password, email) do
    # First create the user
    case RubberDuck.Accounts.User
         |> Ash.Changeset.for_create(:register_with_password, %{
           username: username,
           email: email,
           password: password,
           password_confirmation: password
         })
         |> Ash.create(authorize?: false) do
      {:ok, user} ->
        # Auto-confirm the admin user by setting confirmed_at directly
        alias RubberDuck.Repo
        import Ecto.Query
        
        {:ok, user_id_binary} = Ecto.UUID.dump(user.id)
        
        case from(u in "users", where: u.id == ^user_id_binary)
             |> Repo.update_all(set: [confirmed_at: DateTime.utc_now()]) do
          {1, _} ->
            # Reload the user to get the updated data
            require Ash.Query
            RubberDuck.Accounts.User
            |> Ash.Query.filter(id == ^user.id)
            |> Ash.read_one!(authorize?: false)
            |> then(&{:ok, &1})
            
          _ ->
            {:error, "Failed to confirm user"}
        end
        
      error ->
        error
    end
  end
end