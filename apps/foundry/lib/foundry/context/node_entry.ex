defmodule Foundry.Context.NodeEntry do
  @moduledoc """
  The core typed output struct for per-module context queries.
  Mirrors the ModuleContext schema but with extended metadata.

  All fields must be present in every output — use nil or empty collections
  for absent values. Consumers depend on key presence, not existence checks.
  """

  @type state_machine :: %{
          present: boolean(),
          states: [String.t()],
          transitions: [%{from: String.t(), to: String.t(), action: String.t()}],
          state_attribute: String.t() | nil
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

  @derive Jason.Encoder
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
      state_attribute: nil
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
    last_modified: nil
  ]
end

defimpl Jason.Encoder, for: Foundry.Context.NodeEntry do
  @field_order ~w[id module type domain app sensitive description attributes actions
    rules compliance adrs runbook test_coverage data_layer pending_migrations
    paper_trail archival state_machine api_routes telemetry_prefix money_attributes
    authentication_subject oban_queues rate_limited feature_flags steps performs outputs
    agent_steps last_modified]a

  def encode(entry, opts) do
    @field_order
    |> Enum.map(fn key -> {to_string(key), Map.get(entry, key)} end)
    |> Map.new()
    |> Jason.Encode.map(opts)
  end
end
