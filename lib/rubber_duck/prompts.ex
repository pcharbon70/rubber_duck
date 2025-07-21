defmodule RubberDuck.Prompts do
  use Ash.Domain,
    otp_app: :rubber_duck
    
  require Ash.Query

  def list_prompt_versions(prompt_id, opts \\ []) do
    actor = Keyword.get(opts, :actor)
    
    # First check if the user owns the prompt
    case get_prompt(prompt_id, actor: actor) do
      {:ok, _prompt} ->
        RubberDuck.Prompts.PromptVersion
        |> Ash.Query.filter(prompt_id: prompt_id)
        |> Ash.Query.sort(version_number: :desc)
        |> Ash.read(actor: actor)
      
      error -> error
    end
  end

  resources do
    resource RubberDuck.Prompts.Prompt do
      define :create_prompt, action: :create
      define :get_prompt, action: :read, get_by: [:id]
      define :list_prompts, action: :read
      define :update_prompt, action: :update
      define :delete_prompt, action: :destroy
      define :search_prompts, action: :search, args: [:query]
    end

    resource RubberDuck.Prompts.PromptVersion do
      define :get_version, action: :read, get_by: [:id]
      define :list_versions, action: :read
    end

    resource RubberDuck.Prompts.Category do
      define :create_category, action: :create
      define :get_category, action: :read, get_by: [:id]
      define :list_categories, action: :read
      define :update_category, action: :update
      define :delete_category, action: :destroy
    end

    resource RubberDuck.Prompts.Tag do
      define :create_tag, action: :create
      define :get_tag, action: :read, get_by: [:id]
      define :list_tags, action: :read
      define :update_tag, action: :update
      define :delete_tag, action: :destroy
    end

    resource RubberDuck.Prompts.PromptCategory
    resource RubberDuck.Prompts.PromptTag
  end
end