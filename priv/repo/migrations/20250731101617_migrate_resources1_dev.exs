defmodule RubberDuck.Repo.Migrations.MigrateResources1 do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    create table(:provenance_relationships, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:parent_request_id, :text, null: false)
      add(:child_request_id, :text, null: false)
      add(:relationship_type, :text, null: false, default: "derived_from")
      add(:sequence_number, :bigint)
      add(:metadata, :map, null: false, default: %{})
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create table(:token_usages, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:provider, :text, null: false)
      add(:model, :text, null: false)
      add(:prompt_tokens, :bigint, null: false)
      add(:completion_tokens, :bigint, null: false)
      add(:total_tokens, :bigint, null: false)
      add(:cost, :decimal, null: false)
      add(:currency, :text, null: false, default: "USD")

      add(
        :user_id,
        references(:users,
          column: :id,
          name: "token_usages_user_id_fkey",
          type: :uuid,
          prefix: "public",
          on_delete: :restrict
        ),
        null: false
      )

      add(:project_id, :uuid)
      add(:team_id, :uuid)
      add(:feature, :text)
      add(:request_id, :text, null: false)
      add(:metadata, :map, null: false, default: %{})
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create unique_index(:token_usages, [:request_id], name: "token_usages_unique_request_id_index")

    create table(:token_provenances, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:request_id, :text, null: false)
      add(:workflow_id, :text)
      add(:task_type, :text, null: false)
      add(:task_name, :text)
      add(:agent_type, :text)
      add(:agent_id, :text)
      add(:input_hash, :text, null: false)
      add(:input_size, :bigint, null: false)
      add(:output_hash, :text)
      add(:output_size, :bigint)
      add(:processing_time_ms, :bigint)
      add(:error_code, :text)
      add(:error_message, :text)
      add(:metadata, :map, null: false, default: %{})
      add(:cached, :boolean, null: false, default: false)

      add(
        :cache_hit_id,
        references(:token_provenances,
          column: :id,
          name: "token_provenances_cache_hit_id_fkey",
          type: :uuid,
          prefix: "public",
          on_delete: :nilify_all
        )
      )

      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create unique_index(:token_provenances, [:request_id], name: "token_provenances_unique_request_id_index")

    alter table(:provenance_relationships) do
      modify :parent_request_id,
             references(:token_provenances,
               column: :request_id,
               name: "provenance_relationships_parent_request_id_fkey",
               type: :text,
               prefix: "public"
             )

      modify :child_request_id,
             references(:token_provenances,
               column: :request_id,
               name: "provenance_relationships_child_request_id_fkey",
               type: :text,
               prefix: "public"
             )
    end

    create unique_index(:provenance_relationships, [:parent_request_id, :child_request_id],
             name: "provenance_relationships_unique_parent_child_index"
           )

    create table(:token_budgets, primary_key: false) do
      add(:id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true)
      add(:name, :text, null: false)
      add(:entity_type, :text, null: false)
      add(:entity_id, :uuid)
      add(:period_type, :text, null: false)
      add(:period_start, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:period_end, :utc_datetime_usec)
      add(:limit_amount, :decimal, null: false)
      add(:current_spending, :decimal, null: false, default: "0")
      add(:currency, :text, null: false, default: "USD")
      add(:is_active, :boolean, null: false, default: true)
      add(:override_active, :boolean, null: false, default: false)
      add(:override_data, :map, null: false, default: %{})
      add(:last_reset, :utc_datetime_usec)
      add(:last_updated, :utc_datetime_usec)
      add(:metadata, :map, null: false, default: %{})
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')"))
    end

    create unique_index(:token_budgets, [:entity_type, :entity_id, :name],
             name: "token_budgets_unique_entity_budget_index"
           )
  end

  def down do
    drop_if_exists(
      unique_index(:token_budgets, [:entity_type, :entity_id, :name], name: "token_budgets_unique_entity_budget_index")
    )

    drop(table(:token_budgets))

    drop_if_exists(
      unique_index(:provenance_relationships, [:parent_request_id, :child_request_id],
        name: "provenance_relationships_unique_parent_child_index"
      )
    )

    drop(constraint(:provenance_relationships, "provenance_relationships_parent_request_id_fkey"))

    drop(constraint(:provenance_relationships, "provenance_relationships_child_request_id_fkey"))

    alter table(:provenance_relationships) do
      modify :child_request_id, :text
      modify :parent_request_id, :text
    end

    drop_if_exists(unique_index(:token_provenances, [:request_id], name: "token_provenances_unique_request_id_index"))

    drop(constraint(:token_provenances, "token_provenances_cache_hit_id_fkey"))

    drop(table(:token_provenances))

    drop_if_exists(unique_index(:token_usages, [:request_id], name: "token_usages_unique_request_id_index"))

    drop(constraint(:token_usages, "token_usages_user_id_fkey"))

    drop(table(:token_usages))

    drop(table(:provenance_relationships))
  end
end
