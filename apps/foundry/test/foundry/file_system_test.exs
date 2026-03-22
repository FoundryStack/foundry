defmodule Foundry.FileSystemTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../reference_projects/igaming", __DIR__)

  describe "permitted paths" do
    test "lib/ file" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, "lib/igaming_ref/finance/wallet.ex")
      assert String.contains?(content, "defmodule")
    end

    test "docs/adrs/ file" do
      # Uses one of the stub ADRs created in P-1
      {:ok, first_adr} =
        File.ls!(Path.join(@root, "docs/adrs/"))
        |> Enum.find(&String.ends_with?(&1, ".md"))
        |> then(&{:ok, &1})

      assert {:ok, _} = Foundry.FileSystem.read(@root, "docs/adrs/#{first_adr}")
    end

    test "AGENTS.md" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, "AGENTS.md")
    end

    test ".foundry/manifest.exs" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, ".foundry/manifest.exs")
    end

    test "mix.exs" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, "mix.exs")
    end

    test "priv/repo/migrations/ file" do
      # Create a stub migration file in P-1 if none exists
      assert {:ok, _} =
               Foundry.FileSystem.read(@root, "priv/repo/migrations/20260101000000_init.exs")
    end
  end

  describe "boundary rejections" do
    test "_build/ is rejected" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "_build/dev/lib/igaming_ref/ebin/something.beam")
    end

    test "deps/ is rejected" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "deps/ash/lib/ash.ex")
    end

    test ".env is rejected" do
      assert {:error, :outside_boundary} = Foundry.FileSystem.read(@root, ".env")
    end

    test "path traversal: lib/../../.env" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "lib/../../.env")
    end

    test "double traversal: lib/../lib/../.env" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "lib/../lib/../.env")
    end

    test "AGENTS.md.bak is not a permitted exact path" do
      # Guards against prefix-matching exact files as directories
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "AGENTS.md.bak")
    end

    test "mix.exs.bak is not permitted" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "mix.exs.bak")
    end
  end

  describe "not_found" do
    test "non-existent permitted path" do
      assert {:error, :not_found} =
               Foundry.FileSystem.read(@root, "lib/does_not_exist.ex")
    end
  end
end
