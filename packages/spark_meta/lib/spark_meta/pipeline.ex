defmodule SparkMeta.Pipeline do
  @moduledoc """
  Explicit, ordered analysis pipeline for SparkMeta.

  The pipeline builds a reusable `SparkMeta.Context`, then runs analyzers in
  order while capturing non-fatal diagnostics per analyzer.
  """

  alias SparkMeta.{Analysis, Context}

  @type option ::
          {:analyzers, [module()]}
          | {:source_provider, module() | (module() -> SparkMeta.SourceProvider.fetch_result())}

  @spec run(module(), [option()]) :: {:ok, Analysis.t()} | {:error, {:not_loaded, module()}}
  def run(module, opts \\ []) when is_atom(module) do
    analyzers = Keyword.get(opts, :analyzers, SparkMeta.default_analyzers())
    source_provider = Keyword.get(opts, :source_provider, SparkMeta.SourceProvider.FileSystem)

    with {:module, ^module} <- Code.ensure_loaded(module) do
      context = build_context(module, source_provider)

      analysis =
        Analysis.new(module)
        |> add_context_diagnostics(context)
        |> run_analyzers(context, analyzers)

      {:ok, analysis}
    else
      _ -> {:error, {:not_loaded, module}}
    end
  end

  defp build_context(module, source_provider) do
    {spark_module?, dsl_state, walk_diagnostics} = walker_state(module)
    {source_payload, source_diagnostics} = load_source(module, source_provider)

    %Context{
      module: module,
      spark_module?: spark_module?,
      dsl_state: dsl_state,
      source_path: source_payload[:path],
      source_text: source_payload[:text],
      source_ast: source_payload[:ast],
      diagnostics: walk_diagnostics ++ source_diagnostics
    }
  end

  defp walker_state(module) do
    case SparkMeta.Walker.walk(module) do
      {:ok, dsl_state} ->
        {true, dsl_state, []}

      {:error, :not_a_spark_module} ->
        {false, nil, []}

      {:error, {:not_loaded, _module}} ->
        {false, nil, []}
    end
  end

  defp load_source(module, source_provider) when is_atom(source_provider) do
    load_source(module, &source_provider.fetch/1)
  end

  defp load_source(module, source_provider) when is_function(source_provider, 1) do
    case source_provider.(module) do
      {:ok, nil} ->
        {%{}, []}

      {:ok, payload} when is_map(payload) ->
        {Map.take(payload, [:path, :text, :ast]), []}

      {:error, reason} ->
        {%{}, [diagnostic(:source_provider, module, "source provider failed", reason)]}

      other ->
        {%{},
         [
           diagnostic(
             :source_provider,
             module,
             "source provider returned an unexpected result",
             other
           )
         ]}
    end
  rescue
    error ->
      {%{}, [diagnostic(:source_provider, module, "source provider raised", error)]}
  end

  defp add_context_diagnostics(analysis, %Context{diagnostics: diagnostics}) do
    Enum.reduce(diagnostics, analysis, &Analysis.add_diagnostic(&2, &1))
  end

  defp run_analyzers(analysis, _context, []), do: analysis

  defp run_analyzers(analysis, context, [analyzer | rest]) do
    next_analysis =
      try do
        case analyzer.analyze(context, analysis) do
          {:ok, %Analysis{} = next_analysis} ->
            next_analysis

          {:error, diagnostic} when is_map(diagnostic) ->
            Analysis.add_diagnostic(analysis, Map.put_new(diagnostic, :analyzer, analyzer))

          other ->
            Analysis.add_diagnostic(
              analysis,
              diagnostic(analyzer, context.module, "analyzer returned an unexpected result", other)
            )
        end
      rescue
        error ->
          Analysis.add_diagnostic(
            analysis,
            diagnostic(analyzer, context.module, "analyzer raised", error)
          )
      end

    run_analyzers(next_analysis, context, rest)
  end

  defp diagnostic(analyzer, module, message, detail) do
    %{
      analyzer: analyzer,
      module: module,
      message: message,
      detail: format_detail(detail)
    }
  end

  defp format_detail(%_{} = exception), do: Exception.message(exception)
  defp format_detail(detail), do: inspect(detail)
end
