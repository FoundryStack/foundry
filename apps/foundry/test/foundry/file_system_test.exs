defmodule Foundry.FileSystemTest do
  use ExUnit.Case, async: true

  @root Path.expand("../../../../reference_projects/igaming", __DIR__)

  describe "permitted paths" do
    test "lib/ file" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, "lib/wallet.ex")
      assert String.contains?(content, "defmodule")
    end

    test "test/ file" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, "test/transfers_test.exs")
      assert String.contains?(content, "defmodule")
    end

    test ".foundry/manifest.exs" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, ".foundry/manifest.exs")
      assert String.contains?(content, "project_name:")
    end

    test "mix.exs" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, "mix.exs")
      assert String.contains?(content, "defmodule")
    end

    test "config/ file" do
      assert {:ok, _} = Foundry.FileSystem.read(@root, "config/config.exs")
    end

    test "readme.md at project root" do
      assert {:ok, content} = Foundry.FileSystem.read(@root, "readme.md")
      assert String.contains?(content, "iGaming")
    end
  end

  describe "path traversal prevention" do
    test "path traversal: ../ is rejected" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "lib/../../etc/passwd")
    end

    test "double traversal is rejected" do
      assert {:error, :outside_boundary} =
               Foundry.FileSystem.read(@root, "lib/../lib/../..")
    end
  end

  describe "not_found" do
    test "non-existent permitted path" do
      assert {:error, :not_found} =
               Foundry.FileSystem.read(@root, "lib/does_not_exist.ex")
    end
  end
end
