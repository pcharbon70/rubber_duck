defmodule Mix.Tasks.RubberDuck.ResetUser do
  @moduledoc """
  Resets a user's username and/or password while keeping the same user ID.

  ## Usage

      mix rubber_duck.reset_user --current-username USERNAME [--new-username NEW_USERNAME] [--password NEW_PASSWORD]
      
  ## Options

    * `--current-username` - Required. The current username of the user to reset
    * `--new-username` - Optional. The new username to set
    * `--password` - Optional. The new password to set (minimum 8 characters)
    
  At least one of --new-username or --password must be provided.
    
  ## Examples

      # Reset password only
      mix rubber_duck.reset_user --current-username admin --password newsecret123
      
      # Reset username only  
      mix rubber_duck.reset_user --current-username admin --new-username superadmin
      
      # Reset both username and password
      mix rubber_duck.reset_user --current-username admin --new-username superadmin --password newsecret123
  """

  use Mix.Task

  @shortdoc "Resets a user's username and/or password"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          current_username: :string,
          new_username: :string,
          password: :string
        ],
        aliases: [
          u: :current_username,
          n: :new_username,
          p: :password
        ]
      )

    # Validate arguments
    current_username = Keyword.get(opts, :current_username)
    new_username = Keyword.get(opts, :new_username)
    new_password = Keyword.get(opts, :password)

    cond do
      is_nil(current_username) ->
        Mix.shell().error("❌ Error: --current-username is required")
        Mix.shell().info("")
        show_usage()
        exit(:normal)

      is_nil(new_username) and is_nil(new_password) ->
        Mix.shell().error("❌ Error: At least one of --new-username or --password must be provided")
        Mix.shell().info("")
        show_usage()
        exit(:normal)

      not is_nil(new_password) and String.length(new_password) < 8 ->
        Mix.shell().error("❌ Error: Password must be at least 8 characters long")
        exit(:normal)

      true ->
        reset_user(current_username, new_username, new_password)
    end
  end

  defp show_usage do
    Mix.shell().info(
      "Usage: mix rubber_duck.reset_user --current-username USERNAME [--new-username NEW_USERNAME] [--password NEW_PASSWORD]"
    )

    Mix.shell().info("")
    Mix.shell().info("Examples:")
    Mix.shell().info("  mix rubber_duck.reset_user --current-username admin --password newsecret123")
    Mix.shell().info("  mix rubber_duck.reset_user --current-username admin --new-username superadmin")
  end

  defp reset_user(current_username, new_username, new_password) do
    require Ash.Query

    # Find the user
    user =
      RubberDuck.Accounts.User
      |> Ash.Query.filter(username: current_username)
      |> Ash.read_one(authorize?: false)

    case user do
      {:ok, nil} ->
        Mix.shell().error("❌ Error: User with username '#{current_username}' not found")
        exit(:normal)

      {:ok, user} ->
        Mix.shell().info("Found user:")
        Mix.shell().info("   User ID: #{user.id}")
        Mix.shell().info("   Current username: #{user.username}")
        Mix.shell().info("   Email: #{user.email}")
        Mix.shell().info("")

        # Apply updates
        results = []

        # Update username if provided
        results =
          if new_username do
            case update_username(user, new_username) do
              {:ok, updated_user} ->
                Mix.shell().info("✅ Username updated: #{current_username} → #{new_username}")
                [{:username, :ok, updated_user} | results]

              {:error, error} ->
                Mix.shell().error("❌ Failed to update username: #{format_error(error)}")
                [{:username, :error, error} | results]
            end
          else
            results
          end

        # Get the latest user for password update (in case username changed)
        user =
          case List.keyfind(results, :username, 0) do
            {:username, :ok, updated_user} -> updated_user
            _ -> user
          end

        # Update password if provided
        results =
          if new_password do
            case update_password(user, new_password) do
              {:ok, _updated_user} ->
                Mix.shell().info("✅ Password updated successfully")
                [{:password, :ok} | results]

              {:error, error} ->
                Mix.shell().error("❌ Failed to update password: #{format_error(error)}")
                [{:password, :error, error} | results]
            end
          else
            results
          end

        # Check if all updates succeeded
        errors =
          Enum.filter(results, fn
            {_, :error, _} -> true
            _ -> false
          end)

        if Enum.empty?(errors) do
          Mix.shell().info("")
          Mix.shell().info("✅ User reset completed successfully!")
        else
          Mix.shell().info("")
          Mix.shell().error("⚠️  Some updates failed. Please check the errors above.")
        end

      {:error, error} ->
        Mix.shell().error("❌ Error finding user: #{inspect(error)}")
        exit(:normal)
    end
  end

  defp update_username(user, new_username) do
    require Ash.Query

    # Check if new username is already taken
    existing =
      RubberDuck.Accounts.User
      |> Ash.Query.filter(username == ^new_username and id != ^user.id)
      |> Ash.read_one(authorize?: false)

    case existing do
      {:ok, nil} ->
        # Username is available, update it directly via Ecto
        alias RubberDuck.Repo
        import Ecto.Query

        {:ok, user_id_binary} = Ecto.UUID.dump(user.id)

        case from(u in "users", where: u.id == ^user_id_binary)
             |> Repo.update_all(set: [username: new_username]) do
          {1, _} ->
            # Reload the user to get the updated data
            RubberDuck.Accounts.User
            |> Ash.Query.filter(id == ^user.id)
            |> Ash.read_one!(authorize?: false)
            |> then(&{:ok, &1})

          _ ->
            {:error, "Failed to update username"}
        end

      {:ok, _} ->
        {:error, "Username '#{new_username}' is already taken"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp update_password(user, new_password) do
    # Since we're doing an administrative reset, we need to bypass the
    # change_password action which requires the current password.
    # We'll update the password directly via Ecto.

    # Hash the new password
    hashed_password = Bcrypt.hash_pwd_salt(new_password)

    # Update the user with the new hashed password directly
    alias RubberDuck.Repo
    import Ecto.Query

    {:ok, user_id_binary} = Ecto.UUID.dump(user.id)

    case from(u in "users", where: u.id == ^user_id_binary)
         |> Repo.update_all(set: [hashed_password: hashed_password]) do
      {1, _} ->
        {:ok, user}

      _ ->
        {:error, "Failed to update password"}
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
