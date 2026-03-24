#include "flutter_window.h"

#include <optional>

#include <flutter/generated_plugin_registrant.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include "clipboard_bridge.h"

// Loop-guard: set to true while our injector is writing to the clipboard
// so WM_CLIPBOARDUPDATE does not echo the event back to Dart.
static bool g_injecting_clipboard = false;

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

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // Register native Windows MethodChannel handlers
  clipboard_bridge::RegisterMethodHandlers(
      flutter_controller_->engine()->messenger(), GetHandle());

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_CLIPBOARDUPDATE: {
      // Skip if we are the ones who just wrote to the clipboard (loop-guard)
      if (!g_injecting_clipboard && flutter_controller_) {
        flutter::MethodChannel<flutter::EncodableValue> channel(
            flutter_controller_->engine()->messenger(), "com.antigravity.clipsync/clipboard",
            &flutter::StandardMethodCodec::GetInstance());
        channel.InvokeMethod("onNativeClipboardUpdate", std::make_unique<flutter::EncodableValue>());
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
