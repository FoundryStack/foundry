defmodule PhoenixLLMChat.StreamRuntimeTest do
  use ExUnit.Case

  test "StreamRuntime module compiles and is loadable" do
    assert Code.ensure_loaded?(PhoenixLLMChat.StreamRuntime)
  end

  test "StreamRuntime module has required functions" do
    {:module, mod} = Code.ensure_loaded(PhoenixLLMChat.StreamRuntime)
    functions = mod.__info__(:functions)
    function_names = Enum.map(functions, &elem(&1, 0))

    assert Enum.member?(function_names, :handle_llm_delta)
    assert Enum.member?(function_names, :handle_llm_done)
    assert Enum.member?(function_names, :handle_llm_error)
    assert Enum.member?(function_names, :handle_llm_trace)
    assert Enum.member?(function_names, :handle_process_down)
    assert Enum.member?(function_names, :cleanup_on_terminate)
  end

  test "DOWN tuple format is correct" do
    ref = make_ref()
    down_tuple = {:DOWN, ref, :process, 1234, :killed}

    assert is_tuple(down_tuple)
    assert tuple_size(down_tuple) == 5
    assert elem(down_tuple, 0) == :DOWN
    assert elem(down_tuple, 1) == ref
    assert elem(down_tuple, 2) == :process
  end
end
