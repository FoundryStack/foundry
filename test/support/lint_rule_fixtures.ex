defmodule Foundry.Test.Fixtures.PlainSensitive do
  @moduledoc "A plain module with no Spark extensions — for testing lint rules that check sensitive modules."
end

defmodule Foundry.Test.Fixtures.PaperTrailOnly do
  @moduledoc "Plain module (no Ash) — for testing ArchivalRule violation."
end

defmodule Foundry.Test.Fixtures.NoDocModule do
  @moduledoc false
end

defmodule Foundry.Test.Fixtures.InactiveAdapter do
  @moduledoc "A module for testing adapter rules (Phase 1 stub returns no violations)."
end

defmodule Foundry.Test.Fixtures.ReactorMissingRunbook do
  @moduledoc "Reactor with 4+ steps but no @runbook — for RunbookRule violation test."
  use Reactor

  step :step_one do
    run fn _, _ -> {:ok, :one} end
  end

  step :step_two do
    run fn _, _ -> {:ok, :two} end
  end

  step :step_three do
    run fn _, _ -> {:ok, :three} end
  end

  step :step_four do
    run fn _, _ -> {:ok, :four} end
  end
end

defmodule Foundry.Test.Fixtures.ReactorMissingIdempotency do
  @moduledoc "Reactor with side-effect steps but no @idempotency_key — for IdempotencyRule violation test."
  use Reactor

  step :load_data do
    run fn _, _ -> {:ok, %{data: :loaded}} end
  end

  step :process do
    argument :data, result(:load_data)
    run fn %{data: _}, _ -> {:ok, :processed} end
  end

  step :persist do
    argument :result, result(:process)
    run fn %{result: _}, _ -> {:ok, :persisted} end
  end
end
