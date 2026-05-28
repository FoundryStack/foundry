defmodule Foundry.Verifiers.ReactorWithSideEffectsRequiresIdempotencyTest do
  use ExUnit.Case, async: true

  alias Foundry.Verifiers.ReactorWithSideEffectsRequiresIdempotency

  defp dsl_state(module, steps) do
    %{persist: %{module: module}}
    |> Map.put([:steps], %{entities: steps})
  end

  defp step(type), do: %{type: type}

  # ---------------------------------------------------------------------------
  # Stub modules — use Foundry.Annotations so @idempotency_key is registered
  # with persist: true and appears in __info__(:attributes)
  # ---------------------------------------------------------------------------

  defmodule ReactorWithKey do
    use Foundry.Annotations
    @idempotency_key :my_key
  end

  defmodule ReactorWithoutKey do
    # no Foundry.Annotations, no @idempotency_key
  end

  describe "side-effecting steps without @idempotency_key" do
    for side_effect_type <- [:create, :update, :destroy, :action, :run] do
      test "#{side_effect_type} step returns error" do
        ds = dsl_state(ReactorWithoutKey, [step(unquote(side_effect_type))])
        assert {:error, error} = ReactorWithSideEffectsRequiresIdempotency.verify(ds)
        assert error.message =~ "idempotency_key"
        assert error.message =~ "INV-013"
      end
    end
  end

  describe "side-effecting steps with @idempotency_key defined" do
    test "returns :ok" do
      ds = dsl_state(ReactorWithKey, [step(:create)])
      assert :ok = ReactorWithSideEffectsRequiresIdempotency.verify(ds)
    end
  end

  describe "no side-effecting steps" do
    test "returns :ok without @idempotency_key" do
      ds = dsl_state(ReactorWithoutKey, [step(:map), step(:transform)])
      assert :ok = ReactorWithSideEffectsRequiresIdempotency.verify(ds)
    end

    test "returns :ok with empty step list" do
      ds = dsl_state(ReactorWithoutKey, [])
      assert :ok = ReactorWithSideEffectsRequiresIdempotency.verify(ds)
    end
  end

  describe "rescue path when module has no __info__" do
    test "non-existent module with side-effect steps returns error (rescue returns false for key check)" do
      ds = dsl_state(DoesNotExist.NoSuchModule, [step(:create)])
      assert {:error, _} = ReactorWithSideEffectsRequiresIdempotency.verify(ds)
    end
  end
end
