defmodule ExTracer.Step do
  @moduledoc """
  A single meaningful call or assertion captured from test code.

  Steps are the atomic building blocks of scenarios. Each step represents a
  classifiable action: an API call, database query, assertion, or helper
  invocation. They carry metadata for linking to AST source, runtime traces,
  and domain-specific focus nodes — and flow information like dependencies
  (`:reacts_to`) and emissions (`:emits`).

  Steps are created by `ExTracer.FlowExpander` using `ExTracer.Adapter` implementations
  to classify calls in test ASTs. At runtime, their execution is tracked by `ExTracer.CallTracer`
  and matched against persisted traces by `ExTracer.TraceStore` implementations.
  """

  @derive Jason.Encoder

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: atom() | String.t(),
          kind: atom() | String.t() | nil,
          label: String.t() | nil,
          node_id: String.t() | nil,
          focus_node_id: String.t() | nil,
          focus_targets: [String.t()],
          emits: [String.t()],
          reacts_to: String.t() | nil,
          action: String.t() | nil,
          actor: String.t() | nil,
          provenance: atom() | String.t() | nil,
          status: atom() | String.t() | nil,
          module_function: String.t() | nil,
          source_snippet: String.t() | nil,
          result: String.t() | nil,
          details: String.t() | nil,
          line: pos_integer() | nil,
          test_name: String.t() | nil,
          test_kind: atom() | String.t() | nil,
          assertion_context: map() | nil,
          capture_origin: String.t() | nil
        }

  defstruct [
    :id,
    :type,
    :kind,
    :label,
    :node_id,
    :focus_node_id,
    focus_targets: [],
    emits: [],
    reacts_to: nil,
    action: nil,
    actor: nil,
    provenance: nil,
    status: nil,
    module_function: nil,
    source_snippet: nil,
    result: nil,
    details: nil,
    line: nil,
    test_name: nil,
    test_kind: nil,
    assertion_context: nil,
    capture_origin: nil
  ]

  def new(attrs \\ %{}) do
    struct(__MODULE__, attrs)
  end
end
