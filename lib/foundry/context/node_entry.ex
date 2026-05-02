defmodule Foundry.Context.NodeEntry do
  @moduledoc """
  The core typed output struct for per-module context queries.
  Mirrors the ModuleContext schema but with extended metadata.

  Serialized with compact encoding: nil, false, [], and "" values are filtered out
  at any nesting depth. This optimizes LLM context while future-proofing stub fields
  (Phase B/D features appear automatically when populated).
  """

  @derive Jason.Encoder

  @type state_machine :: %{
          present: boolean(),
          states: [String.t()],
          transitions: [%{from: String.t(), to: String.t(), action: String.t()}],
          state_attribute: String.t() | nil,
          initial_states: [String.t()],
          default_initial_state: String.t() | nil,
          terminal_states: [String.t()]
        }

  @type relationship :: %{
          name: String.t(),
          type: :belongs_to | :has_many | :has_one | :many_to_many,
          related_resource: String.t(),
          source_attribute: String.t() | nil,
          destination_attribute: String.t() | nil,
          description: String.t() | nil
        }

  @type auth_strategy :: %{
          strategy_name: String.t(),
          strategy_type: :password | :magic_link | :oauth2 | :api_key | :other,
          identity_field: String.t() | nil,
          token_resource: String.t() | nil,
          has_sign_in_tokens: boolean(),
          has_password_reset: boolean()
        }

  @type money_attribute :: %{
          name: String.t(),
          type: String.t(),
          cldr_backend: String.t()
        }

  @type test_coverage :: %{
          property_tests: boolean(),
          scenario_tests: boolean(),
          e2e_tests: boolean()
        }

  @type agent_step :: %{
          step_id: String.t(),
          agent_type: String.t(),
          model: String.t(),
          input_schema: String.t() | nil,
          output_schema: String.t() | nil,
          tools: [String.t()],
          confidence_threshold: float() | nil,
          on_low_confidence: String.t() | nil,
          human_gate: map() | nil,
          telemetry_prefix: [String.t()]
        }

  @enforce_keys [:module, :type, :domain, :description]
  defstruct [
    # Required fields
    :module,
    :type,
    :domain,
    :description,
    # Optional fields with defaults
    id: nil,
    app: nil,
    sensitive: false,
    attributes: [],
    actions: [],
    steps: [],
    rules: [],
    compliance: [],
    adrs: [],
    runbook: nil,
    test_coverage: %{
      property_tests: false,
      scenario_tests: false,
      e2e_tests: false
    },
    data_layer: nil,
    pending_migrations: false,
    paper_trail: false,
    archival: false,
    state_machine: %{
      present: false,
      states: [],
      transitions: [],
      state_attribute: nil,
      initial_states: [],
      default_initial_state: nil,
      terminal_states: []
    },
    api_routes: [],
    telemetry_prefix: [],
    money_attributes: [],
    authentication_subject: false,
    oban_queues: [],
    rate_limited: false,
    feature_flags: [],
    performs: nil,
    outputs: [],
    agent_steps: [],
    last_modified: nil,
    relationships: [],
    auth_strategies: [],
    side_effects: [],
    trigger_kind: nil,
    rule_compliance_links: [],
    # Phase B extensions
    scenario_origins: [],
    graphql_mutations: [],
    json_api_routes: [],
    vectorized: false
  ]
end
