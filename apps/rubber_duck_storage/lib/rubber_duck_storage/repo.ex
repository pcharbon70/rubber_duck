defmodule RubberDuckStorage.Repo do
  use Ecto.Repo,
    otp_app: :rubber_duck_storage,
    adapter: Ecto.Adapters.Postgres
end
