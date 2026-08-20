const app = document.querySelector('#app');
const invoke = window.__TAURI__?.core?.invoke;

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
boot();
