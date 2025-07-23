defmodule RubberDuck.Prompts.PromptTag do
  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Prompts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "prompts_tags"
    repo RubberDuck.Repo
  end

  actions do
    defaults [:create, :read, :update, :destroy]
  end

  relationships do
    belongs_to :prompt, RubberDuck.Prompts.Prompt do
      primary_key? true
      allow_nil? false
    end

    belongs_to :tag, RubberDuck.Prompts.Tag do
      primary_key? true
      allow_nil? false
    end
  end
end
