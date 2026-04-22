defmodule Foundry.SparkMeta.ModuleInfo do
  @moduledoc """
  Output struct from `Foundry.SparkMeta.walk/1`.

  Mirrors the NodeEntry schema fields that SparkMeta can derive without
  manifest-specific context. Fields like `:sensitive` are added later by
  `Foundry.Context.NodeBuilder`.
  """

  @derive Jason.Encoder
  @enforce_keys [:module]
  defstruct [
    :module,
    type: nil,
    description: nil,
    attributes: [],
    actions: [],
    rules: [],
    compliance: [],
    adrs: [],
    runbook: nil,
    data_layer: nil,
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
    steps: [],
    outputs: [],
    agent_steps: [],
    performs: nil,
    last_modified: nil,
    relationships: [],
    auth_strategies: [],
    side_effects: [],
    trigger_kind: nil,
    diagnostics: []
  ]

  @type t :: %__MODULE__{}
end

defmodule Foundry.SparkMeta.Attribute do
  @moduledoc "Structured representation of an Ash resource attribute."
  @derive Jason.Encoder
  defstruct [:name, :type, :description, pii: false, sensitive: false, money: false, cldr_backend: nil]
end

defmodule Foundry.SparkMeta.Action do
  @moduledoc "Structured representation of an Ash resource action."
  @derive Jason.Encoder
  defstruct [:name, :type, :description]
end

defmodule Foundry.SparkMeta.StepEntry do
  @moduledoc """
  Structured representation of a Reactor step.
  """

  @derive Jason.Encoder
  defstruct [
    :name,
    :type,
    :description,
    :target_module,
    step_index: nil,
    wait_for: [],
    has_compensation: false,
    target_resource: nil,
    target_action: nil,
    step_kind: nil,
    rules_applied: [],
    source_snippet: nil,
    read_targets: [],
    write_targets: [],
    fact_provenance: %{},
    step_model: nil,
    confidence_threshold: nil,
    on_low_confidence: nil,
    step_tools: [],
    step_telemetry_prefix: [],
    side_effects: []
  ]
end

defmodule Foundry.SparkMeta.SideEffectEntry do
  @moduledoc """
  Structured representation of a side effect.
  """

  @derive Jason.Encoder
  defstruct [
    :type,
    :name,
    :declared_on,
    :idempotency_key_from,
    :step_name,
    :action,
    :job_module,
    :module,
    :queue,
    :trigger,
    idempotent: false,
    declared: false,
    epistemic: "VERIFIED"
  ]
end

defmodule Foundry.SparkMeta.StepFacts do
  @moduledoc false

  defstruct [
    read_targets: [],
    write_targets: [],
    rules_applied: [],
    policy_checks: [],
    queue_targets: [],
    external_calls: [],
    output_resources: %{},
    direct_result_resources: [],
    variable_resources: %{},
    helper_results: %{},
    provenance: %{
      reads: %{},
      writes: %{},
      rules: %{},
      policies: %{},
      queues: %{},
      external_calls: %{}
    }
  ]
end

defmodule Foundry.SparkMeta.SourceContext do
  @moduledoc false

  defstruct [:module, :source_text, :module_source, alias_map: %{}, step_sources: %{}, helper_sources: %{}]
end

defmodule Foundry.SparkMeta.MoneyAttr do
  @moduledoc "Structured representation of a monetary attribute."
  @derive Jason.Encoder
  defstruct [:name, :type, :cldr_backend]
end

defmodule Foundry.SparkMeta.Relationship do
  @moduledoc "Structured representation of an Ash resource relationship."
  @derive Jason.Encoder
  defstruct [:name, :type, :related_resource, :source_attribute, :destination_attribute, :description]
end

defmodule Foundry.SparkMeta.AuthStrategy do
  @moduledoc "Structured representation of an AshAuthentication strategy."
  @derive Jason.Encoder
  defstruct [:strategy_name, :strategy_type, :identity_field, :token_resource, :has_sign_in_tokens, :has_password_reset]
end
