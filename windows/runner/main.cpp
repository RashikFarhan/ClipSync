#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(420, 780);

  // ── Silent autostart: create window but keep it hidden until Dart shows it.
  // When launched with --autostart (Windows startup), we pass SW_HIDE so the
  // window is never shown — the app lives purely in the system tray.
  bool is_autostart = false;
  int argc;
  LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv) {
    for (int i = 1; i < argc; ++i) {
      if (::wcscmp(argv[i], L"--autostart") == 0) {
        is_autostart = true;
        break;
      }
    }
    ::LocalFree(argv);
  }

  if (!window.Create(L"clip_sync", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(false);

  // If autostart: keep the window hidden. The system_tray / window_manager
  // Dart code will show it explicitly when the user clicks the tray icon.
  if (is_autostart) {
    ::ShowWindow(window.GetHandle(), SW_HIDE);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
