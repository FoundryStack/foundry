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
      import Phoenix.ConnTest
      import IgamingRef.ConnCase
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def build_conn_with_trace do
    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(%{"foundry_test_pid" => encode_pid(self())})
  end

  defp encode_pid(pid) do
    pid |> :erlang.pid_to_list() |> List.to_string()
  end
end
