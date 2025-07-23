defmodule RubberDuck.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `RubberDuck.Accounts` context.
  """

  alias RubberDuck.Accounts.User

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def unique_username, do: "user#{System.unique_integer()}"

  def user_fixture(attrs \\ %{}) do
    # Create the user bypassing policies for test fixtures
    attrs =
      Enum.into(attrs, %{
        email: unique_user_email(),
        username: unique_username(),
        hashed_password: Bcrypt.hash_pwd_salt("password123!")
      })

    User
    |> Ash.Changeset.for_create(:register_with_password, %{
      username: attrs.username,
      email: attrs.email,
      password: "password123!",
      password_confirmation: "password123!"
    })
    |> Ash.create!(authorize?: false)
  end
end
