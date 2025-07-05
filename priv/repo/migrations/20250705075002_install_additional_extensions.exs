defmodule RubberDuck.Repo.Migrations.InstallAdditionalExtensions do
  use Ecto.Migration

  def up do
    # Enable UUID generation extension
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
    
    # Enable encryption support
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"
    
    # Enable trigram similarity search
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    
    # Enable GIN index support for btree
    execute "CREATE EXTENSION IF NOT EXISTS btree_gin"
    
    # Enable pgvector for embeddings
    execute "CREATE EXTENSION IF NOT EXISTS vector"
  end

  def down do
    # Note: Dropping extensions can be dangerous if data depends on them
    # Only uncomment if you're sure you want to remove these extensions
    
    # execute "DROP EXTENSION IF EXISTS vector"
    # execute "DROP EXTENSION IF EXISTS btree_gin"
    # execute "DROP EXTENSION IF EXISTS pg_trgm"
    # execute "DROP EXTENSION IF EXISTS pgcrypto"
    # execute "DROP EXTENSION IF EXISTS \"uuid-ossp\""
  end
end