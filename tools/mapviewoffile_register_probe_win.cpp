// G4 — Decisive probe: does cuMemHostRegister succeed on a MapViewOfFile view?
//
// This answers the single question that decides the DS4 0050 zero-copy port to
// native Windows (see docs/PORT_WINDOWS_NATIVE/README.md §5):
//
//   Can a range of a CreateFileMappingW(PAGE_READONLY)+MapViewOfFile(FILE_MAP_READ)
//   section view be page-locked by cuMemHostRegister(READ_ONLY|DEVICEMAP) on the
//   RTX 3060 under WDDM, and then DMA'd to VRAM at pinned bandwidth?
//
//     SUCCESS -> port the Linux register-mmap zero-copy path directly (remove the
//                `#ifdef _WIN32 g_model_range_mapping_supported = 0` guards).
//     FAILURE -> use the pinned-arena copy design (handoff §7 / 0051): the section
//                view stays pageable, copy masked bytes into a cudaHostAlloc arena,
//                DMA arena->VRAM. ds4-win preemptively assumed FAILURE and never tested.
//
// Deliberately depends ONLY on System32\nvcuda.dll via the CUDA Driver API — no
// cuda.h, no cuda.lib, no CUDA Toolkit. Mirrors the ABI-handling idiom of
// runs/ds4/20260712_v2_zerocopy/tools/cuda_pinned_arena_probe_win.cpp.
//
// Build (once a C++ compiler exists on the box; see BUILD_AND_RUN.md):
//   MSVC : cl /std:c++17 /O2 /EHsc mapviewoffile_register_probe_win.cpp
//   MinGW: x86_64-w64-mingw32-g++ -std=c++17 -O2 -static -o mvof_probe.exe mapviewoffile_register_probe_win.cpp
//
// Run:
//   mvof_probe.exe [path-to-large-file] [range_MiB]
//   - path omitted  -> creates a temp file of (range_MiB + 64) MiB with a known pattern.
//   - path given    -> maps that file read-only (e.g. the real ds4-2bit.gguf) and
//                       registers a range from its middle. Content is NOT modified.
//   - range_MiB default 512.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#if !defined(_WIN64)
#error This probe supports only the Windows x64 CUDA Driver ABI.
#endif

namespace {

using Clock = std::chrono::steady_clock;
constexpr std::uint64_t kMiB = 1024ull * 1024ull;
constexpr std::uint64_t kGiB = 1024ull * kMiB;

// ---- Minimal CUDA Driver API surface (no cuda.h) ----
#define CUDAAPI __stdcall
using CUresult = int;
using CUdevice = int;
using CUdeviceptr = unsigned long long;  // x64 v2 ABI
struct CUctx_st;
struct CUstream_st;
using CUcontext = CUctx_st*;
using CUstream = CUstream_st*;

constexpr CUresult CUDA_SUCCESS = 0;
constexpr unsigned int CU_STREAM_NON_BLOCKING = 0x1;
// cuMemHostRegister flags (from cuda.h, stable ABI values):
constexpr unsigned int CU_MEMHOSTREGISTER_PORTABLE = 0x01;
constexpr unsigned int CU_MEMHOSTREGISTER_DEVICEMAP = 0x02;
constexpr unsigned int CU_MEMHOSTREGISTER_IOMEMORY = 0x04;
constexpr unsigned int CU_MEMHOSTREGISTER_READ_ONLY = 0x08;

using PfnCuInit = CUresult(CUDAAPI*)(unsigned int);
using PfnCuGetErrorName = CUresult(CUDAAPI*)(CUresult, const char**);
using PfnCuGetErrorString = CUresult(CUDAAPI*)(CUresult, const char**);
using PfnCuDeviceGet = CUresult(CUDAAPI*)(CUdevice*, int);
using PfnCuCtxCreate = CUresult(CUDAAPI*)(CUcontext*, unsigned int, CUdevice);
using PfnCuCtxDestroy = CUresult(CUDAAPI*)(CUcontext);
using PfnCuMemAlloc = CUresult(CUDAAPI*)(CUdeviceptr*, size_t);
using PfnCuMemFree = CUresult(CUDAAPI*)(CUdeviceptr);
using PfnCuMemHostRegister = CUresult(CUDAAPI*)(void*, size_t, unsigned int);
using PfnCuMemHostUnregister = CUresult(CUDAAPI*)(void*);
using PfnCuMemHostGetDevicePointer = CUresult(CUDAAPI*)(CUdeviceptr*, void*, unsigned int);
using PfnCuMemcpyHtoDAsync = CUresult(CUDAAPI*)(CUdeviceptr, const void*, size_t, CUstream);
using PfnCuMemcpyDtoH = CUresult(CUDAAPI*)(void*, CUdeviceptr, size_t);
using PfnCuStreamCreate = CUresult(CUDAAPI*)(CUstream*, unsigned int);
using PfnCuStreamSynchronize = CUresult(CUDAAPI*)(CUstream);
using PfnCuStreamDestroy = CUresult(CUDAAPI*)(CUstream);

struct Driver {
  HMODULE mod = nullptr;
  PfnCuInit Init = nullptr;
  PfnCuGetErrorName ErrName = nullptr;
  PfnCuGetErrorString ErrStr = nullptr;
  PfnCuDeviceGet DeviceGet = nullptr;
  PfnCuCtxCreate CtxCreate = nullptr;
  PfnCuCtxDestroy CtxDestroy = nullptr;
  PfnCuMemAlloc MemAlloc = nullptr;
  PfnCuMemFree MemFree = nullptr;
  PfnCuMemHostRegister HostRegister = nullptr;
  PfnCuMemHostUnregister HostUnregister = nullptr;
  PfnCuMemHostGetDevicePointer HostGetDevPtr = nullptr;
  PfnCuMemcpyHtoDAsync H2DAsync = nullptr;
  PfnCuMemcpyDtoH DtoH = nullptr;
  PfnCuStreamCreate StreamCreate = nullptr;
  PfnCuStreamSynchronize StreamSync = nullptr;
  PfnCuStreamDestroy StreamDestroy = nullptr;

  template <typename T>
  T res(const char* n) { return reinterpret_cast<T>(GetProcAddress(mod, n)); }

  // Prefer the _v2 export; fall back to the plain name.
  template <typename T>
  T res2(const char* v2, const char* v1) {
    T p = reinterpret_cast<T>(GetProcAddress(mod, v2));
    return p ? p : reinterpret_cast<T>(GetProcAddress(mod, v1));
  }

  std::string ename(CUresult e) {
    const char* t = nullptr;
    if (ErrName && ErrName(e, &t) == CUDA_SUCCESS && t) return t;
    return "CUresult_" + std::to_string(e);
  }
  std::string estr(CUresult e) {
    const char* t = nullptr;
    if (ErrStr && ErrStr(e, &t) == CUDA_SUCCESS && t) return t;
    return "code " + std::to_string(e);
  }

  bool load(std::string* err) {
    wchar_t sysdir[MAX_PATH]{};
    UINT n = GetSystemDirectoryW(sysdir, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) { *err = "GetSystemDirectoryW failed"; return false; }
    std::wstring path(sysdir, n);
    if (!path.empty() && path.back() != L'\\') path.push_back(L'\\');
    path += L"nvcuda.dll";
    mod = LoadLibraryW(path.c_str());
    if (!mod) { *err = "LoadLibraryW(System32\\nvcuda.dll) failed, win32=" + std::to_string(GetLastError()); return false; }

    Init = res<PfnCuInit>("cuInit");
    ErrName = res<PfnCuGetErrorName>("cuGetErrorName");
    ErrStr = res<PfnCuGetErrorString>("cuGetErrorString");
    DeviceGet = res<PfnCuDeviceGet>("cuDeviceGet");
    CtxCreate = res2<PfnCuCtxCreate>("cuCtxCreate_v2", "cuCtxCreate");
    CtxDestroy = res2<PfnCuCtxDestroy>("cuCtxDestroy_v2", "cuCtxDestroy");
    MemAlloc = res2<PfnCuMemAlloc>("cuMemAlloc_v2", "cuMemAlloc");
    MemFree = res2<PfnCuMemFree>("cuMemFree_v2", "cuMemFree");
    HostRegister = res2<PfnCuMemHostRegister>("cuMemHostRegister_v2", "cuMemHostRegister");
    HostUnregister = res<PfnCuMemHostUnregister>("cuMemHostUnregister");
    HostGetDevPtr = res2<PfnCuMemHostGetDevicePointer>("cuMemHostGetDevicePointer_v2", "cuMemHostGetDevicePointer");
    H2DAsync = res2<PfnCuMemcpyHtoDAsync>("cuMemcpyHtoDAsync_v2", "cuMemcpyHtoDAsync");
    DtoH = res2<PfnCuMemcpyDtoH>("cuMemcpyDtoH_v2", "cuMemcpyDtoH");
    StreamCreate = res<PfnCuStreamCreate>("cuStreamCreate");
    StreamSync = res<PfnCuStreamSynchronize>("cuStreamSynchronize");
    StreamDestroy = res2<PfnCuStreamDestroy>("cuStreamDestroy_v2", "cuStreamDestroy");

    std::vector<const char*> missing;
    auto need = [&](void* p, const char* nm) { if (!p) missing.push_back(nm); };
    need((void*)Init, "cuInit"); need((void*)DeviceGet, "cuDeviceGet");
    need((void*)CtxCreate, "cuCtxCreate"); need((void*)CtxDestroy, "cuCtxDestroy");
    need((void*)MemAlloc, "cuMemAlloc"); need((void*)MemFree, "cuMemFree");
    need((void*)HostRegister, "cuMemHostRegister"); need((void*)HostUnregister, "cuMemHostUnregister");
    need((void*)HostGetDevPtr, "cuMemHostGetDevicePointer");
    need((void*)H2DAsync, "cuMemcpyHtoDAsync"); need((void*)DtoH, "cuMemcpyDtoH");
    need((void*)StreamCreate, "cuStreamCreate"); need((void*)StreamSync, "cuStreamSynchronize");
    need((void*)StreamDestroy, "cuStreamDestroy");
    if (!missing.empty()) {
      std::string m = "nvcuda.dll missing symbols:";
      for (auto s : missing) { m += ' '; m += s; }
      *err = m; return false;
    }
    return true;
  }
};

std::uint64_t fnv1a(const void* data, std::uint64_t len) {
  const std::uint8_t* p = static_cast<const std::uint8_t*>(data);
  std::uint64_t h = 14695981039346656037ull;
  for (std::uint64_t i = 0; i < len; ++i) { h ^= p[i]; h *= 1099511628211ull; }
  return h;
}

// Create a temp file of `bytes` filled with a deterministic byte pattern.
std::wstring make_temp_file(std::uint64_t bytes, std::string* err) {
  wchar_t dir[MAX_PATH]{}; GetTempPathW(MAX_PATH, dir);
  wchar_t name[MAX_PATH]{}; GetTempFileNameW(dir, L"mvof", 0, name);
  HANDLE h = CreateFileW(name, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) { *err = "temp CreateFileW failed"; return {}; }
  std::vector<std::uint8_t> buf(1 * kMiB);
  for (std::uint64_t written = 0; written < bytes;) {
    for (std::size_t i = 0; i < buf.size(); ++i)
      buf[i] = static_cast<std::uint8_t>((written + i) * 2654435761ull >> 13);
    DWORD chunk = static_cast<DWORD>((bytes - written < buf.size()) ? (bytes - written) : buf.size());
    DWORD wr = 0;
    if (!WriteFile(h, buf.data(), chunk, &wr, nullptr) || wr != chunk) {
      CloseHandle(h); *err = "temp WriteFile failed"; return {};
    }
    written += wr;
  }
  CloseHandle(h);
  return name;
}

}  // namespace

int main(int argc, char** argv) {
  std::uint64_t range_mib = 512;
  std::wstring file_path;
  bool made_temp = false;

  if (argc >= 2) {
    int len = MultiByteToWideChar(CP_UTF8, 0, argv[1], -1, nullptr, 0);
    std::wstring w(len, 0);
    MultiByteToWideChar(CP_UTF8, 0, argv[1], -1, &w[0], len);
    if (!w.empty() && w.back() == L'\0') w.pop_back();
    file_path = w;
  }
  if (argc >= 3) range_mib = std::strtoull(argv[2], nullptr, 10);
  const std::uint64_t range_bytes = range_mib * kMiB;

  std::printf("== G4 MapViewOfFile + cuMemHostRegister probe ==\n");
  std::printf("range = %llu MiB\n", (unsigned long long)range_mib);

  std::string err;
  if (file_path.empty()) {
    file_path = make_temp_file(range_bytes + 64 * kMiB, &err);
    if (file_path.empty()) { std::printf("FATAL: %s\n", err.c_str()); return 2; }
    made_temp = true;
    std::wprintf(L"created temp file: %ls\n", file_path.c_str());
  } else {
    std::wprintf(L"mapping existing file (read-only, unmodified): %ls\n", file_path.c_str());
  }

  auto cleanup_temp = [&]() { if (made_temp) DeleteFileW(file_path.c_str()); };

  // ---- Map the file read-only (identical to ds4-win os_mmap.c) ----
  HANDLE hFile = CreateFileW(file_path.c_str(), GENERIC_READ, FILE_SHARE_READ,
                             nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (hFile == INVALID_HANDLE_VALUE) { std::printf("FATAL: CreateFileW win32=%lu\n", GetLastError()); cleanup_temp(); return 2; }
  LARGE_INTEGER fsz{}; GetFileSizeEx(hFile, &fsz);
  const std::uint64_t file_size = (std::uint64_t)fsz.QuadPart;
  HANDLE hMap = CreateFileMappingW(hFile, nullptr, PAGE_READONLY, 0, 0, nullptr);
  if (!hMap) { std::printf("FATAL: CreateFileMappingW win32=%lu\n", GetLastError()); CloseHandle(hFile); cleanup_temp(); return 2; }
  const std::uint8_t* view = static_cast<const std::uint8_t*>(MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0));
  if (!view) { std::printf("FATAL: MapViewOfFile win32=%lu\n", GetLastError()); CloseHandle(hMap); CloseHandle(hFile); cleanup_temp(); return 2; }
  std::printf("mapped %.2f GiB, view=%p\n", (double)file_size / kGiB, (const void*)view);

  if (range_bytes + 32 * kMiB > file_size) { std::printf("FATAL: file smaller than range\n"); }

  // ---- Page-align a range from the file's interior (as ds4_cuda.cu does) ----
  SYSTEM_INFO si{}; GetSystemInfo(&si);
  const std::uint64_t page = si.dwPageSize ? si.dwPageSize : 4096;
  std::uint64_t off = 16 * kMiB;                       // skip GGUF-header-ish prefix
  if (off + range_bytes > file_size && file_size > range_bytes) off = 0;
  const std::uint8_t* host = view + off;
  const std::uintptr_t aligned = (std::uintptr_t)host & ~(std::uintptr_t)(page - 1);
  const std::uint64_t delta = (std::uintptr_t)host - aligned;
  const std::uint64_t reg_bytes = (delta + range_bytes + page - 1) & ~(std::uint64_t)(page - 1);
  void* reg_addr = (void*)aligned;

  // Touch the range so pages are resident before registering (WillNeed analogue).
  volatile std::uint8_t sink = 0;
  for (std::uint64_t i = 0; i < reg_bytes; i += page) sink ^= ((const std::uint8_t*)reg_addr)[i];
  (void)sink;

  // ---- Driver init ----
  Driver d;
  if (!d.load(&err)) { std::printf("FATAL: %s\n", err.c_str()); UnmapViewOfFile(view); CloseHandle(hMap); CloseHandle(hFile); cleanup_temp(); return 2; }
  CUresult r;
  if ((r = d.Init(0)) != CUDA_SUCCESS) { std::printf("FATAL cuInit: %s\n", d.estr(r).c_str()); return 2; }
  CUdevice dev = 0; d.DeviceGet(&dev, 0);
  CUcontext ctx = nullptr;
  if ((r = d.CtxCreate(&ctx, 0, dev)) != CUDA_SUCCESS) { std::printf("FATAL cuCtxCreate: %s\n", d.estr(r).c_str()); return 2; }

  int verdict = 1;  // default: FAIL
  std::uint64_t src_hash = fnv1a(reg_addr, range_bytes);

  // ---- THE DECISIVE CALL: try flag combinations, most-desirable first ----
  struct Attempt { const char* name; unsigned int flags; };
  const Attempt attempts[] = {
    {"READ_ONLY|DEVICEMAP", CU_MEMHOSTREGISTER_READ_ONLY | CU_MEMHOSTREGISTER_DEVICEMAP},
    {"DEVICEMAP",           CU_MEMHOSTREGISTER_DEVICEMAP},
    {"READ_ONLY",           CU_MEMHOSTREGISTER_READ_ONLY},
    {"PORTABLE",            CU_MEMHOSTREGISTER_PORTABLE},
    {"0(default)",          0u},
  };

  bool registered = false;
  const char* winning_flags = nullptr;
  for (const auto& a : attempts) {
    r = d.HostRegister(reg_addr, (size_t)reg_bytes, a.flags);
    std::printf("cuMemHostRegister(%-20s) -> %s (%s)\n", a.name,
                r == CUDA_SUCCESS ? "SUCCESS" : d.ename(r).c_str(),
                r == CUDA_SUCCESS ? "registered" : d.estr(r).c_str());
    if (r == CUDA_SUCCESS) { registered = true; winning_flags = a.name; break; }
  }

  if (registered) {
    // (a) device pointer for the mapped (zero-copy) path
    CUdeviceptr devmap = 0;
    r = d.HostGetDevPtr(&devmap, reg_addr, 0);
    std::printf("cuMemHostGetDevicePointer -> %s\n",
                r == CUDA_SUCCESS ? "SUCCESS (mapped device ptr available)" : d.ename(r).c_str());

    // (b) DMA bandwidth from the registered file-view host pointer -> VRAM
    CUdeviceptr dbuf = 0;
    if (d.MemAlloc(&dbuf, (size_t)range_bytes) == CUDA_SUCCESS) {
      CUstream s = nullptr; d.StreamCreate(&s, CU_STREAM_NON_BLOCKING);
      d.H2DAsync(dbuf, reg_addr, (size_t)range_bytes, s); d.StreamSync(s);  // warm
      const auto t0 = Clock::now();
      const int iters = 5;
      for (int i = 0; i < iters; ++i) { d.H2DAsync(dbuf, reg_addr, (size_t)range_bytes, s); }
      d.StreamSync(s);
      const double secs = std::chrono::duration<double>(Clock::now() - t0).count();
      const double gib = (double)range_bytes * iters / kGiB;
      std::printf("H2D from registered file-view: %.2f GiB in %.4f s = %.2f GiB/s\n", gib, secs, gib / secs);

      // (c) correctness: copy back and FNV-compare
      std::vector<std::uint8_t> back(range_bytes);
      if (d.DtoH(back.data(), dbuf, (size_t)range_bytes) == CUDA_SUCCESS) {
        std::uint64_t dst_hash = fnv1a(back.data(), range_bytes);
        std::printf("DMA correctness: src=%016llx dst=%016llx -> %s\n",
                    (unsigned long long)src_hash, (unsigned long long)dst_hash,
                    src_hash == dst_hash ? "MATCH" : "MISMATCH");
        if (src_hash == dst_hash) verdict = 0;  // PASS
      }
      d.StreamDestroy(s); d.MemFree(dbuf);
    }
    d.HostUnregister(reg_addr);
  }

  std::printf("\nG4_VERDICT: register=%s%s%s dma=%s\n",
              registered ? "SUCCESS" : "FAIL",
              registered ? " flags=" : "",
              registered ? winning_flags : "",
              verdict == 0 ? "MATCH" : (registered ? "unchecked" : "n/a"));
  std::printf("INTERPRETATION: %s\n",
              (verdict == 0)
                  ? "cudaHostRegister works on MapViewOfFile -> port register-mmap zero-copy 0050 directly."
                  : "register-mmap NOT usable on Win32 view -> use pinned-arena copy design (0051).");

  d.CtxDestroy(ctx);
  UnmapViewOfFile(view); CloseHandle(hMap); CloseHandle(hFile);
  cleanup_temp();
  return verdict;
}
