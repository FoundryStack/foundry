use serde::Serialize;
use serde_json::Value;
use std::env;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tauri::{AppHandle, Emitter, Manager, RunEvent, Runtime};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_shell::{
    process::{CommandChild, CommandEvent},
    ShellExt,
};
use url::form_urlencoded;

const HEALTH_TIMEOUT: Duration = Duration::from_secs(180);
const HEALTH_POLL_INTERVAL: Duration = Duration::from_millis(100);
const STATUS_UPDATE_INTERVAL: Duration = Duration::from_secs(5);
const HEALTH_CHECK_IO_TIMEOUT: Duration = Duration::from_millis(750);
const EXTRA_PATH_ENTRIES: &[&str] = &[
    "/opt/homebrew/bin",
    "/opt/homebrew/opt/elixir/bin",
    "/opt/homebrew/opt/erlang/bin",
    "/usr/local/bin",
];
const SIDECAR_NAME: &str = "foundry-sidecar";
const STATUS_EVENT: &str = "foundry://launch-status";
const ERROR_EVENT: &str = "foundry://launch-error";
const FILE_OPEN_ID: &str = "file.open";
const FILE_CLONE_ID: &str = "file.clone";
const FILE_RECENT_PREFIX: &str = "file.recent.";
const STANDALONE_SECRET_FILE: &str = "standalone_secret_key_base";

#[derive(Default)]
pub struct FoundrySidecarState {
    child: Mutex<Option<CommandChild>>,
}

#[derive(Clone, Serialize)]
pub struct LaunchStatusPayload {
    pub message: String,
}

#[derive(Clone, Debug)]
struct RecentProject {
    label: String,
    root: String,
}

pub fn build_menu<R: tauri::Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let open_item = MenuItem::with_id(app, FILE_OPEN_ID, "Open...", true, None::<&str>)?;
    let clone_item = MenuItem::with_id(app, FILE_CLONE_ID, "Clone Git Repository...", true, None::<&str>)?;
    let recent_items = build_recent_menu_items(app)?;
    let recent_refs = recent_items
        .iter()
        .map(|item| item as _)
        .collect::<Vec<_>>();
    let recent_submenu = Submenu::with_items(app, "Open Recent", true, &recent_refs)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = PredefinedMenuItem::quit(app, None)?;
    let file_menu = Submenu::with_items(
        app,
        "File",
        true,
        &[&open_item, &clone_item, &recent_submenu, &separator, &quit],
    )?;

    Menu::with_items(app, &[&file_menu])
}

pub fn handle_menu_event<R: tauri::Runtime>(app: &AppHandle<R>, event: MenuEvent) {
    let id = event.id().0.as_str();

    if id == FILE_OPEN_ID {
        let handle = app.clone();

        app.dialog().file().pick_folder(move |folder| {
            if let Some(folder) = folder {
                let path = folder
                    .into_path()
                    .ok()
                    .map(|path| path.to_string_lossy().to_string());

                if let Some(path) = path {
                    if let Err(message) =
                        navigate_to_project_launch(&handle, &[("path", path.as_str())])
                    {
                        emit_status(&handle, ERROR_EVENT, message);
                    }
                }
            }
        });

        return;
    }

    if id == FILE_CLONE_ID {
        if let Err(message) = navigate_to_url(app, "/project-manager") {
            emit_status(app, ERROR_EVENT, message);
        }
        return;
    }

    if let Some(index) = id.strip_prefix(FILE_RECENT_PREFIX) {
        if let Ok(index) = index.parse::<usize>() {
            if let Some(project) = load_recent_projects().get(index) {
                if let Err(message) =
                    navigate_to_project_launch(app, &[("path", project.root.as_str())])
                {
                    emit_status(app, ERROR_EVENT, message);
                }
            }
        }
    }
}

pub fn start_foundry(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        if let Err(message) = launch_and_navigate(app.clone()).await {
            shutdown_sidecar(&app);
            emit_status(&app, ERROR_EVENT, message);
        }
    });
}

pub fn handle_run_event<R: Runtime>(app: &AppHandle<R>, event: &RunEvent) {
    if matches!(event, RunEvent::ExitRequested { .. } | RunEvent::Exit) {
        shutdown_sidecar(app);
    }
}

async fn launch_and_navigate(app: AppHandle) -> Result<(), String> {
    emit_status(&app, STATUS_EVENT, "Preparing Foundry sidecar...");

    let project_root = normalize_project_root(env::var("FOUNDRY_PROJECT_ROOT").ok().as_deref());
    let project_root_string = project_root.to_string_lossy().to_string();
    let foundry_home = foundry_home_dir();
    let secret_key_base = ensure_standalone_secret(&foundry_home)?;

    let mut command = app
        .shell()
        .sidecar(SIDECAR_NAME)
        .map_err(|error| format!("Failed to prepare sidecar: {error}"))?
        .env("FOUNDRY_HOME", foundry_home.as_os_str())
        .env("FOUNDRY_STANDALONE", "1")
        .env("PHX_SERVER", "1")
        .env("SECRET_KEY_BASE", &secret_key_base);

    // Add common Elixir/mix paths to PATH for development environments
    if let Ok(current_path) = env::var("PATH") {
        let mut new_path = EXTRA_PATH_ENTRIES.join(":");
        new_path.push(':');
        new_path.push_str(&current_path);
        command = command.env("PATH", new_path);
    }

    let command = command
        .args([
            "studio",
            "--project",
            project_root_string.as_str(),
            "--port",
            "auto",
            "--no-browser",
        ]);

    let (mut rx, child) = command
        .spawn()
        .map_err(|error| format!("Failed to spawn Foundry sidecar: {error}"))?;

    store_sidecar(&app, child);

    let sidecar_output_app = app.clone();

    tauri::async_runtime::spawn(async move {
        while let Some(event) = rx.recv().await {
            match event {
                CommandEvent::Stdout(line) => {
                    eprintln!(
                        "[foundry-sidecar] {}",
                        String::from_utf8_lossy(&line).trim()
                    );
                }
                CommandEvent::Stderr(line) => {
                    eprintln!(
                        "[foundry-sidecar:stderr] {}",
                        String::from_utf8_lossy(&line).trim()
                    );
                }
                CommandEvent::Error(error) => {
                    eprintln!("[foundry-sidecar:error] {error}");
                }
                CommandEvent::Terminated(payload) => {
                    eprintln!(
                        "[foundry-sidecar:exit] code={:?} signal={:?}",
                        payload.code, payload.signal
                    );
                    clear_sidecar(&sidecar_output_app);
                }
                _ => {}
            }
        }
    });

    emit_status(
        &app,
        STATUS_EVENT,
        "Waiting for Foundry to become healthy...",
    );

    let url = wait_for_health(&app)?;
    emit_status(&app, STATUS_EVENT, format!("Foundry ready..."));

    let window = app
        .get_webview_window("main")
        .ok_or_else(|| "Main window is not available".to_string())?;
    let parsed = url
        .parse()
        .map_err(|error| format!("Failed to parse Foundry URL {url}: {error}"))?;

    window
        .navigate(parsed)
        .map_err(|error| format!("Failed to navigate to Foundry: {error}"))?;

    Ok(())
}

fn wait_for_health(app: &AppHandle) -> Result<String, String> {
    let started_at = Instant::now();
    let mut last_status_update: Option<u64> = None;

    loop {
        if started_at.elapsed() > HEALTH_TIMEOUT {
            return Err(
                format!(
                    "Foundry sidecar did not become healthy within {} seconds. It may still be compiling; check sidecar logs for compile errors.",
                    HEALTH_TIMEOUT.as_secs()
                )
            );
        }

        if let Ok(port) = read_port_file() {
            let url = format!("http://127.0.0.1:{port}");

            if health_check(&url) {
                return Ok(url);
            }
        }

        let elapsed_secs = started_at.elapsed().as_secs();
        let status_bucket = elapsed_secs / STATUS_UPDATE_INTERVAL.as_secs();

        if last_status_update != Some(status_bucket) {
            last_status_update = Some(status_bucket);
            emit_status(
                app,
                STATUS_EVENT,
                "Foundry is starting and compiling...",
            );
        }

        std::thread::sleep(HEALTH_POLL_INTERVAL);
    }
}

fn read_port_file() -> Result<u16, String> {
    let port_path = port_file_path();
    let contents = std::fs::read_to_string(&port_path)
        .map_err(|error| format!("Failed reading {}: {error}", port_path.display()))?;

    contents
        .trim()
        .parse::<u16>()
        .map_err(|error| format!("Failed parsing port file {}: {error}", port_path.display()))
}

fn port_file_path() -> PathBuf {
    if let Ok(home) = env::var("FOUNDRY_HOME") {
        return PathBuf::from(home).join(".foundry.port");
    }

    env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| fallback_project_root())
        .join(".foundry.port")
}

fn health_check(base_url: &str) -> bool {
    let Ok(parsed) = url::Url::parse(base_url) else {
        return false;
    };

    let host = parsed.host_str().unwrap_or("127.0.0.1");
    let port = parsed.port_or_known_default().unwrap_or(80);

    let Ok(mut stream) = TcpStream::connect((host, port)) else {
        return false;
    };

    let _ = stream.set_read_timeout(Some(HEALTH_CHECK_IO_TIMEOUT));
    let _ = stream.set_write_timeout(Some(HEALTH_CHECK_IO_TIMEOUT));

    let request = format!("GET /healthz HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n");

    if stream.write_all(request.as_bytes()).is_err() {
        return false;
    }

    let mut response = String::new();

    if stream.read_to_string(&mut response).is_err() {
        return false;
    }

    response.starts_with("HTTP/1.1 200") || response.starts_with("HTTP/1.0 200")
}

fn emit_status<R: tauri::Runtime, S: Into<String>>(app: &AppHandle<R>, event: &str, message: S) {
    let payload = LaunchStatusPayload {
        message: message.into(),
    };

    let _ = app.emit(event, payload);
}

fn build_recent_menu_items<R: tauri::Runtime>(
    app: &AppHandle<R>,
) -> tauri::Result<Vec<MenuItem<R>>> {
    let recent_projects = load_recent_projects();

    if recent_projects.is_empty() {
        let empty = MenuItem::with_id(
            app,
            "file.recent.empty",
            "No Recent Projects",
            false,
            None::<&str>,
        )?;
        return Ok(vec![empty]);
    }

    recent_projects
        .iter()
        .enumerate()
        .map(|(index, project)| {
            let title = format!("{}  {}", project.label, project.root);
            MenuItem::with_id(
                app,
                format!("{FILE_RECENT_PREFIX}{index}"),
                title,
                true,
                None::<&str>,
            )
        })
        .collect()
}

fn navigate_to_project_launch<R: tauri::Runtime>(
    app: &AppHandle<R>,
    params: &[(&str, &str)],
) -> Result<(), String> {
    let base_url = running_base_url()?;
    let mut serializer = form_urlencoded::Serializer::new(String::new());

    for (key, value) in params {
        serializer.append_pair(key, value);
    }

    let url = format!("{base_url}/project-launch?{}", serializer.finish());
    let parsed = url
        .parse()
        .map_err(|error| format!("Failed to parse project launch URL {url}: {error}"))?;

    let window = app
        .get_webview_window("main")
        .ok_or_else(|| "Main window is not available".to_string())?;

    window
        .navigate(parsed)
        .map_err(|error| format!("Failed to navigate to project launch: {error}"))?;

    Ok(())
}

fn navigate_to_url<R: tauri::Runtime>(app: &AppHandle<R>, path: &str) -> Result<(), String> {
    let base_url = running_base_url()?;
    let url = format!("{base_url}{path}");
    let parsed = url
        .parse()
        .map_err(|error| format!("Failed to parse URL {url}: {error}"))?;

    let window = app
        .get_webview_window("main")
        .ok_or_else(|| "Main window is not available".to_string())?;

    window
        .navigate(parsed)
        .map_err(|error| format!("Failed to navigate to {path}: {error}"))?;

    Ok(())
}

fn running_base_url() -> Result<String, String> {
    let port = read_port_file()?;
    Ok(format!("http://127.0.0.1:{port}"))
}

fn normalize_project_root(explicit: Option<&str>) -> PathBuf {
    explicit
        .filter(|value| !value.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(fallback_project_root)
}

fn fallback_project_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap_or_else(|_| Path::new(env!("CARGO_MANIFEST_DIR")).join("../../.."))
}

fn load_recent_projects() -> Vec<RecentProject> {
    let path = persisted_state_path();
    let Ok(body) = std::fs::read_to_string(path) else {
        return vec![];
    };

    let Ok(json) = serde_json::from_str::<Value>(&body) else {
        return vec![];
    };

    json.get("recent_projects")
        .and_then(|value| value.as_array())
        .into_iter()
        .flatten()
        .filter_map(|entry| {
            let root = entry.get("root")?.as_str()?.to_string();
            let label = entry
                .get("label")
                .and_then(|value| value.as_str())
                .filter(|value| !value.trim().is_empty())
                .unwrap_or_else(|| {
                    Path::new(&root)
                        .file_name()
                        .and_then(|name| name.to_str())
                        .unwrap_or("Project")
                })
                .to_string();

            Some(RecentProject { label, root })
        })
        .collect()
}

fn persisted_state_path() -> PathBuf {
    let home_dir = foundry_home_dir();

    home_dir.join(".foundry").join("project_manager.json")
}

fn foundry_home_dir() -> PathBuf {
    env::var("FOUNDRY_HOME")
        .map(PathBuf::from)
        .or_else(|_| env::var("HOME").map(PathBuf::from))
        .unwrap_or_else(|_| fallback_project_root())
}

fn standalone_secret_path(foundry_home: &Path) -> PathBuf {
    foundry_home.join(".foundry").join(STANDALONE_SECRET_FILE)
}

fn ensure_standalone_secret(foundry_home: &Path) -> Result<String, String> {
    let secret_path = standalone_secret_path(foundry_home);

    if let Ok(existing) = fs::read_to_string(&secret_path) {
        let secret = existing.trim().to_string();

        if !secret.is_empty() {
            return Ok(secret);
        }
    }

    let secret = generate_standalone_secret()?;
    let parent = secret_path.parent().ok_or_else(|| {
        format!(
            "Standalone secret path {} has no parent directory",
            secret_path.display()
        )
    })?;

    fs::create_dir_all(parent)
        .map_err(|error| format!("Failed to create {}: {error}", parent.display()))?;
    fs::write(&secret_path, format!("{secret}\n"))
        .map_err(|error| format!("Failed to write {}: {error}", secret_path.display()))?;

    Ok(secret)
}

fn generate_standalone_secret() -> Result<String, String> {
    let mut bytes = [0_u8; 64];
    let mut random = File::open("/dev/urandom")
        .map_err(|error| format!("Failed to open /dev/urandom: {error}"))?;

    random
        .read_exact(&mut bytes)
        .map_err(|error| format!("Failed to read random bytes: {error}"))?;

    Ok(hex_encode(&bytes))
}

fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);

    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }

    output
}

fn store_sidecar<R: Runtime>(app: &AppHandle<R>, child: CommandChild) {
    let state = app.state::<FoundrySidecarState>();
    let mut lock = state.child.lock().expect("sidecar state lock poisoned");
    *lock = Some(child);
}

fn clear_sidecar<R: Runtime>(app: &AppHandle<R>) {
    let state = app.state::<FoundrySidecarState>();
    let mut lock = state.child.lock().expect("sidecar state lock poisoned");
    lock.take();
}

fn shutdown_sidecar<R: Runtime>(app: &AppHandle<R>) {
    let state = app.state::<FoundrySidecarState>();
    let child = {
        let mut lock = state.child.lock().expect("sidecar state lock poisoned");
        lock.take()
    };

    if let Some(child) = child {
        let _ = child.kill();
    }
}

#[cfg(test)]
mod tests {
    use super::{
        ensure_standalone_secret, fallback_project_root, normalize_project_root,
        persisted_state_path, standalone_secret_path,
    };
    use std::env;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};
    use std::{fs, process};

    #[test]
    fn normalize_project_root_prefers_override() {
        let expected = PathBuf::from("/tmp/foundry");

        assert_eq!(
            normalize_project_root(Some(expected.to_string_lossy().as_ref())),
            expected
        );
    }

    #[test]
    fn fallback_project_root_points_at_repo_root() {
        let root = fallback_project_root();

        assert!(root.join("mix.exs").exists(), "expected repo root mix.exs");
        assert!(
            root.join(".foundry").exists(),
            "expected repo root .foundry directory"
        );
    }

    #[test]
    fn persisted_state_path_ends_with_project_manager_json() {
        assert!(persisted_state_path()
            .to_string_lossy()
            .ends_with(".foundry/project_manager.json"));
    }

    #[test]
    fn ensure_standalone_secret_reuses_existing_secret() {
        let home_dir = unique_tmp_dir("secret-reuse");
        let secret_path = standalone_secret_path(&home_dir);

        fs::create_dir_all(secret_path.parent().unwrap()).unwrap();
        fs::write(&secret_path, "existing-secret\n").unwrap();

        assert_eq!(
            ensure_standalone_secret(&home_dir).unwrap(),
            "existing-secret"
        );
    }

    #[test]
    fn ensure_standalone_secret_generates_and_persists_secret() {
        let home_dir = unique_tmp_dir("secret-generate");
        let secret_path = standalone_secret_path(&home_dir);
        let secret = ensure_standalone_secret(&home_dir).unwrap();

        assert_eq!(secret.len(), 128);
        assert!(secret.chars().all(|char| char.is_ascii_hexdigit()));
        assert_eq!(
            fs::read_to_string(secret_path).unwrap(),
            format!("{secret}\n")
        );
    }

    fn unique_tmp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = env::temp_dir().join(format!(
            "foundry-desktop-{label}-{}-{unique}",
            process::id()
        ));

        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).unwrap();
        path
    }
}
