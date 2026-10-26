#include "flutter_window.h"

#include <optional>
#include <commdlg.h>
#include <wtsapi32.h>
#include <flutter/standard_method_codec.h>
#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  local_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "password_manager/windows",
      &flutter::StandardMethodCodec::GetInstance());
  local_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "chooseBackup" || method == "chooseExport") {
      wchar_t path[32768] = {};
      const bool save = method == "chooseExport";
      if (save) wcscpy_s(path, L"copia-cifrada.kdbx");
      OPENFILENAMEW dialog = {};
      dialog.lStructSize = sizeof(dialog);
      dialog.hwndOwner = GetHandle();
      dialog.lpstrFilter = L"Bovedas cifradas\0*.kdbx;*.bak\0Todos los archivos\0*.*\0\0";
      dialog.lpstrFile = path;
      dialog.nMaxFile = 32768;
      dialog.lpstrDefExt = L"kdbx";
      dialog.Flags = OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST |
          (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
      const BOOL selected = save ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog);
      if (selected) {
        result->Success(flutter::EncodableValue(Utf8FromUtf16(path)));
      } else if (CommDlgExtendedError() != 0) {
        result->Error("dialog", "No se pudo abrir el selector de archivos.");
      } else {
        result->Success();
      }
      return;
    }
    result->NotImplemented();
  });

  session_notifications_registered_ =
      WTSRegisterSessionNotification(GetHandle(), NOTIFY_FOR_THIS_SESSION) != FALSE;
  if (!session_notifications_registered_) return false;

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (session_notifications_registered_) {
    WTSUnRegisterSessionNotification(GetHandle());
    session_notifications_registered_ = false;
  }
  local_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Session lock is independent of Flutter's visible/minimized window state.
  // Handle it before plugins can consume the native message. Unlock/resume also
  // requests locking, so returning to Windows never automatically unlocks a vault.
  const bool session_lock = message == WM_WTSSESSION_CHANGE &&
      (wparam == WTS_SESSION_LOCK || wparam == WTS_SESSION_UNLOCK ||
       wparam == WTS_CONSOLE_DISCONNECT || wparam == WTS_REMOTE_DISCONNECT);
  const bool suspend_or_resume = message == WM_POWERBROADCAST &&
      (wparam == PBT_APMSUSPEND || wparam == PBT_APMRESUMEAUTOMATIC ||
       wparam == PBT_APMRESUMESUSPEND);
  if ((session_lock || suspend_or_resume) && local_channel_) {
    local_channel_->InvokeMethod("lockSession", nullptr);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

