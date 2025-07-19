defmodule RubberDuck.Instructions.SecurityAudit do
  @moduledoc """
  Audit logging resource for security events in the template processing system.

  Records all security-relevant events including successful template processing,
  security violations, rate limiting, and other security-related activities.
  """

  use Ash.Resource,
    otp_app: :rubber_duck,
    domain: RubberDuck.Instructions,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "security_audits"
    repo RubberDuck.Repo
  end

  postgres do
    table "security_audits"
    repo RubberDuck.Repo

    # Indexes for performance
    custom_indexes do
      index [:user_id]
      index [:event_type]
      index [:severity]
      index [:inserted_at]
      index [:user_id, :event_type]
    end
  end

  actions do
    defaults [
      :read,
      create: [:event_type, :user_id, :session_id, :ip_address, :template_hash, :severity, :success, :details]
    ]

    # Custom create action for logging events
    create :log_event do
      accept [:event_type, :user_id, :session_id, :ip_address, :template_hash, :severity, :success, :details]
    end

    # Query actions
    read :find_by_user do
      argument :user_id, :string, allow_nil?: false

      filter expr(user_id == ^arg(:user_id))
    end

    read :find_by_event_type do
      argument :event_type, :atom, allow_nil?: false

      filter expr(event_type == ^arg(:event_type))
    end

    read :recent_events do
      argument :minutes, :integer, default: 60
      argument :limit, :integer, default: 100

      filter expr(inserted_at > ago(^arg(:minutes), :minute))

      prepare build(sort: [inserted_at: :desc], limit: arg(:limit))
    end

    read :find_events do
      argument :user_id, :string
      argument :event_type, :atom
      argument :severity, :atom
      argument :start_date, :datetime
      argument :end_date, :datetime

      filter expr(if not is_nil(^arg(:user_id)), do: user_id == ^arg(:user_id), else: true)

      filter expr(if not is_nil(^arg(:event_type)), do: event_type == ^arg(:event_type), else: true)

      filter expr(if not is_nil(^arg(:severity)), do: severity == ^arg(:severity), else: true)

      filter expr(if not is_nil(^arg(:start_date)), do: inserted_at >= ^arg(:start_date), else: true)

      filter expr(if not is_nil(^arg(:end_date)), do: inserted_at <= ^arg(:end_date), else: true)

      prepare build(sort: [inserted_at: :desc])
    end

    # Cleanup action for old logs
    destroy :cleanup_old_logs do
      argument :days, :integer, default: 30

      filter expr(inserted_at < ago(^arg(:days), :day))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :event_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :template_processed,
                    :security_violation,
                    :injection_attempt,
                    :rate_limit_exceeded,
                    :sandbox_violation,
                    :resource_limit_exceeded,
                    :user_blocked,
                    :anomaly_detected
                  ]
    end

    attribute :user_id, :string do
      public? true
    end

    attribute :session_id, :string do
      public? true
    end

    attribute :ip_address, :string do
      public? true
    end

    attribute :template_hash, :string do
      public? true
    end

    attribute :severity, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:info, :low, :medium, :high, :critical]
    end

    attribute :success, :boolean do
      allow_nil? false
      public? true
    end

    attribute :details, :map do
      public? true
      default %{}
    end

    timestamps()
  end

  identities do
    identity :unique_event, [:user_id, :template_hash, :event_type, :inserted_at]
  end

  # Helper functions for common operations
  def log_event(event_data) do
    RubberDuck.Instructions.SecurityAudit
    |> Ash.Changeset.for_create(:log_event, event_data)
    |> Ash.create()
  end

  def find_events(filters) do
    RubberDuck.Instructions.SecurityAudit
    |> Ash.Query.for_read(:find_events, filters)
    |> Ash.read()
  end

  def recent_events(opts \\ []) do
    RubberDuck.Instructions.SecurityAudit
    |> Ash.Query.for_read(:recent_events, opts)
    |> Ash.read()
  end

  def find_by_user(user_id) do
    RubberDuck.Instructions.SecurityAudit
    |> Ash.Query.for_read(:find_by_user, %{user_id: user_id})
    |> Ash.read()
  end

  def find_by_event_type(event_type) do
    RubberDuck.Instructions.SecurityAudit
    |> Ash.Query.for_read(:find_by_event_type, %{event_type: event_type})
    |> Ash.read()
  end

  def cleanup_old_logs(days_to_keep \\ 30) do
    # Calculate cutoff date
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_to_keep * 86400, :second)

    # Use raw query for now - proper Ash filter would require using the defined destroy action
    case Ash.Query.for_read(__MODULE__, :read) |> Ash.read() do
      {:ok, all_records} ->
        old_records =
          Enum.filter(all_records, fn record ->
            DateTime.compare(record.inserted_at, cutoff_date) == :lt
          end)

        # Delete old records
        deleted_count =
          Enum.reduce(old_records, 0, fn record, count ->
            case Ash.destroy(record) do
              {:ok, _} -> count + 1
              _ -> count
            end
          end)

        {:ok, deleted_count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def all do
    RubberDuck.Instructions.SecurityAudit
    |> Ash.Query.for_read(:read)
    |> Ash.read()
  end
end
