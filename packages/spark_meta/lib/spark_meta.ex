defmodule SparkMeta do
  @moduledoc """
  Generic Spark DSL walker and introspection library.

  Provides a unified way to inspect any [Spark](https://hexdocs.pm/spark)-based DSL
  module — extracting extensions, entities, options, and persisted state — with an
  opt-in handler system for richer, extension-specific output.

  ## Key modules

  - `SparkMeta.Walker` — low-level DSL introspection delegated from this module
  - `SparkMeta.DslState` — normalized struct produced by `walk/1`
  - `SparkMeta.Pipeline` — runs an ordered list of analyzers against a module
  - `SparkMeta.Analysis` — typed result struct with facts and diagnostics
  - `SparkMeta.Context` — carries the target module, DSL state, and source material
  - `SparkMeta.Analyzer` — behaviour for implementing custom analyzers
  - `SparkMeta.Extension` — behaviour for extension-specific extraction handlers
  - `SparkMeta.Registry` — ETS-backed registry mapping extensions to handlers
  - `SparkMeta.SourceProvider` — behaviour for fetching source text/AST

  ## Walking a Spark module

      {:ok, state} = SparkMeta.walk(MyApp.Accounts.User)

      state.extensions     # => [Ash.Resource, ...]
      state.sections       # => %{[:attributes] => [%Ash.Resource.Attribute{...}, ...]}
      state.options        # => %{[:attributes] => %{allow_nil?: false}}
      state.persisted      # => %{domain: MyApp.Domain}
      state.extension_data # => %{Ash.Resource => %{attributes: [...], actions: [...]}}

  ## Analyzer pipeline

      {:ok, analysis} = SparkMeta.analyze(MyApp.Accounts.User)

      analysis.facts[:attributes]  # => [%{name: :email, type: :string}, ...]
      analysis.diagnostics         # => []

  Run with custom analyzers:

      {:ok, analysis} = SparkMeta.analyze(MyApp.Accounts.User,
        analyzers: SparkMeta.default_analyzers() ++ [MyApp.Analyzers.Compliance]
      )

  ## Registering extension handlers

      SparkMeta.Registry.register(MyExtension, MyExtensionHandler)

      defmodule MyExtensionHandler do
        @behaviour SparkMeta.Extension

        @impl true
        def extract(extension_module, dsl_state) do
          %{custom: "output"}
        end
      end

  See the [README](https://hexdocs.pm/spark_meta) for full usage and built-in analyzers.
  """

  defdelegate walk(module), to: SparkMeta.Walker
  defdelegate spark_module?(module), to: SparkMeta.Walker
  defdelegate extensions(module), to: SparkMeta.Walker
  defdelegate entities(module, path), to: SparkMeta.Walker
  defdelegate get_opt(module, path, key, default), to: SparkMeta.Walker
  defdelegate get_persisted(module, key, default), to: SparkMeta.Walker

  @spec analyze(module(), keyword()) ::
          {:ok, SparkMeta.Analysis.t()} | {:error, {:not_loaded, module()}}
  def analyze(module, opts \\ []) do
    SparkMeta.Pipeline.run(module, opts)
  end

  @spec default_analyzers() :: [module()]
  def default_analyzers do
    [
      SparkMeta.Analyzers.ModuleDoc,
      SparkMeta.Analyzers.Extensions,
      SparkMeta.Analyzers.AshResource,
      SparkMeta.Analyzers.StateMachine
    ]
  end
end
