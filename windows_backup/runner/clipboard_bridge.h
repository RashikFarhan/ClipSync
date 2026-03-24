// clipboard_bridge.h — Win32 Clipboard Injector + Registry Bridge
// Declares the MethodChannel handlers for:
//   - "setWindowsClipboard"  → OpenClipboard / SetClipboardData
//   - "setStartOnBoot"       → HKCU\...\Run registry key
#pragma once

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#include <windows.h>
#include <string>

namespace clipboard_bridge {

// ─────────────────────────────────────────────
// Clipboard Injector
// Writes |text| to the Windows system clipboard
// using CF_UNICODETEXT.
// Returns true on success.
// ─────────────────────────────────────────────
static bool SetWindowsClipboard(const std::wstring& text) {
    if (!OpenClipboard(nullptr)) return false;
    EmptyClipboard();

    // Allocate global memory for the unicode string
    size_t byte_count = (text.size() + 1) * sizeof(wchar_t);
    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, byte_count);
    if (!hMem) {
        CloseClipboard();
        return false;
    }

    void* pMem = GlobalLock(hMem);
    memcpy(pMem, text.c_str(), byte_count);
    GlobalUnlock(hMem);

    SetClipboardData(CF_UNICODETEXT, hMem);
    CloseClipboard();
    return true;
}

// ─────────────────────────────────────────────
// Registry: Launch-on-Startup Toggle
// Adds / removes this EXE from HKCU Run key.
// ─────────────────────────────────────────────
static const wchar_t* kRunKey =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
static const wchar_t* kAppName = L"ClipSync";

static bool SetStartOnBoot(bool enable) {
    HKEY hKey;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &hKey)
        != ERROR_SUCCESS) {
        return false;
    }

    bool ok;
    if (enable) {
        // Get current EXE path
        wchar_t exePath[MAX_PATH];
        GetModuleFileNameW(nullptr, exePath, MAX_PATH);
        ok = (RegSetValueExW(hKey, kAppName, 0, REG_SZ,
                             reinterpret_cast<const BYTE*>(exePath),
                             static_cast<DWORD>((wcslen(exePath) + 1) * sizeof(wchar_t)))
              == ERROR_SUCCESS);
    } else {
        LSTATUS result = RegDeleteValueW(hKey, kAppName);
        ok = (result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
    }

    RegCloseKey(hKey);
    return ok;
}

// ─────────────────────────────────────────────
// Check if startup key exists
// ─────────────────────────────────────────────
static bool IsStartOnBootEnabled() {
    HKEY hKey;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_READ, &hKey)
        != ERROR_SUCCESS) {
        return false;
    }
    DWORD type;
    LSTATUS result = RegQueryValueExW(hKey, kAppName, nullptr, &type, nullptr, nullptr);
    RegCloseKey(hKey);
    return (result == ERROR_SUCCESS);
}

// ─────────────────────────────────────────────
// RegisterMethodHandlers
// Call from FlutterWindow::OnCreate() after
// RegisterPlugins() to attach the channel.
// ─────────────────────────────────────────────
static void RegisterMethodHandlers(flutter::BinaryMessenger* messenger) {
    auto channel = std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger,
        "com.antigravity.clipsync/windows",
        &flutter::StandardMethodCodec::GetInstance()
    );

    channel->SetMethodCallHandler(
        [](const flutter::MethodCall<flutter::EncodableValue>& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

            if (call.method_name() == "setWindowsClipboard") {
                const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                if (!args) { result->Error("INVALID_ARGS", "Expected map"); return; }

                auto it = args->find(flutter::EncodableValue("text"));
                if (it == args->end()) { result->Error("MISSING_KEY", "No 'text' key"); return; }

                const std::string& utf8 = std::get<std::string>(it->second);

                // Convert UTF-8 → UTF-16
                int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
                std::wstring wide(len, 0);
                MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), len);

                bool ok = SetWindowsClipboard(wide);
                if (ok) result->Success(flutter::EncodableValue(true));
                else    result->Error("CLIP_FAIL", "OpenClipboard failed");

            } else if (call.method_name() == "setStartOnBoot") {
                const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
                bool enable = false;
                if (args) {
                    auto it = args->find(flutter::EncodableValue("enable"));
                    if (it != args->end()) enable = std::get<bool>(it->second);
                }
                bool ok = SetStartOnBoot(enable);
                result->Success(flutter::EncodableValue(ok));

            } else if (call.method_name() == "getStartOnBoot") {
                result->Success(flutter::EncodableValue(IsStartOnBootEnabled()));

            } else {
                result->NotImplemented();
            }
        }
    );

    // Keep channel alive — store it in a static so it isn't destroyed
    static auto s_channel = channel;
}

} // namespace clipboard_bridge
