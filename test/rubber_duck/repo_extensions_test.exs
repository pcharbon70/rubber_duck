defmodule RubberDuck.RepoExtensionsTest do
  use RubberDuck.DataCase

  describe "PostgreSQL extensions" do
    test "uuid-ossp extension is enabled" do
      result =
        RubberDuck.Repo.query!("SELECT * FROM pg_extension WHERE extname = 'uuid-ossp'")

      assert length(result.rows) == 1, "uuid-ossp extension should be installed"
    end

    test "pgcrypto extension is enabled" do
      result =
        RubberDuck.Repo.query!("SELECT * FROM pg_extension WHERE extname = 'pgcrypto'")

      assert length(result.rows) == 1, "pgcrypto extension should be installed"
    end

    test "pg_trgm extension is enabled" do
      result =
        RubberDuck.Repo.query!("SELECT * FROM pg_extension WHERE extname = 'pg_trgm'")

      assert length(result.rows) == 1, "pg_trgm extension should be installed"
    end

    test "btree_gin extension is enabled" do
      result =
        RubberDuck.Repo.query!("SELECT * FROM pg_extension WHERE extname = 'btree_gin'")

      assert length(result.rows) == 1, "btree_gin extension should be installed"
    end

    test "vector extension is enabled" do
      result =
        RubberDuck.Repo.query!("SELECT * FROM pg_extension WHERE extname = 'vector'")

      assert length(result.rows) == 1, "vector extension should be installed"
    end

    test "can use uuid_generate_v4() function from uuid-ossp" do
      result = RubberDuck.Repo.query!("SELECT uuid_generate_v4()::text")
      [[uuid]] = result.rows

      assert String.match?(uuid, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/),
             "Should generate valid UUID v4"
    end

    test "can use gen_random_bytes() function from pgcrypto" do
      result = RubberDuck.Repo.query!("SELECT length(gen_random_bytes(16))")
      [[length]] = result.rows

      assert length == 16, "Should generate 16 random bytes"
    end

    test "can use similarity() function from pg_trgm" do
      result = RubberDuck.Repo.query!("SELECT similarity('hello', 'helo')")
      [[similarity]] = result.rows

      # similarity is already a float, not a Decimal
      assert is_float(similarity), "Similarity should be a float"

      assert similarity > 0.0 and similarity <= 1.0,
             "Similarity should be between 0 and 1"
    end

    test "can create vector column type" do
      # Test creating a temporary table with vector column
      RubberDuck.Repo.query!("CREATE TEMP TABLE test_vectors (id serial, embedding vector(3))")

      # Insert a vector
      RubberDuck.Repo.query!("INSERT INTO test_vectors (embedding) VALUES ('[1,2,3]')")

      # Query the vector
      result = RubberDuck.Repo.query!("SELECT embedding::text FROM test_vectors")
      [[vector]] = result.rows

      assert vector == "[1,2,3]", "Should store and retrieve vector correctly"
    end

    test "can calculate vector cosine distance" do
      # Create temp table and insert test vectors
      RubberDuck.Repo.query!("CREATE TEMP TABLE test_similarity (id serial, vec vector(3))")
      RubberDuck.Repo.query!("INSERT INTO test_similarity (vec) VALUES ('[1,0,0]'), ('[0,1,0]')")

      # Calculate cosine distance between orthogonal vectors
      result =
        RubberDuck.Repo.query!("SELECT vec <=> '[1,0,0]'::vector as distance FROM test_similarity ORDER BY distance")

      [[distance1], [distance2]] = result.rows

      # distances are already floats, not Decimals
      assert is_float(distance1), "Distance should be a float"
      assert is_float(distance2), "Distance should be a float"

      assert distance1 == 0.0, "Distance to itself should be 0"
      assert distance2 == 1.0, "Distance between orthogonal vectors should be 1"
    end
  end
end
