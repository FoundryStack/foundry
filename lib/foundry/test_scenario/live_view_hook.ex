defmodule Foundry.TestScenario.LiveViewHook do
  @moduledoc """
  Phoenix LiveView on_mount hook that registers the LiveView channel PID
  with its associated test process PID during test execution.

  Reads the test PID from the Phoenix session if present (set by test helpers).
  The PID is then used by AshTracer to forward action events back to the test.
  Also records the page mount as an entry event in the scenario trace.

  Add to router via:
    live_session :default, on_mount: [Foundry.TestScenario.LiveViewHook]
  """

  def on_mount(_name, _params, session, socket) do
    case decode_test_pid(session) do
      {:ok, test_pid} ->
        Foundry.TestScenario.LiveViewRegistry.register(self(), test_pid)

        # Record page entry in scenario trace
        page_module = socket.view |> Atom.to_string() |> String.trim_leading("Elixir.")
        send(test_pid, {:foundry_ash_event, %{
          node_id: page_module,
          action_kind: :entry
        }})

        {:cont, socket}

      :not_found ->
        {:cont, socket}
    end
  end

  defp decode_test_pid(session) when is_map(session) do
    case session do
      %{"foundry_test_pid" => pid_string} when is_binary(pid_string) ->
        # Decode PID from string representation
        try do
          pid = :erlang.list_to_pid(String.to_charlist(pid_string))
          {:ok, pid}
        rescue
          _ -> :not_found
        end

      %{foundry_test_pid: pid_string} when is_binary(pid_string) ->
        try do
          pid = :erlang.list_to_pid(String.to_charlist(pid_string))
          {:ok, pid}
        rescue
          _ -> :not_found
        end

      _ ->
        :not_found
    end
  end
  defp decode_test_pid(_), do: :not_found
end
