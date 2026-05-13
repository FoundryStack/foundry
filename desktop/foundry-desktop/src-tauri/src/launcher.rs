use serde::Serialize;
use std::env;
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_shell::{process::CommandEvent, ShellExt};

const HEALTH_TIMEOUT: Duration = Duration::from_secs(15);
const HEALTH_POLL_INTERVAL: Duration = Duration::from_millis(100);
const SIDECAR_NAME: &str = "foundry-sidecar";
const STATUS_EVENT: &str = "foundry://launch-status";
const ERROR_EVENT: &str = "foundry://launch-error";

#[derive(Clone, Serialize)]
pub struct LaunchStatusPayload {
    pub message: String,
}

pub fn start_foundry(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        if let Err(message) = launch_and_navigate(app.clone()).await {
            emit_status(&app, ERROR_EVENT, message);
        }
    });
}

async fn launch_and_navigate(app: AppHandle) -> Result<(), String> {
    emit_status(&app, STATUS_EVENT, "Preparing Foundry sidecar...");

    let project_root = normalize_project_root(env::var("FOUNDRY_PROJECT_ROOT").ok().as_deref());
    let project_root_string = project_root.to_string_lossy().to_string();

    let command = app
        .shell()
        .sidecar(SIDECAR_NAME)
        .map_err(|error| format!("Failed to prepare sidecar: {error}"))?
        .args([
            "studio",
            "--project",
            project_root_string.as_str(),
            "--port",
            "auto",
            "--no-browser",
        ]);

    let (mut rx, _child) = command
        .spawn()
        .map_err(|error| format!("Failed to spawn Foundry sidecar: {error}"))?;

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
                _ => {}
            }
        }
    });

    emit_status(
        &app,
        STATUS_EVENT,
        "Waiting for Foundry to become healthy...",
    );

    let url = wait_for_health()?;
    emit_status(&app, STATUS_EVENT, format!("Foundry ready at {url}"));

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

fn wait_for_health() -> Result<String, String> {
    let started_at = Instant::now();

    loop {
        if started_at.elapsed() > HEALTH_TIMEOUT {
            return Err("Foundry sidecar did not become healthy within 15 seconds.".to_string());
        }

        if let Ok(port) = read_port_file() {
            let url = format!("http://127.0.0.1:{port}");

            if health_check(&url) {
                return Ok(url);
            }
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

    let _ = stream.set_read_timeout(Some(Duration::from_millis(750)));
    let _ = stream.set_write_timeout(Some(Duration::from_millis(750)));

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

fn emit_status<S: Into<String>>(app: &AppHandle, event: &str, message: S) {
    let payload = LaunchStatusPayload {
        message: message.into(),
    };

    let _ = app.emit(event, payload);
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

#[cfg(test)]
mod tests {
    use super::{fallback_project_root, normalize_project_root};
    use std::path::PathBuf;

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
}
