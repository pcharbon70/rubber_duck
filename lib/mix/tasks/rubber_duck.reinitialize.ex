defmodule Mix.Tasks.RubberDuck.Reinitialize do
  @moduledoc """
  Drops both dev and test databases and re-runs the setup.

  ## Usage

      mix rubber_duck.reinitialize [OPTIONS]
      
  ## Options

    * `--force` - Skip confirmation prompt
    * `--create-admin` - Create an admin user after setup
    * `--username` - Username for admin user (required with --create-admin)
    * `--password` - Password for admin user (required with --create-admin)
    * `--email` - Email for admin user (optional, defaults to username@rubberduck.local)
    
  ## Examples

      # Basic usage with confirmation
      mix rubber_duck.reinitialize
      
      # Skip confirmation
      mix rubber_duck.reinitialize --force
      
      # Create admin user after setup
      mix rubber_duck.reinitialize --create-admin --username admin --password admin123456
      
      # Full example with all options
      mix rubber_duck.reinitialize --force --create-admin --username admin --password admin123456 --email admin@example.com
  """

  use Mix.Task

  @shortdoc "Drops dev/test databases and re-runs setup"

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          force: :boolean,
          create_admin: :boolean,
          username: :string,
          password: :string,
          email: :string
        ]
      )

    force = Keyword.get(opts, :force, false)
    create_admin = Keyword.get(opts, :create_admin, false)

    # Validate admin options if --create-admin is provided
    if create_admin do
      username = Keyword.get(opts, :username)
      password = Keyword.get(opts, :password)

      cond do
        is_nil(username) ->
          Mix.shell().error("❌ Error: --username is required when using --create-admin")
          exit(:normal)

        is_nil(password) ->
          Mix.shell().error("❌ Error: --password is required when using --create-admin")
          exit(:normal)

        String.length(password) < 8 ->
          Mix.shell().error("❌ Error: Password must be at least 8 characters long")
          exit(:normal)

        true ->
          :ok
      end
    end

    # Get database configuration
    dev_config = Application.get_env(:rubber_duck, RubberDuck.Repo, [])
    dev_db = Keyword.get(dev_config, :database, "rubber_duck_dev")

    # For test, we need to consider MIX_ENV
    test_db_base = "rubber_duck_test"

    if force || confirm_reinitialize(dev_db, test_db_base) do
      reinitialize_databases(opts)
    else
      Mix.shell().info("Reinitialization cancelled.")
    end
  end

  defp confirm_reinitialize(dev_db, test_db_base) do
    Mix.shell().info("⚠️  WARNING: This will DROP the following databases:")
    Mix.shell().info("")
    Mix.shell().info("   Development: #{dev_db}")
    Mix.shell().info("   Test: #{test_db_base} (and any partitions)")
    Mix.shell().info("")
    Mix.shell().info("All data will be permanently lost!")
    Mix.shell().info("")

    response = Mix.shell().prompt("Are you sure you want to proceed? Type 'yes' to confirm")
    String.trim(response) == "yes"
  end

  defp reinitialize_databases(opts) do
    Mix.shell().info("Starting database reinitialization...")
    Mix.shell().info("")

    # Step 1: Drop test database
    Mix.shell().info("1️⃣  Dropping test database...")

    case Mix.shell().cmd("MIX_ENV=test mix ecto.drop") do
      0 ->
        Mix.shell().info("   ✅ Test database dropped")

      _ ->
        Mix.shell().error("   ⚠️  Failed to drop test database (it might not exist)")
    end

    # Step 2: Drop dev database
    Mix.shell().info("")
    Mix.shell().info("2️⃣  Dropping development database...")

    case Mix.shell().cmd("MIX_ENV=dev mix ecto.drop") do
      0 ->
        Mix.shell().info("   ✅ Development database dropped")

      _ ->
        Mix.shell().error("   ⚠️  Failed to drop dev database (it might not exist)")
    end

    # Step 3: Run ash.setup (which creates databases and runs migrations)
    Mix.shell().info("")
    Mix.shell().info("3️⃣  Running ash.setup (creates databases and runs migrations)...")

    case Mix.shell().cmd("mix ash.setup") do
      0 ->
        Mix.shell().info("   ✅ Setup completed successfully")

      exit_code ->
        Mix.shell().error("   ❌ Setup failed with exit code: #{exit_code}")
        exit({:shutdown, 1})
    end

    # Step 4: Create admin user if requested
    if Keyword.get(opts, :create_admin, false) do
      Mix.shell().info("")
      Mix.shell().info("4️⃣  Creating admin user...")

      username = Keyword.get(opts, :username)
      password = Keyword.get(opts, :password)
      email = Keyword.get(opts, :email, "#{username}@rubberduck.local")

      # Build the command
      cmd = "mix rubber_duck.create_admin --username #{username} --password #{password} --email #{email}"

      case Mix.shell().cmd(cmd) do
        0 ->
          Mix.shell().info("   ✅ Admin user created")

        exit_code ->
          Mix.shell().error("   ❌ Failed to create admin user (exit code: #{exit_code})")
      end
    end

    # Success message
    Mix.shell().info("")
    Mix.shell().info("🎉 Database reinitialization completed!")
    Mix.shell().info("")
    Mix.shell().info("Your databases have been recreated with fresh schema.")

    if Keyword.get(opts, :create_admin, false) do
      username = Keyword.get(opts, :username)
      Mix.shell().info("Admin user '#{username}' is ready to use.")
    else
      Mix.shell().info("Run 'mix rubber_duck.create_admin' to create an admin user.")
    end
  end
end
