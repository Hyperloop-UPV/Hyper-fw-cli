#+build windows
package hyper_platform

import "core:sys/windows"
import "core:fmt"
import "core:strings"

EXECUTABLE_EXTENSION :: ".exe"

stdout_handle: windows.HANDLE
stderr_handle: windows.HANDLE

// https://stackoverflow.com/questions/1388871/how-do-i-get-a-list-of-available-serial-ports-in-win32
init :: proc() -> bool
{
  stdout_handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE)
  stderr_handle = windows.GetStdHandle(windows.STD_ERROR_HANDLE)

  return stdout_handle != nil && stderr_handle != nil
}

write_console_unicode :: proc(s: string) -> bool
{
  buf := windows.utf8_to_utf16_alloc(s, context.temp_allocator)
  ok := windows.WriteConsoleW(stdout_handle, &buf[0], u32(len(buf)), nil, nil)
  return windows.SUCCEEDED(ok)
}

open_uart :: proc(baud_rate: u32, name: string = "") -> bool
{
  name := name
  handle: windows.HANDLE = windows.INVALID_HANDLE_VALUE
  if name == "" || name == "auto" {
    for i in 0..<256 {
      name = fmt.tprintf(`\\.\COM%d`, i)
      buf := windows.utf8_to_wstring_alloc(name, context.temp_allocator)
      handle = windows.CreateFileW(buf, windows.GENERIC_READ, windows.FILE_SHARE_READ, nil, windows.OPEN_EXISTING, windows.FILE_ATTRIBUTE_READONLY, nil)
  
      if handle != windows.INVALID_HANDLE_VALUE {
        break
      }
    }

    if handle == windows.INVALID_HANDLE_VALUE {
      fmt.eprintfln("[windows] Could not find any open uart ports to choose automatically from")
      return false
    } else {
      fmt.printfln("[info] Port chosen: %s", name)
    }
  } else {
    buf := windows.utf8_to_wstring_alloc(name, context.temp_allocator)
    handle := windows.CreateFileW(buf, windows.GENERIC_READ, windows.FILE_SHARE_READ, nil, windows.OPEN_EXISTING, windows.FILE_ATTRIBUTE_READONLY, nil)
    if handle == windows.INVALID_HANDLE_VALUE {
      fmt.eprintfln("[windows] Could not open uart comm handle: %d", windows.GetLastError())
      return false
    }
  }
  defer windows.CloseHandle(handle)

  dcb: windows.DCB
  if !windows.SUCCEEDED(windows.GetCommState(handle, &dcb)) {
    fmt.eprintfln("[windows] Could not get DCB info for uart: %d", windows.GetLastError())
    return false
  }

  dcb.BaudRate = baud_rate;
  dcb.ByteSize = 8;
  if !windows.SUCCEEDED(windows.SetCommState(handle, &dcb)) {
    fmt.eprintfln("[windows] Could not set DCB info for uart: %d", windows.GetLastError())
    return false
  }

  timeouts: windows.COMMTIMEOUTS
  if !windows.SUCCEEDED(windows.GetCommTimeouts(handle, &timeouts)) {
    fmt.eprintfln("[windows] Could not get uart comm timeouts: %d", windows.GetLastError())
    return false
  }

  fmt.println("prev timeouts:", timeouts)
  // TODO: are these timeouts what we want?
  timeouts.ReadIntervalTimeout = 0;
  timeouts.ReadTotalTimeoutMultiplier = 0;
  timeouts.ReadTotalTimeoutConstant = 1;
  timeouts.WriteTotalTimeoutMultiplier = 0;
  timeouts.WriteTotalTimeoutConstant = 0;

  if !windows.SUCCEEDED(windows.SetCommTimeouts(handle, &timeouts)) {
    fmt.eprintfln("[windows] Could not set uart comm timeouts: %d", windows.GetLastError())
    return false
  }

  // Enable all events (temporary ?)
  event_mask: u32 = windows.EV_BREAK | windows.EV_CTS | windows.EV_DSR | windows.EV_ERR |
                    windows.EV_RING | windows.EV_RING | windows.EV_RLSD |
                    windows.EV_RXCHAR | windows.EV_RXFLAG | windows.EV_TXEMPTY
  if !windows.SUCCEEDED(windows.SetCommMask(handle, windows.EV_RXCHAR)) {
    fmt.eprintfln("[windows] Could not set uart comm mask: %d", windows.GetLastError())
    return false
  }

  fmt.println("[info] Starting communication event loop, use Ctrl+C to stop")

  readbuf: [4096]u8
  // NOTE: win32 readfile takes a 32 bit nº
  #assert(size_of(readbuf) < 0xFFFFFFFF)
  for {
    if !windows.SUCCEEDED(windows.WaitCommEvent(handle, &event_mask, nil)) {
      fmt.printfln("[warn] WaitCommEvent failed: %d", windows.GetLastError())
      continue
    }
    if event_mask == 0 {
      fmt.printfln("[warn] WaitCommEvent error: %d", windows.GetLastError())
    }

    fmt.printfln("[info] Comm event: %x", event_mask)
    if event_mask & windows.EV_RXCHAR != 0 {
      bytes_read: u32 = size_of(readbuf)
      for bytes_read == size_of(readbuf) {
        ok := windows.SUCCEEDED(windows.ReadFile(handle, &readbuf[0], size_of(readbuf), &bytes_read, nil))
        fmt.printfln("%s", string(readbuf[:bytes_read]))
      }
    }
  }

  return true
}
