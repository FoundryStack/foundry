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
    {:ok, %{report: nil}}
  end

  def handle_call(:get, _from, state), do: {:reply, state.report, state}

  def handle_cast({:update, report}, state) do
    Phoenix.PubSub.broadcast(Foundry.PubSub, "scenarios", {:scenarios_updated, report})
    {:noreply, %{state | report: report}}
  end

  def handle_info(:extract_static, state) do
    project_root = File.cwd!()

    report =
      ScenarioTracer.MixTask.run(Mix.Tasks.Foundry.Scenarios.Extract, [:static_only])

    Phoenix.PubSub.broadcast(Foundry.PubSub, "scenarios", {:scenarios_updated, report})
    {:noreply, %{state | report: report, project_root: project_root}}
  end
end
