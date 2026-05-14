defmodule PhoenixLLMChat.CoreTest do
  use ExUnit.Case

  test "Core module compiles and is loadable" do
    assert Code.ensure_loaded?(PhoenixLLMChat.Core)
  end

  test "Core module has required functions" do
    {:module, mod} = Code.ensure_loaded(PhoenixLLMChat.Core)
    functions = mod.__info__(:functions)
    function_names = Enum.map(functions, &elem(&1, 0))

    assert Enum.member?(function_names, :mount)
    assert Enum.member?(function_names, :handle_event)
    assert Enum.member?(function_names, :handle_info)
    assert Enum.member?(function_names, :terminate)
  end
end
