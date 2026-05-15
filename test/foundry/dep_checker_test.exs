defmodule Foundry.DepCheckerTest do
  use ExUnit.Case

  test "check_all/0 returns all required and optional deps" do
    results = Foundry.DepChecker.check_all()

    assert Map.has_key?(results, :erlang)
    assert Map.has_key?(results, :elixir)
    assert Map.has_key?(results, :node)
    assert Map.has_key?(results, :bun)

    Enum.each(results, fn {_key, info} ->
      assert Map.has_key?(info, :installed?)
      assert Map.has_key?(info, :version)
      assert Map.has_key?(info, :name)
      assert Map.has_key?(info, :required?)
    end)
  end

  test "blocking_missing?/1 returns true if elixir is missing" do
    results = %{
      elixir: %{installed?: false, version: nil, name: "Elixir", required?: true},
      node: %{installed?: true, version: "v18.0.0", name: "Node.js", required?: false},
      bun: %{installed?: false, version: nil, name: "Bun", required?: false},
      erlang: %{installed?: true, version: "Erlang/OTP 26", name: "Erlang/OTP", required?: true}
    }

    assert Foundry.DepChecker.blocking_missing?(results)
  end

  test "blocking_missing?/1 returns true if both node and bun are missing" do
    results = %{
      elixir: %{installed?: true, version: "1.14.0", name: "Elixir", required?: true},
      node: %{installed?: false, version: nil, name: "Node.js", required?: false},
      bun: %{installed?: false, version: nil, name: "Bun", required?: false},
      erlang: %{installed?: true, version: "Erlang/OTP 26", name: "Erlang/OTP", required?: true}
    }

    assert Foundry.DepChecker.blocking_missing?(results)
  end

  test "blocking_missing?/1 returns false if all required deps are present" do
    results = %{
      elixir: %{installed?: true, version: "1.14.0", name: "Elixir", required?: true},
      node: %{installed?: true, version: "v18.0.0", name: "Node.js", required?: false},
      bun: %{installed?: false, version: nil, name: "Bun", required?: false},
      erlang: %{installed?: true, version: "Erlang/OTP 26", name: "Erlang/OTP", required?: true}
    }

    refute Foundry.DepChecker.blocking_missing?(results)
  end

  test "blocking_missing?/1 returns false if bun is present (node not required)" do
    results = %{
      elixir: %{installed?: true, version: "1.14.0", name: "Elixir", required?: true},
      node: %{installed?: false, version: nil, name: "Node.js", required?: false},
      bun: %{installed?: true, version: "1.0.0", name: "Bun", required?: false},
      erlang: %{installed?: true, version: "Erlang/OTP 26", name: "Erlang/OTP", required?: true}
    }

    refute Foundry.DepChecker.blocking_missing?(results)
  end
end
