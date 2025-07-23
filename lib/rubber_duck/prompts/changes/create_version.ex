defmodule RubberDuck.Prompts.Changes.CreateVersion do
  use Ash.Resource.Change
  alias RubberDuck.Prompts.PromptVersion

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data do
        %{id: id, content: old_content} when not is_nil(id) ->
          # Get the current highest version number
          version_number =
            case get_latest_version_number(id) do
              nil -> 1
              num -> num + 1
            end

          # Create version record with old content
          version_attrs = %{
            prompt_id: id,
            version_number: version_number,
            content: old_content,
            variables_schema: changeset.data.template_variables,
            change_description: "Version #{version_number}",
            created_by_id: changeset.context[:private][:actor].id
          }

          case Ash.create(PromptVersion, version_attrs, authorize?: false) do
            {:ok, _version} ->
              changeset

            {:error, error} ->
              Ash.Changeset.add_error(changeset, field: :base, message: "Failed to create version: #{inspect(error)}")
          end

        _ ->
          # New prompt, no version needed
          changeset
      end
    end)
  end

  defp get_latest_version_number(prompt_id) do
    PromptVersion
    |> Ash.Query.filter(prompt_id: prompt_id)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> nil
      version -> version.version_number
    end
  end
end
