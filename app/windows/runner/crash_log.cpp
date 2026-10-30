#include "crash_log.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <string>

namespace {
constexpr LONGLONG kMaxBytes = 256 * 1024;
LONG handling_crash = 0;

std::wstring Environment(const wchar_t* name) {
  wchar_t value[4096] = {};
  const DWORD size = GetEnvironmentVariableW(name, value, 4096);
  return size > 0 && size < 4096 ? std::wstring(value, size) : L"";
}

std::wstring LogDirectory() {
  auto path = Environment(L"CHAOWEN_LOG_DIR");
  if (path.empty()) {
    path = Environment(L"LOCALAPPDATA");
    if (path.empty()) path = Environment(L"TEMP");
    if (path.empty()) return L"";
    path += L"\\rmrb-reader";
    CreateDirectoryW(path.c_str(), nullptr);
    path += L"\\logs";
  }
  CreateDirectoryW(path.c_str(), nullptr);
  return path;
}

void WriteRecord(const char* record) {
  const auto directory = LogDirectory();
  if (directory.empty()) return;
  const auto lock_path = directory + L"\\native.lock";
  HANDLE lock = CreateFileW(lock_path.c_str(), GENERIC_WRITE, 0, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (lock == INVALID_HANDLE_VALUE) return;
  const auto path = directory + L"\\native.log";
  const auto backup = path + L".1";
  const DWORD length = static_cast<DWORD>(strlen(record));
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                            nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  LARGE_INTEGER size = {};
  if (file != INVALID_HANDLE_VALUE) {
    GetFileSizeEx(file, &size);
    CloseHandle(file);
  }
  bool ready = true;
  if (size.QuadPart + length > kMaxBytes) {
    DeleteFileW(backup.c_str());
    ready = MoveFileW(path.c_str(), backup.c_str()) != FALSE;
  }
  if (ready) {
    file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                       nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
      DWORD written = 0;
      WriteFile(file, record, length, &written, nullptr);
      FlushFileBuffers(file);
      CloseHandle(file);
    }
  }
  CloseHandle(lock);
}

LONG WINAPI UnhandledException(EXCEPTION_POINTERS* exception) {
  if (InterlockedExchange(&handling_crash, 1) != 0) return EXCEPTION_CONTINUE_SEARCH;
  SYSTEMTIME now;
  GetSystemTime(&now);
  char record[2048] = {};
  const auto* fault = exception->ExceptionRecord;
#ifdef _M_X64
  const auto* context = exception->ContextRecord;
  snprintf(record, sizeof(record),
           "%04u-%02u-%02uT%02u:%02u:%02uZ native.crash pid=%lu thread=%lu "
           "code=0x%08lx address=%p RIP=0x%llx RSP=0x%llx RBP=0x%llx\n",
           now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
           GetCurrentProcessId(), GetCurrentThreadId(), fault->ExceptionCode,
           fault->ExceptionAddress, context->Rip, context->Rsp, context->Rbp);
#else
  snprintf(record, sizeof(record),
           "native.crash pid=%lu thread=%lu code=0x%08lx address=%p\n",
           GetCurrentProcessId(), GetCurrentThreadId(), fault->ExceptionCode,
           fault->ExceptionAddress);
#endif
  WriteRecord(record);
  return EXCEPTION_CONTINUE_SEARCH;
}
}  // namespace

void InstallNativeCrashLogging() {
  SetUnhandledExceptionFilter(UnhandledException);
  std::set_terminate([] {
    WriteRecord("native.terminate unhandled C++ exception\n");
    std::abort();
  });
}
