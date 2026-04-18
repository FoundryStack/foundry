defmodule IgamingRef.Ops.AuditEntry do
  @moduledoc """
  Immutable audit trail entry.

  Records all privileged actions on sensitive resources. Never deleted -
  required for compliance evidence. Includes actor, action, timestamp, and
  affected resource information.

  Compliance: RG-MGA-002 (audit trail requirements)
  """

  use Foundry.Annotations

  @compliance [:RG_MGA_002]
  @telemetry_prefix [:igaming_ref, :ops, :audit_entry]

  use Ash.Resource,
    domain: IgamingRef.Ops,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshArchival.Resource]

  postgres do
    table("audit_entries")
    repo(IgamingRef.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :actor_id, :uuid do
      description("The user or system actor performing the action.")
      allow_nil?(true)
    end

    attribute :actor_type, :string do
      description("Type of actor: 'user', 'system', 'service', etc.")
      allow_nil?(false)
      constraints(max_length: 64)
    end

    attribute :action, :string do
      description("The action performed: 'create', 'update', 'delete', 'suspend', etc.")
      allow_nil?(false)
      constraints(max_length: 128)
    end

    attribute :resource_type, :string do
      description("The resource type affected: 'Player', 'Wallet', 'WithdrawalRequest', etc.")
      allow_nil?(false)
      constraints(max_length: 128)
    end

    attribute :resource_id, :uuid do
      description("The specific resource affected.")
      allow_nil?(false)
    end

    attribute :changes, :map do
      description("JSON map of attribute changes. Nil if no attributes changed.")
      allow_nil?(true)
    end

    attribute :reason, :string do
      description("Why the action was performed. Audit evidence.")
      allow_nil?(true)
      constraints(max_length: 512)
    end

    create_timestamp(:recorded_at)
  end

  actions do
    defaults([:read])

    create :record do
      description("Record an audit entry. Internal use only.")
      accept([
        :actor_id,
        :actor_type,
        :action,
        :resource_type,
        :resource_id,
        :changes,
        :reason
      ])
    end
  end

  policies do
    policy action_type(:read) do
      description("Only compliance officers and operators may read audit logs.")
      authorize_if(always())
    end

    policy action(:record) do
      description("Only the system may create audit entries.")
      authorize_if(always())
    end
  end
end
