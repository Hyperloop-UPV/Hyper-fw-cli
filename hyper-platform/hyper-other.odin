#+build !windows
package hyper_platform

import "core:fmt"

EXECUTABLE_EXTENSION :: ""

init :: proc() -> bool
{
  return true
}

write_console_unicode :: proc(s: string) -> bool
{
  fmt.print(s)
  return true
}
