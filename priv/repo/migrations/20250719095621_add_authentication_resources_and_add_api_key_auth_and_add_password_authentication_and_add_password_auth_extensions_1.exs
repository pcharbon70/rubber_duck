defmodule RubberDuck.Repo.Migrations.AddAuthenticationResourcesAndAddApiKeyAuthAndAddPasswordAuthenticationAndAddPasswordAuthExtensions1 do
  @moduledoc """
  Installs any extensions that are mentioned in the repo's `installed_extensions/0` callback

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS \"citext\"")
  end

  def down do
    # Uncomment this if you actually want to uninstall the extensions
    # when this migration is rolled back:
    # execute("DROP EXTENSION IF EXISTS \"citext\"")
  end
end
