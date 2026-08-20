use std::{
    env,
    fs::{create_dir_all, read_to_string, OpenOptions},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};
use tauri::{
    menu::{MenuBuilder, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, RunEvent, State, WindowEvent,
};

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const DETACHED_PROCESS: u32 = 0x00000008;
#[cfg(target_os = "windows")]
const CREATE_NEW_PROCESS_GROUP: u32 = 0x00000200;
#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

struct AppState {
    harness: Mutex<Option<Child>>,
    quitting: AtomicBool,
}

#[cfg(target_os = "windows")]
fn ensure_single_instance() {
    use std::{ptr::null_mut, sync::OnceLock};
    use windows_sys::Win32::Foundation::ERROR_ALREADY_EXISTS;
    use windows_sys::Win32::System::Threading::CreateMutexW;
    static HANDLE: OnceLock<isize> = OnceLock::new();
    let name: Vec<u16> = "Global\\DeepSeekHarnessDesktopSingleInstance"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    unsafe {
        let handle = CreateMutexW(null_mut(), 0, name.as_ptr());
        if handle.is_null()
            || windows_sys::Win32::Foundation::GetLastError() == ERROR_ALREADY_EXISTS
        {
            std::process::exit(0);
        }
        let _ = HANDLE.set(handle as isize);
    }
}

fn free_port() -> std::io::Result<u16> {
    let socket = TcpListener::bind(("127.0.0.1", 0))?;
    Ok(socket.local_addr()?.port())
}

fn runtime_root(app: &AppHandle) -> PathBuf {
    app.path()
        .resource_dir()
        .unwrap_or_else(|_| env::current_exe().unwrap().parent().unwrap().to_path_buf())
}

fn resolve_resource(root: &Path, name: &str) -> PathBuf {
    let candidates = [
        root.join(name),
        root.join("resources").join(name),
        root.join("_up_").join(name),
        env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|p| p.join(name)))
            .unwrap_or_default(),
    ];
    candidates
        .into_iter()
        .find(|path| path.exists())
        .unwrap_or_else(|| root.join(name))
}

fn start_harness(
    app: &AppHandle,
    state: &State<AppState>,
) -> Result<(String, PathBuf, u16), String> {
    let port = free_port().map_err(|e| format!("无法选择端口: {e}"))?;
    let root = runtime_root(app);
    let node = resolve_resource(&root, "runtime").join("node.exe");
    let harness = resolve_resource(&root, "harness-dist");
    let entry = harness.join("lib").join("bin.js");
    if !node.exists() || !entry.exists() {
        return Err("运行时文件不完整，请确认已正确解压发布包。".into());
    }
    let log_dir = app
        .path()
        .app_data_dir()
        .unwrap_or_else(|_| root.join("logs"))
        .join("logs");
    create_dir_all(&log_dir).map_err(|e| format!("无法创建日志目录: {e}"))?;
    let log_path = log_dir.join("harness.log");
    let log = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&log_path)
        .map_err(|e| format!("无法创建日志文件: {e}"))?;
    let err_log = log
        .try_clone()
        .map_err(|e| format!("无法打开错误日志: {e}"))?;
    let mut command = Command::new(node);
    command
        .arg(entry)
        .arg("web")
        .arg("--no-open")
        .arg("--port")
        .arg(port.to_string())
        .env("DSH_DESKTOP", "1")
        .current_dir(harness)
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(err_log))
        .stdin(Stdio::null());
    #[cfg(target_os = "windows")]
    command.creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW);
    let child = command
        .spawn()
        .map_err(|e| format!("启动 Harness 失败: {e}"))?;
    *state.harness.lock().map_err(|_| "无法锁定服务状态")? = Some(child);
    Ok((format!("http://127.0.0.1:{port}"), log_path, port))
}

fn log_tail(path: &Path) -> String {
    let content = read_to_string(path).unwrap_or_default();
    let mut chars: Vec<char> = content.chars().rev().take(4000).collect();
    chars.reverse();
    chars.into_iter().collect()
}

fn stop_harness(state: &AppState) {
    if let Ok(mut guard) = state.harness.lock() {
        if let Some(mut child) = guard.take() {
            #[cfg(target_os = "windows")]
            {
                let pid = child.id().to_string();
                let mut taskkill = Command::new("taskkill");
                taskkill
                    .args(["/PID", &pid, "/T", "/F"])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null());
                taskkill.creation_flags(CREATE_NO_WINDOW);
                let _ = taskkill.status();
            }
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[tauri::command]
fn boot_url(app: AppHandle, state: State<AppState>) -> Result<String, String> {
    let (url, log_path, port) = start_harness(&app, &state)?;
    let started = Instant::now();
    while started.elapsed() < Duration::from_secs(120) {
        {
            let mut guard = state.harness.lock().map_err(|_| "无法锁定服务状态")?;
            if let Some(child) = guard.as_mut() {
                if let Some(status) = child
                    .try_wait()
                    .map_err(|e| format!("无法检查 Harness 状态: {e}"))?
                {
                    guard.take();
                    return Err(format!(
                        "Harness 启动失败（退出码 {}）。\n日志：{}\n{}",
                        status
                            .code()
                            .map_or_else(|| "未知".into(), |code| code.to_string()),
                        log_path.display(),
                        log_tail(&log_path),
                    ));
                }
            }
        }
        if TcpStream::connect_timeout(
            &format!("127.0.0.1:{port}")
                .parse()
                .map_err(|e| format!("端口地址无效: {e}"))?,
            Duration::from_millis(300),
        )
        .is_ok()
        {
            return Ok(url);
        }
        thread::sleep(Duration::from_millis(200));
    }
    stop_harness(&state);
    Err(format!(
        "Harness 启动超时。日志：{}\n{}",
        log_path.display(),
        log_tail(&log_path)
    ))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(target_os = "windows")]
    ensure_single_instance();

    tauri::Builder::default()
        .manage(AppState {
            harness: Mutex::new(None),
            quitting: AtomicBool::new(false),
        })
        .invoke_handler(tauri::generate_handler![boot_url])
        .setup(|app| {
            let show = MenuItem::with_id(app, "show", "打开主界面", true, None::<&str>)?;
            let logs = MenuItem::with_id(app, "logs", "打开日志目录", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "彻底退出", true, None::<&str>)?;
            let menu = MenuBuilder::new(app)
                .items(&[&show, &logs, &quit])
                .build()?;
            let icon = app.default_window_icon().cloned().ok_or("未找到应用图标")?;
            TrayIconBuilder::new()
                .icon(icon)
                .tooltip("DeepSeek Harness")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                    "logs" => {
                        if let Ok(path) = app.path().app_data_dir() {
                            let _ = std::process::Command::new("explorer.exe")
                                .arg(path.join("logs"))
                                .spawn();
                        }
                    }
                    "quit" => {
                        app.state::<AppState>()
                            .quitting
                            .store(true, Ordering::SeqCst);
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::DoubleClick { .. } = event {
                        if let Some(window) = tray.app_handle().get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| match event {
            RunEvent::WindowEvent {
                label,
                event: WindowEvent::CloseRequested { api, .. },
                ..
            } if label == "main" && !app.state::<AppState>().quitting.load(Ordering::SeqCst) => {
                api.prevent_close();
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.hide();
                }
            }
            RunEvent::Exit => stop_harness(&app.state::<AppState>()),
            _ => {}
        });
}
