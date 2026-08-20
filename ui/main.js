const app = document.querySelector('#app');
const invoke = window.__TAURI__?.core?.invoke;
const listen = window.__TAURI__?.event?.listen;

async function boot() {
  if (!invoke) {
    app.textContent = '请通过 DeepSeekHarness.exe 启动此应用。';
    return;
  }
  try {
    const url = await invoke('boot_url');
    window.location.replace(url);
  } catch (error) {
    app.textContent = String(error);
  }
}

async function restart() {
  if (!invoke) return;
  app.textContent = '正在重启 Harness 服务…';
  try {
    const url = await invoke('restart_harness');
    window.location.replace(url);
  } catch (error) {
    app.textContent = 'Harness 重启失败：' + String(error);
  }
}

if (listen) {
  listen('restart-harness', restart);
}
boot();
