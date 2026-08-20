!macro NSIS_HOOK_PREINSTALL
  ; Close a running copy before replacing its bundled native DLLs.
  ExecWait 'taskkill.exe /F /T /IM "deepseek-harness-desktop.exe"' $0
  Sleep 1200
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  ; Ensure the application tree is not holding files during uninstall.
  ExecWait 'taskkill.exe /F /T /IM "deepseek-harness-desktop.exe"' $0
  Sleep 1200
!macroend
