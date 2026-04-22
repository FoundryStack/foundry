defmodule SparkMeta.Analysis do
  @moduledoc """
  Normalized output accumulator for SparkMeta analyzers.

  Analyzers write reusable facts into `facts` and append structured diagnostics
  into `diagnostics`.
  """

  @enforce_keys [:module]
  defstruct module: nil, facts: %{}, diagnostics: []

  @type diagnostic :: map()

  @type t :: %__MODULE__{
          module: module(),
          facts: %{optional(atom()) => term()},
          diagnostics: [diagnostic()]
        }

  @spec new(module()) :: t()
  def new(module), do: %__MODULE__{module: module}

  @spec put_fact(t(), atom(), term()) :: t()
  def put_fact(%__MODULE__{facts: facts} = analysis, key, value) when is_atom(key) do
    %{analysis | facts: Map.put(facts, key, value)}
  end

  @spec merge_facts(t(), map()) :: t()
  def merge_facts(%__MODULE__{facts: facts} = analysis, values) when is_map(values) do
    %{analysis | facts: Map.merge(facts, values)}
  end

  @spec add_diagnostic(t(), diagnostic()) :: t()
  def add_diagnostic(%__MODULE__{diagnostics: diagnostics} = analysis, diagnostic) do
    %{analysis | diagnostics: diagnostics ++ [diagnostic]}
  end
end
