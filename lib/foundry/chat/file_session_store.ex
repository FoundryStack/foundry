defmodule Foundry.Chat.FileSessionStore do
  @moduledoc """
  File-backed session store for Studio copilot sessions.

  Sessions are stored as JSON files in `.foundry/local/chat_sessions/` relative to the project root.
  Each file is named `<session_id>.json` and contains the full session state.

  Atomic writes are ensured via temp-file + rename pattern.
  """

  @behaviour Foundry.Chat.SessionStore

  @impl true
  def list(workspace_id, project_fingerprint) do
    store_root = store_root()

    case File.mkdir_p(store_root) do
      :ok ->
        case File.ls(store_root) do
          {:ok, files} ->
            sessions =
              files
              |> Enum.filter(&String.ends_with?(&1, ".json"))
              |> Enum.flat_map(&load_file(store_root, &1))
              |> Enum.filter(fn session ->
                session["workspace_id"] == workspace_id and
                  session["project_fingerprint"] == project_fingerprint
              end)
              |> Enum.sort_by(& &1["updated_at"], :desc)

            {:ok, sessions}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def load(session_id) do
    store_root = store_root()
    path = Path.join(store_root, "#{session_id}.json")

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, session} -> {:ok, session}
          {:error, reason} -> {:error, {:invalid_json, reason}}
        end

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create(attrs) do
    session_id = Map.fetch!(attrs, :id)
    store_root = store_root()

    case File.mkdir_p(store_root) do
      :ok ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        session = %{
          "id" => session_id,
          "workspace_id" => Map.fetch!(attrs, :workspace_id),
          "project_fingerprint" => Map.fetch!(attrs, :project_fingerprint),
          "title" => Map.get(attrs, :title, "New session"),
          "messages" => Map.get(attrs, :messages, []),
          "session_digest" => Map.get(attrs, :session_digest, %{}),
          "last_message_preview" => Map.get(attrs, :last_message_preview),
          "created_at" => now,
          "updated_at" => now,
          "model" => Map.get(attrs, :model)
        }

        write_session(store_root, session_id, session)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def update(session_id, attrs) do
    store_root = store_root()

    with {:ok, session} <- load(session_id) do
      if session do
        now = DateTime.utc_now() |> DateTime.to_iso8601()
        updated_session = Map.merge(session, attrs) |> Map.put("updated_at", now)
        write_session(store_root, session_id, updated_session)
      else
        {:error, :not_found}
      end
    end
  end

  @impl true
  def rename(session_id, title) do
    update(session_id, %{"title" => title})
  end

  @impl true
  def delete(session_id) do
    store_root = store_root()
    path = Path.join(store_root, "#{session_id}.json")

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_session(store_root, session_id, session) do
    path = Path.join(store_root, "#{session_id}.json")
    tmp_path = "#{path}.tmp"

    case Jason.encode(session) do
      {:ok, content} ->
        case File.write(tmp_path, content) do
          :ok ->
            case File.rename(tmp_path, path) do
              :ok -> {:ok, session}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_file(store_root, filename) do
    path = Path.join(store_root, filename)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, session} -> [session]
          {:error, _reason} -> []
        end

      {:error, _reason} ->
        []
    end
  end

  defp store_root do
    project_root =
      Application.get_env(
        :foundry_web,
        :current_project_root,
        Application.get_env(
          :foundry_web,
          :igaming_project_root,
          Path.expand("../../reference_projects/igaming", __DIR__)
        )
      )
      |> Path.expand()

    Path.join([project_root, ".foundry", "local", "chat_sessions"])
  end
end
