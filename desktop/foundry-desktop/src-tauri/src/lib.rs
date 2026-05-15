mod launcher;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app = tauri::Builder::default()
        .menu(|app| launcher::build_menu(app))
        .on_menu_event(|app, event| launcher::handle_menu_event(app, event))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            app.manage(launcher::FoundrySidecarState::default());
            launcher::start_foundry(app.handle().clone());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    app.run(|app_handle, event| {
        launcher::handle_run_event(app_handle, &event);
    });
}
