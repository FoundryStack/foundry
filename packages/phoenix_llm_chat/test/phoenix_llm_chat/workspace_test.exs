defmodule PhoenixLLMChat.WorkspaceTest do
  use ExUnit.Case

  test "Workspace module compiles and is loadable" do
    assert Code.ensure_loaded?(PhoenixLLMChat.Workspace)
  end

  test "Workspace module has required functions" do
    # Check that key functions exist in the module
    {:module, mod} = Code.ensure_loaded(PhoenixLLMChat.Workspace)
    functions = mod.__info__(:functions)
    function_names = Enum.map(functions, &elem(&1, 0))

    assert Enum.member?(function_names, :create_session)
    assert Enum.member?(function_names, :open_session)
    assert Enum.member?(function_names, :switch_session)
    assert Enum.member?(function_names, :rename_session)
    assert Enum.member?(function_names, :delete_session)
    assert Enum.member?(function_names, :hydrate_workspace)
  end
end
