#include <windows.h>
#include <filesystem>
#include <string>
#include <system_error>

namespace fs = std::filesystem;

static void write_log(const std::wstring& message) {
  wchar_t temp_path[MAX_PATH] = {0};
  if (GetTempPathW(MAX_PATH, temp_path) == 0) return;
  std::wstring path = std::wstring(temp_path) + L"chernogram-update.log";
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                            FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  SYSTEMTIME st{};
  GetLocalTime(&st);
  wchar_t line[2048] = {0};
  _snwprintf_s(line, _countof(line), _TRUNCATE,
               L"[%04d-%02d-%02d %02d:%02d:%02d] %s\r\n",
               st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
               message.c_str());
  const DWORD bytes = static_cast<DWORD>(wcslen(line) * sizeof(wchar_t));
  DWORD written = 0;
  WriteFile(file, line, bytes, &written, nullptr);
  CloseHandle(file);
}

static bool copy_tree(const fs::path& source, const fs::path& destination) {
  std::error_code ec;
  fs::create_directories(destination, ec);
  if (ec) return false;

  for (const auto& entry : fs::recursive_directory_iterator(source, ec)) {
    if (ec) return false;
    const fs::path relative = fs::relative(entry.path(), source, ec);
    if (ec) return false;
    const fs::path target = destination / relative;
    if (entry.is_directory()) {
      fs::create_directories(target, ec);
      if (ec) return false;
    } else if (entry.is_regular_file()) {
      fs::create_directories(target.parent_path(), ec);
      if (ec) return false;
      fs::copy_file(entry.path(), target,
                    fs::copy_options::overwrite_existing, ec);
      if (ec) {
        write_log(L"Copy failed: " + entry.path().wstring() + L" -> " +
                  target.wstring() + L" (" + std::to_wstring(ec.value()) + L")");
        return false;
      }
    }
  }
  return true;
}

int wmain(int argc, wchar_t* argv[]) {
  if (argc < 5) return 2;

  const DWORD old_pid = static_cast<DWORD>(_wtoi(argv[1]));
  const fs::path stage = argv[2];
  const fs::path destination = argv[3];
  const fs::path exe_name = argv[4];

  write_log(L"Updater started for PID " + std::to_wstring(old_pid));

  HANDLE old_process = OpenProcess(SYNCHRONIZE, FALSE, old_pid);
  if (old_process != nullptr) {
    const DWORD wait_result = WaitForSingleObject(old_process, 60000);
    CloseHandle(old_process);
    if (wait_result != WAIT_OBJECT_0) {
      write_log(L"Old process did not exit in time");
      return 3;
    }
  }

  Sleep(350);
  if (!fs::exists(stage)) {
    write_log(L"Stage directory is missing");
    return 4;
  }

  if (!copy_tree(stage, destination)) {
    write_log(L"Copy tree failed");
    return 5;
  }

  const fs::path target = destination / exe_name;
  if (!fs::exists(target)) {
    write_log(L"Updated executable is missing");
    return 6;
  }

  std::wstring command = L"\"" + target.wstring() + L"\"";
  STARTUPINFOW si{};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi{};
  std::wstring mutable_command = command;
  const BOOL started = CreateProcessW(
      target.c_str(), mutable_command.data(), nullptr, nullptr, FALSE, 0,
      nullptr, destination.c_str(), &si, &pi);
  if (!started) {
    write_log(L"CreateProcess failed: " + std::to_wstring(GetLastError()));
    return 7;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);

  write_log(L"Update completed and Chernogram restarted");
  std::error_code ec;
  fs::remove_all(stage.parent_path(), ec);
  return 0;
}
