use std::{
    env,
    fs::{create_dir_all, read_to_string, OpenOptions},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::Mutex,
    thread,
    time::{Duration, Instant},
};
use tauri::{AppHandle, Manager, State};

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

struct HarnessProcess(Mutex<Option<Child>>);

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
    state: &State<HarnessProcess>,
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
        .stderr(Stdio::from(err_log));
    #[cfg(target_os = "windows")]
    command.creation_flags(CREATE_NO_WINDOW);
    let child = command
        .spawn()
        .map_err(|e| format!("启动 Harness 失败: {e}"))?;
    *state.0.lock().map_err(|_| "无法锁定服务状态")? = Some(child);
    Ok((format!("http://127.0.0.1:{port}"), log_path, port))
}

fn log_tail(path: &Path) -> String {
    let content = read_to_string(path).unwrap_or_default();
    let mut chars: Vec<char> = content.chars().rev().take(4000).collect();
    chars.reverse();
    chars.into_iter().collect()
}

fn stop_harness(state: &HarnessProcess) {
    if let Ok(mut guard) = state.0.lock() {
        if let Some(mut child) = guard.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[tauri::command]
fn boot_url(app: AppHandle, state: State<HarnessProcess>) -> Result<String, String> {
    let (url, log_path, port) = start_harness(&app, &state)?;
    let started = Instant::now();
    while started.elapsed() < Duration::from_secs(120) {
        {
            let mut guard = state.0.lock().map_err(|_| "无法锁定服务状态")?;
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
    tauri::Builder::default()
        .manage(HarnessProcess(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![boot_url])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                stop_harness(&app.state::<HarnessProcess>());
            }
        });
}
