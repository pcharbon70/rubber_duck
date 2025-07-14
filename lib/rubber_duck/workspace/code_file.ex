defmodule RubberDuck.Workspace.CodeFile do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Workspace,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "code_files"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:file_path, :content, :language, :ast_cache, :embeddings, :project_id]
    end

    update :update do
      accept [:file_path, :content, :language, :ast_cache, :embeddings]
    end

    # Parse AST and store in cache
    update :parse_ast do
      require_atomic? false
      
      argument :force, :boolean do
        allow_nil? true
        default false
      end

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :content) do
          nil ->
            Ash.Changeset.add_error(changeset, field: :content, message: "Content is required for AST parsing")

          content ->
            language = Ash.Changeset.get_attribute(changeset, :language) || detect_language(changeset)

            if should_parse_ast?(changeset, Ash.Changeset.get_argument(changeset, :force)) do
              case parse_ast_for_language(content, language) do
                {:ok, ast_info} ->
                  Ash.Changeset.change_attribute(changeset, :ast_cache, ast_info)

                {:error, reason} ->
                  # Store error in ast_cache metadata
                  error_info = %{
                    "error" => true,
                    "reason" => inspect(reason),
                    "parsed_at" => DateTime.utc_now()
                  }

                  Ash.Changeset.change_attribute(changeset, :ast_cache, error_info)
              end
            else
              changeset
            end
        end
      end
    end

    # Custom semantic search action
    read :semantic_search do
      argument :embedding, {:array, :float} do
        allow_nil? false
      end

      argument :limit, :integer do
        allow_nil? true
        default 10
      end

      # This will need to be implemented with a preparation
      # that uses pgvector for similarity search
      prepare fn query, _context ->
        # TODO: Implement pgvector similarity search
        query
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :file_path, :string do
      allow_nil? false
      public? true
    end

    attribute :content, :string do
      allow_nil? true
      public? true
    end

    attribute :language, :string do
      allow_nil? true
      public? true
    end

    # AST cache stored as JSONB
    attribute :ast_cache, :map do
      allow_nil? true
      default %{}
      public? true
    end

    # Embeddings stored as vector array
    attribute :embeddings, {:array, :float} do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, RubberDuck.Workspace.Project do
      allow_nil? false
      attribute_type :uuid
      attribute_writable? true
    end

    has_many :analysis_results, RubberDuck.Workspace.AnalysisResult
  end

  # Private helper functions

  defp should_parse_ast?(changeset, force) do
    force ||
      Ash.Changeset.changing_attribute?(changeset, :content) ||
      is_nil(Ash.Changeset.get_attribute(changeset, :ast_cache)) ||
      Map.get(Ash.Changeset.get_attribute(changeset, :ast_cache) || %{}, "error", false)
  end

  defp detect_language(changeset) do
    file_path = Ash.Changeset.get_attribute(changeset, :file_path)

    cond do
      String.ends_with?(file_path, ".ex") || String.ends_with?(file_path, ".exs") -> "elixir"
      String.ends_with?(file_path, ".js") || String.ends_with?(file_path, ".jsx") -> "javascript"
      String.ends_with?(file_path, ".ts") || String.ends_with?(file_path, ".tsx") -> "typescript"
      true -> "unknown"
    end
  end

  defp parse_ast_for_language(content, "elixir") do
    case RubberDuck.Analysis.AST.parse(content, :elixir) do
      {:ok, ast_info} ->
        # Convert to JSON-serializable format
        {:ok, serialize_ast_info(ast_info)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_ast_for_language(_content, language) when language in ["javascript", "typescript"] do
    {:error, :not_implemented_yet}
  end

  defp parse_ast_for_language(_content, _language) do
    {:error, :unsupported_language}
  end

  defp serialize_ast_info(ast_info) do
    %{
      "type" => to_string(ast_info.type),
      "name" => if(ast_info.name, do: to_string(ast_info.name), else: nil),
      "functions" => Enum.map(ast_info.functions, &serialize_function/1),
      "aliases" => Enum.map(ast_info.aliases, &to_string/1),
      "imports" => Enum.map(ast_info.imports, &to_string/1),
      "requires" => Enum.map(ast_info.requires, &to_string/1),
      "calls" => Enum.map(ast_info.calls, &serialize_call/1),
      "parsed_at" => DateTime.utc_now()
    }
  end

  defp serialize_function(func) do
    %{
      "name" => to_string(func.name),
      "arity" => func.arity,
      "line" => func.line,
      "private" => func.private
    }
  end

  defp serialize_call(call) do
    %{
      "from" => serialize_mfa(call.from),
      "to" => serialize_mfa(call.to),
      "line" => call.line
    }
  end

  defp serialize_mfa({module, function, arity}) do
    %{
      "module" => to_string(module),
      "function" => to_string(function),
      "arity" => arity
    }
  end
end
