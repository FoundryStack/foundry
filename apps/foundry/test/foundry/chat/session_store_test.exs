defmodule Foundry.Chat.SessionStoreTest do
  use ExUnit.Case, async: false

  alias Foundry.Chat.FileSessionStore

  setup do
    test_store_root = Path.join(System.tmp_dir!(), "foundry_chat_test_#{System.unique_integer()}")
    File.rm_rf!(test_store_root)
    File.mkdir_p!(test_store_root)

    # Override the default store root for this test
    original_env = Application.get_env(:foundry_web, :igaming_project_root)

    Application.put_env(:foundry_web, :igaming_project_root, test_store_root)

    on_exit(fn ->
      File.rm_rf!(test_store_root)
      restore_env(:foundry_web, :igaming_project_root, original_env)
    end)

    {:ok, store_root: test_store_root}
  end

  describe "create/load/update round-trip" do
    test "creates a session and loads it back", %{store_root: _store_root} do
      session_id = Ecto.UUID.generate()
      workspace_id = "test-workspace"
      project_fingerprint = "abc123"

      {:ok, created} =
        FileSessionStore.create(%{
          id: session_id,
          workspace_id: workspace_id,
          project_fingerprint: project_fingerprint,
          title: "Test Session",
          messages: [%{"role" => "user", "content" => "Hello"}],
          session_digest: %{"key" => "value"}
        })

      assert created["id"] == session_id
      assert created["workspace_id"] == workspace_id
      assert created["project_fingerprint"] == project_fingerprint
      assert created["title"] == "Test Session"
      assert created["messages"] == [%{"role" => "user", "content" => "Hello"}]
      assert created["session_digest"] == %{"key" => "value"}
      assert is_binary(created["created_at"])
      assert is_binary(created["updated_at"])

      {:ok, loaded} = FileSessionStore.load(session_id)

      assert loaded["id"] == session_id
      assert loaded["title"] == "Test Session"
      assert loaded["messages"] == [%{"role" => "user", "content" => "Hello"}]
    end

    test "updates a session and bumps updated_at", %{store_root: _store_root} do
      session_id = Ecto.UUID.generate()

      {:ok, created} =
        FileSessionStore.create(%{
          id: session_id,
          workspace_id: "ws1",
          project_fingerprint: "fp1",
          title: "Original"
        })

      created_at = created["created_at"]
      Process.sleep(10)

      {:ok, updated} =
        FileSessionStore.update(session_id, %{
          "messages" => [%{"role" => "user", "content" => "Updated"}]
        })

      assert updated["created_at"] == created_at
      assert updated["updated_at"] != created_at
      assert updated["messages"] == [%{"role" => "user", "content" => "Updated"}]
    end
  end

  describe "list with filtering" do
    test "returns only sessions matching workspace_id and project_fingerprint", %{
      store_root: _store_root
    } do
      ws1_id = Ecto.UUID.generate()
      ws2_id = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: ws1_id,
        workspace_id: "workspace1",
        project_fingerprint: "fp1",
        title: "Session 1"
      })

      FileSessionStore.create(%{
        id: ws2_id,
        workspace_id: "workspace1",
        project_fingerprint: "fp2",
        title: "Session 2"
      })

      other_id = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: other_id,
        workspace_id: "workspace2",
        project_fingerprint: "fp1",
        title: "Session 3"
      })

      {:ok, ws1_fp1} = FileSessionStore.list("workspace1", "fp1")
      assert Enum.map(ws1_fp1, & &1["id"]) == [ws1_id]

      {:ok, ws1_fp2} = FileSessionStore.list("workspace1", "fp2")
      assert Enum.map(ws1_fp2, & &1["id"]) == [ws2_id]

      {:ok, ws2_fp1} = FileSessionStore.list("workspace2", "fp1")
      assert Enum.map(ws2_fp1, & &1["id"]) == [other_id]

      {:ok, empty} = FileSessionStore.list("workspace1", "fp3")
      assert empty == []
    end

    test "sorts sessions by updated_at descending", %{store_root: _store_root} do
      id1 = Ecto.UUID.generate()
      id2 = Ecto.UUID.generate()
      id3 = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: id1,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "First"
      })

      Process.sleep(10)

      FileSessionStore.create(%{
        id: id2,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "Second"
      })

      Process.sleep(10)

      FileSessionStore.create(%{
        id: id3,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "Third"
      })

      {:ok, sessions} = FileSessionStore.list("ws", "fp")
      ids = Enum.map(sessions, & &1["id"])

      assert ids == [id3, id2, id1]
    end
  end

  describe "malformed files" do
    test "list/2 skips malformed JSON files without crashing", %{store_root: store_root} do
      session_dir = Path.join([store_root, ".foundry", "local", "chat_sessions"])
      File.mkdir_p!(session_dir)

      # Valid session
      valid_id = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: valid_id,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "Valid"
      })

      # Malformed JSON file
      File.write!(Path.join(session_dir, "broken.json"), "{ invalid json }")

      {:ok, sessions} = FileSessionStore.list("ws", "fp")

      assert Enum.map(sessions, & &1["id"]) == [valid_id]
    end
  end

  describe "delete" do
    test "deletes a session file", %{store_root: _store_root} do
      session_id = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: session_id,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "To Delete"
      })

      {:ok, before} = FileSessionStore.load(session_id)
      assert before != nil

      :ok = FileSessionStore.delete(session_id)

      {:ok, after_delete} = FileSessionStore.load(session_id)
      assert after_delete == nil
    end

    test "returns :ok even if session does not exist", %{store_root: _store_root} do
      :ok = FileSessionStore.delete(Ecto.UUID.generate())
    end
  end

  describe "rename" do
    test "renames a session by updating title", %{store_root: _store_root} do
      session_id = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: session_id,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "Original Title"
      })

      {:ok, renamed} = FileSessionStore.rename(session_id, "New Title")

      assert renamed["title"] == "New Title"

      {:ok, loaded} = FileSessionStore.load(session_id)
      assert loaded["title"] == "New Title"
    end
  end

  describe "load" do
    test "returns nil for non-existent session", %{store_root: _store_root} do
      {:ok, result} = FileSessionStore.load(Ecto.UUID.generate())
      assert result == nil
    end
  end

  describe "atomic writes" do
    test "temp file is cleaned up on successful write", %{store_root: store_root} do
      session_dir = Path.join([store_root, ".foundry", "local", "chat_sessions"])
      session_id = Ecto.UUID.generate()

      FileSessionStore.create(%{
        id: session_id,
        workspace_id: "ws",
        project_fingerprint: "fp",
        title: "Test"
      })

      files = File.ls!(session_dir)
      tmp_files = Enum.filter(files, &String.ends_with?(&1, ".tmp"))

      assert tmp_files == []
    end
  end

  defp restore_env(app, key, original_value) do
    case original_value do
      {:ok, value} -> Application.put_env(app, key, value)
      :error -> Application.delete_env(app, key)
      value when is_binary(value) -> Application.put_env(app, key, value)
    end
  end
end
