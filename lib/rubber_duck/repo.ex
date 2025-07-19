defmodule RubberDuck.Repo do
  use AshPostgres.Repo, otp_app: :rubber_duck

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end

  # Don't open unnecessary transactions
  # will default to `false` in 4.0
  def prefer_transaction? do
    false
  end

  def installed_extensions do
    # Add extensions here, and the migration generator will install them.
    [
      "ash-functions",
      # UUID generation
      "uuid-ossp",
      # Encryption support
      "pgcrypto",
      # Trigram similarity search
      "pg_trgm",
      # GIN index support
      "btree_gin",
      # pgvector for embeddings
      "vector",
      "citext"
    ]
  end
end
