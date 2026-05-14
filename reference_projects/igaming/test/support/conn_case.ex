defmodule IgamingRef.ConnCase do
  @moduledoc """
  This module defines the test case to be used by tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also import other functionality to make it easier
  to build common data structures for testing.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint IgamingRef.Web.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest, except: [build_conn: 0, build_conn: 1]
      import IgamingRef.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def build_conn(session \\ %{}) do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(session)
  end

  def build_conn_with_trace(session \\ %{}) do
    trace_id = Foundry.TestScenario.RuntimeCapture.current_trace_id()

    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(maybe_put_trace_id(session, trace_id))
  end

  defp maybe_put_trace_id(session, nil), do: session
  defp maybe_put_trace_id(session, trace_id), do: Map.put(session, "foundry_trace_id", trace_id)
end
