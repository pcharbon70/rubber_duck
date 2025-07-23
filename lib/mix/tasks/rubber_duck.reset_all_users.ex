defmodule Mix.Tasks.RubberDuck.ResetAllUsers do
  @moduledoc """
  Deletes all existing users and creates a fresh admin user.
  
  ## Usage
  
      mix rubber_duck.reset_all_users --username USERNAME --password PASSWORD [--email EMAIL]
      
  ## Options
  
    * `--username` - Required. The username for the new admin user
    * `--password` - Required. The password for the new admin user (minimum 8 characters)
    * `--email` - Optional. The email for the new admin user (defaults to username@rubberduck.local)
    
  ## Safety
  
  This task will prompt for confirmation before deleting all users unless --force is provided.
  
    * `--force` - Skip confirmation prompt
    
  ## Examples
  
      mix rubber_duck.reset_all_users --username admin --password admin123456
      mix rubber_duck.reset_all_users --username admin --password admin123456 --email admin@example.com --force
  """
  
  use Mix.Task
  
  @shortdoc "Deletes all users and creates a fresh admin user"
  
  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")
    
    # Parse arguments
    {opts, _, _} = OptionParser.parse(args, 
      strict: [username: :string, password: :string, email: :string, force: :boolean]
    )
    
    # Validate required arguments
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)
    email = Keyword.get(opts, :email, "#{username}@rubberduck.local")
    force = Keyword.get(opts, :force, false)
    
    cond do
      is_nil(username) ->
        Mix.shell().error("❌ Error: --username is required")
        Mix.shell().info("")
        Mix.shell().info("Usage: mix rubber_duck.reset_all_users --username USERNAME --password PASSWORD [--email EMAIL]")
        exit(:normal)
        
      is_nil(password) ->
        Mix.shell().error("❌ Error: --password is required")
        Mix.shell().info("")
        Mix.shell().info("Usage: mix rubber_duck.reset_all_users --username USERNAME --password PASSWORD [--email EMAIL]")
        exit(:normal)
        
      String.length(password) < 8 ->
        Mix.shell().error("❌ Error: Password must be at least 8 characters long")
        exit(:normal)
        
      true ->
        if force || confirm_reset() do
          reset_all_users(username, password, email)
        else
          Mix.shell().info("Reset cancelled.")
        end
    end
  end
  
  defp confirm_reset do
    Mix.shell().info("⚠️  WARNING: This will delete ALL users in the database!")
    Mix.shell().info("")
    
    # Show current user count
    alias RubberDuck.Repo
    import Ecto.Query
    
    user_count = from(u in "users") |> Repo.aggregate(:count)
    Mix.shell().info("Current users in database: #{user_count}")
    Mix.shell().info("")
    
    response = Mix.shell().prompt("Are you sure you want to proceed? Type 'yes' to confirm")
    String.trim(response) == "yes"
  end
  
  defp reset_all_users(username, password, email) do
    alias RubberDuck.Repo
    import Ecto.Query
    
    Mix.shell().info("Starting user reset process...")
    
    # Delete all related data first
    try do
      # 1. Delete all tokens
      deleted_tokens = from(t in "tokens") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_tokens, 0)} tokens")
      
      # 2. Delete all API keys
      deleted_api_keys = from(ak in "api_keys") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_api_keys, 0)} API keys")
      
      # 3. Delete all messages
      deleted_messages = from(m in "messages") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_messages, 0)} messages")
      
      # 4. Delete all conversations
      deleted_conversations = from(c in "conversations") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_conversations, 0)} conversations")
      
      # 5. Delete all project security audits
      deleted_audits = from(psa in "project_security_audits") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_audits, 0)} security audit entries")
      
      # 6. Delete all project collaborators
      deleted_collabs = from(pc in "project_collaborators") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_collabs, 0)} project collaborators")
      
      # 7. Delete all code files
      deleted_code_files = from(cf in "code_files") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_code_files, 0)} code files")
      
      # 8. Delete all analysis results
      deleted_analysis = from(ar in "analysis_results") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_analysis, 0)} analysis results")
      
      # 9. Delete all projects
      deleted_projects = from(p in "projects") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_projects, 0)} projects")
      
      # 10. Finally, delete all users
      deleted_users = from(u in "users") |> Repo.delete_all()
      Mix.shell().info("  Deleted #{elem(deleted_users, 0)} users")
      
      Mix.shell().info("")
      Mix.shell().info("✅ All users and related data deleted successfully!")
      Mix.shell().info("")
      
      # Create the new admin user
      Mix.shell().info("Creating new admin user...")
      
      case create_admin_user(username, password, email) do
        {:ok, user} ->
          Mix.shell().info("")
          Mix.shell().info("✅ Admin user created successfully!")
          Mix.shell().info("   Username: #{user.username}")
          Mix.shell().info("   Email: #{user.email}")
          Mix.shell().info("   User ID: #{user.id}")
          Mix.shell().info("   Confirmed: #{not is_nil(user.confirmed_at)}")
          Mix.shell().info("")
          Mix.shell().info("🎉 User reset completed successfully!")
          
        {:error, error} ->
          Mix.shell().error("")
          Mix.shell().error("❌ Failed to create admin user: #{format_error(error)}")
          Mix.shell().error("")
          Mix.shell().error("⚠️  WARNING: Database is now empty! Run this command again or use mix rubber_duck.create_admin to create a user.")
      end
      
    rescue
      e ->
        Mix.shell().error("❌ Error during reset: #{inspect(e)}")
        Mix.shell().error("")
        Mix.shell().error("The database may be in an inconsistent state. Please check manually.")
    end
  end
  
  defp create_admin_user(username, password, email) do
    require Ash.Query
    
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
  
  defp format_error(%Ash.Error.Invalid{errors: errors}) do
    errors
    |> Enum.map(fn error ->
      case error do
        %Ash.Error.Changes.InvalidAttribute{field: field, message: message} ->
          "#{field}: #{message}"
        _ ->
          inspect(error)
      end
    end)
    |> Enum.join(", ")
  end
  
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error)
end