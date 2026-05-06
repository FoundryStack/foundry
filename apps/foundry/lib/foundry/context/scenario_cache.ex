defmodule Foundry.Context.ScenarioCache do
  @moduledoc """
  Caches the latest scenario extraction report and broadcasts updates.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get, do: GenServer.call(__MODULE__, :get)
  def update(report), do: GenServer.cast(__MODULE__, {:update, report})

  def subscribe do
    Phoenix.PubSub.subscribe(Foundry.PubSub, "scenarios")
    :ok
  end

  def init(_opts) do
    send(self(), :extract_static)
    {:ok, %{report: nil, project_root: File.cwd!()}}
  end

  def handle_call(:get, _from, state), do: {:reply, state.report, state}

  def handle_cast({:update, report}, state) do
    Phoenix.PubSub.broadcast(Foundry.PubSub, "scenarios", {:scenarios_updated, report})
    {:noreply, %{state | report: report}}
  end

  def handle_info(:extract_static, state) do
    report =
      try do
        ScenarioTracer.MixTask.run(Mix.Tasks.Foundry.Scenarios.Extract, [:static_only])
      rescue
        error ->
          require Logger

          Logger.warning("""
          ScenarioCache static extraction failed: #{Exception.message(error)}
          """)

          %ExTracer.Report{
            extracted_at: DateTime.utc_now(),
            duration_ms: 0,
            scenarios: [],
            coverage: %ExTracer.CoverageReport{},
            performance: %ExTracer.PerformanceReport{},
            node_index: %{},
            warnings: ["static extraction failed: #{Exception.message(error)}"]
          }
      end

    Phoenix.PubSub.broadcast(Foundry.PubSub, "scenarios", {:scenarios_updated, report})
    {:noreply, %{state | report: report}}
  end
end
