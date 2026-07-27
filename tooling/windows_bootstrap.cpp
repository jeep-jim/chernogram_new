#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>

namespace {
std::wstring QuoteArgument(const std::wstring& value) {
  std::wstring quoted = L"\"";
  unsigned int backslashes = 0;
  for (wchar_t ch : value) {
    if (ch == L'\\') {
      ++backslashes;
      continue;
    }
    if (ch == L'\"') {
      quoted.append(backslashes * 2 + 1, L'\\');
      quoted.push_back(L'\"');
      backslashes = 0;
      continue;
    }
    quoted.append(backslashes, L'\\');
    backslashes = 0;
    quoted.push_back(ch);
  }
  quoted.append(backslashes * 2, L'\\');
  quoted.push_back(L'\"');
  return quoted;
}

std::wstring ModuleDirectory() {
  std::vector<wchar_t> buffer(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(),
                                          static_cast<DWORD>(buffer.size()));
  if (length == 0 || length >= buffer.size()) return L"";
  std::wstring path(buffer.data(), length);
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? L"" : path.substr(0, slash);
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  const std::wstring root = ModuleDirectory();
  if (root.empty()) return 2;

  const std::wstring app_dir = root + L"\\app";
  const std::wstring target = app_dir + L"\\chernogram.exe";
  if (GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES) return 3;

  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::wstring command_line = QuoteArgument(target);
  if (argv != nullptr) {
    for (int index = 1; index < argc; ++index) {
      command_line.push_back(L' ');
      command_line += QuoteArgument(argv[index]);
    }
    LocalFree(argv);
  }

  std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
  mutable_command.push_back(L'\0');

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  const BOOL started = CreateProcessW(
      target.c_str(), mutable_command.data(), nullptr, nullptr, FALSE, 0, nullptr,
      app_dir.c_str(), &startup, &process);
  if (!started) return static_cast<int>(GetLastError());

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return 0;
}
