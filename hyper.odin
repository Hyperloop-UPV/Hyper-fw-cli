#+vet style
#+vet unused
#+vet unused-variables
#+vet unused-imports
#+vet shadowing
package hyper

import "core:os"
import "core:fmt"
import "core:mem"
import "core:time"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:reflect"
import "core:terminal"
import "core:text/regex"
import "core:unicode/utf8"
import "core:terminal/ansi"

import platform "hyper-platform"
import cmdline "hyper-cmdline"

HYPER_VERSION_MAJOR :: "0"
HYPER_VERSION_MINOR :: "2"
HYPER_VERSION_PATCH :: "2"

HYPER_VERSION :: HYPER_VERSION_MAJOR + "." + HYPER_VERSION_MINOR + "." + HYPER_VERSION_PATCH

REPO_ROOT: string
TOOLS_DIR: string
STLIB_ROOT: string
BUILD_EXAMPLE_SCRIPT: string
PREFLASH_CHECK_SCRIPT: string
INIT_SCRIPT: string
STLIB_BUILD_SCRIPT: string
STLIB_SIM_TESTS_SCRIPT: string
HARD_FAULT_ANALYSIS_SCRIPT: string
LATEST_ELF: string

DEFAULT_PRESET: string
DEFAULT_FLASH_METHOD: cmdline.Hyper_FlashMethod
DEFAULT_UART_TOOL: cmdline.Hyper_UartTool
DEFAULT_UART_PORT: string
DEFAULT_UART_BAUD: int
DEFAULT_REQUIRED_CLT_VERSION: string
DEFAULT_CLT_ROOT: string
DEFAULT_CLT_INSTALLER: string
DEFAULT_CLT_DOWNLOAD_URL: string
DEFAULT_UV_VERSION: string

COLOR_ENABLED: bool

CLT_PRODUCT_PAGE :: "https://www.st.com/en/development-tools/stm32cubeclt.html"
CLT_RELEASE_NOTE :: "https://www.st.com/resource/en/release_note/rn0132-stm32cube-commandline-toolset-release-v1210-stmicroelectronics.pdf"
UV_INSTALL_PAGE :: "https://docs.astral.sh/uv/getting-started/installation/"

HELP_BANNER_BLOCKS := []string {"",
`
██╗  ██╗██╗   ██╗██████╗ ███████╗██████╗ ██╗      ██████╗  ██████╗ ██████╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗██╔═══██╗██╔══██╗
███████║ ╚████╔╝ ██████╔╝█████╗  ██████╔╝██║     ██║   ██║██║   ██║██████╔╝
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══╝  ██╔══██╗██║     ██║   ██║██║   ██║██╔═══╝
██║  ██║   ██║   ██║     ███████╗██║  ██║███████╗╚██████╔╝╚██████╔╝██║
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝  ╚═════╝ ╚═╝
`,
  "",
`
                                   ▅█╖
██╗   ██╗██████╗ ██╗   ██╗         ██║
██║   ██║██╔══██╗██║   ██║     ▅█╗ ██║
██║   ██║██████╔╝██║   ██║     ██████║   ▅▅▅╖
██║   ██║██╔═══╝ ╚██╗ ██╔╝     ▀█╔═██║ ▅██▀╔╝
╚██████╔╝██║      ╚████╔╝       ╘╝ █▀▅██▀╔╝
 ╚═════╝ ╚═╝       ╚═══╝           ▅██▀╔╝
                                   █▀╔╝
                                   ╘╝
`,
  "",
  "Hyper © 2026 by HyperloopUPV Firmware subsystem under CC By 4.0",
  "",
  "Build • Flash • UART • Diagnostics • ST-LIB",
}
HELP_BANNER_BUILDER: strings.Builder
HELP_BANNER: string
HELP_BANNER_WIDTH :: 82
SERIAL_PATTERNS : []string : {
  "/dev/serial/by-id/*",
  "/dev/cu.usbmodem*",
  "/dev/cu.usbserial*",
  "/dev/cu.wchusbserial*",
  "/dev/ttyACM*",
  "/dev/ttyUSB*",
  "/dev/tty.usbmodem*",
  "/dev/tty.usbserial*",
  "/dev/tty.wchusbserial*",
}

AVAILABLE_DOWNLOADER: enum {
  none = 0,
  curl,
  wget,
}

AVAILABLE_UNZIPPER: bit_set[enum {
  none = 0,
  unzip,
  tar,
}]

getenv :: proc(var: ^string, name: string, default: string = "", allocator := context.allocator) {
  var^ = os.get_env(name, allocator)
  if var^ == "" {
    var^ = default
  }
}

command_path :: proc(name: string, allocator := context.allocator) -> string
{
  if os.is_file(name) {
    info, err := os.stat(name, context.temp_allocator)
    if err == nil && os.Permission_Flag.Execute_User in info.mode {
      return name
    }
  }

  path_env := os.get_env("PATH", context.temp_allocator)
  if path_env == "" {
    return ""
  }

  sep: [1]u8 = {os.Path_List_Separator}
  path_split_char := string(sep[:])
  for dir in strings.split_iterator(&path_env, path_split_char) {
    if dir == "" {
      continue
    }

    path, _ := os.join_path({dir, name}, context.temp_allocator)
    when ODIN_OS == .Windows {
      extensions := []string{"", "exe", "bat", "cmd", "com"}
      for ext in extensions {
        full_path_ext, _ := os.join_filename(path, ext, context.temp_allocator)
        if os.is_file(full_path_ext) {
          return strings.clone(full_path_ext, allocator)
        }
      }
    } else {
      if os.is_file(path) {
        info, err := os.stat(path, context.temp_allocator)
        if err == nil && os.Permission_Flag.Execute_User in info.mode {
          return strings.clone(path, allocator)
        }
      }
    }
  }

  return strings.clone("", allocator)
}

setup_globals :: proc()
{
  setup_path :: proc(var: ^string, paths: []string) {
    os_err: os.Error
    
    var^, os_err = os.join_path(paths, context.allocator)
    fmt.assertf(os_err == nil, "Could not join %v path: %v", paths, os_err)
  }

  ok: bool
  os_err: os.Error
  REPO_ROOT, os_err = os.get_working_directory(context.allocator)
  fmt.assertf(os_err == nil, "Could not get executable directory: %v", os_err)

  setup_path(&TOOLS_DIR, {REPO_ROOT, "tools"})
  setup_path(&STLIB_ROOT, {REPO_ROOT, "deps", "ST-LIB"})
  setup_path(&BUILD_EXAMPLE_SCRIPT, {TOOLS_DIR, "build-example.sh"})
  setup_path(&PREFLASH_CHECK_SCRIPT, {TOOLS_DIR, "preflash_check.py"})
  setup_path(&INIT_SCRIPT, {TOOLS_DIR, "init.sh"})
  setup_path(&STLIB_BUILD_SCRIPT, {STLIB_ROOT, "tools", "build.py"})
  setup_path(&STLIB_SIM_TESTS_SCRIPT, {STLIB_ROOT, "tools", "run_sim_tests.sh"})
  setup_path(&HARD_FAULT_ANALYSIS_SCRIPT, {TOOLS_DIR, "hard_fault_analysis.py"})
  setup_path(&LATEST_ELF, {REPO_ROOT, "out", "build", "latest.elf"})

  getenv(&DEFAULT_PRESET, "HYPER_DEFAULT_PRESET", "nucleo-debug")
  flash_method_str: string
  getenv(&flash_method_str, "HYPER_FLASH_METHOD", "auto")
  DEFAULT_FLASH_METHOD, ok = reflect.enum_from_name(cmdline.Hyper_FlashMethod, flash_method_str)
  if !ok {
    fmt.eprintfln("Invalid Flash method for HYPER_FLASH_METHOD env.\n" + 
                  "Possible values are: %v", reflect.enum_field_names(cmdline.Hyper_FlashMethod))
    os.exit(2)
  }

  uart_tool_str: string
  getenv(&uart_tool_str, "HYPER_UART_TOOL", "auto")
  DEFAULT_UART_TOOL, ok = reflect.enum_from_name(cmdline.Hyper_UartTool, uart_tool_str)
  if !ok {
    fmt.eprintfln("Invalid Uart tool for HYPER_UART_TOOL env.\n" +
                  "Possible values are: %v", reflect.enum_field_names(cmdline.Hyper_UartTool))
    os.exit(2)
  }

  getenv(&DEFAULT_UART_PORT, "HYPER_UART_PORT")

  {
    baud: string
    getenv(&baud, "HYPER_UART_BAUD", "115200")
    DEFAULT_UART_BAUD, ok = strconv.parse_int(baud)
    fmt.assertf(ok, "Invalid HYPER_UART_BAUD, expected an integer")
  }

  getenv(&DEFAULT_REQUIRED_CLT_VERSION, "HYPER_REQUIRED_STM32_CLT_VERSION", "1.21.0")
  getenv(&DEFAULT_CLT_ROOT, "HYPER_STM32CLT_ROOT")
  if DEFAULT_CLT_ROOT == "" {
    getenv(&DEFAULT_CLT_ROOT, "STM32_CLT_ROOT")
  }
  getenv(&DEFAULT_CLT_INSTALLER, "HYPER_STM32CLT_INSTALLER")
  getenv(&DEFAULT_CLT_DOWNLOAD_URL, "HYPER_STM32CLT_DOWNLOAD_URL")
  getenv(&DEFAULT_UV_VERSION, "HYPER_UV_VERSION")
  COLOR_ENABLED = terminal.color_depth != .None

  strings.write_string(&HELP_BANNER_BUILDER, "╔")
  for i := 0; i < HELP_BANNER_WIDTH; i += 1 {
    strings.write_string(&HELP_BANNER_BUILDER, "═")
  }
  strings.write_string(&HELP_BANNER_BUILDER, "╗\n")

  buf: [HELP_BANNER_WIDTH]u8
  mem.set(&buf[0], ' ', HELP_BANNER_WIDTH)

  for block in HELP_BANNER_BLOCKS {
    max_width := 0
    trimmed := strings.trim(block, "\n\r")
    lines := strings.split_lines(trimmed, context.temp_allocator) or_continue
    for line in lines {
      _, _, w := utf8.grapheme_count(line)
      if w > max_width { max_width = w }
    }

    rem := HELP_BANNER_WIDTH - max_width
    left := rem / 2
    base_right := left
    if left + base_right + max_width < HELP_BANNER_WIDTH {
      base_right += 1
    }

    for line in lines {
      _, _, w := utf8.grapheme_count(line)
      right := base_right + (max_width - w)
      strings.write_string(&HELP_BANNER_BUILDER, "║")
      strings.write_bytes(&HELP_BANNER_BUILDER, buf[:left])
      strings.write_string(&HELP_BANNER_BUILDER, line)
      strings.write_bytes(&HELP_BANNER_BUILDER, buf[:right])
      strings.write_string(&HELP_BANNER_BUILDER, "║\n")
    }
  }
  strings.write_string(&HELP_BANNER_BUILDER, "╚")
  for i := 0; i < HELP_BANNER_WIDTH; i += 1 {
    strings.write_string(&HELP_BANNER_BUILDER, "═")
  }
  strings.write_string(&HELP_BANNER_BUILDER, "╝")

  HELP_BANNER = strings.to_string(HELP_BANNER_BUILDER)

  if command_path("curl", context.temp_allocator) != "" {
    AVAILABLE_DOWNLOADER = .curl
  } else if command_path("wget", context.temp_allocator) != "" {
    AVAILABLE_DOWNLOADER = .wget
  } else {
    AVAILABLE_DOWNLOADER = .none
    print_note("No available downloader, you might need to install curl or wget for some commands", .Warn)
  }

  if command_path("unzip", context.temp_allocator) != "" {
    AVAILABLE_UNZIPPER |= { .unzip }
  }
  if command_path("tar", context.temp_allocator) != "" {
    AVAILABLE_UNZIPPER |= { .tar }
  }
  
  if .unzip not_in AVAILABLE_UNZIPPER && .tar not_in AVAILABLE_UNZIPPER {
    AVAILABLE_UNZIPPER = { .none }
    print_note("No available program to unzip files, you might need to install unzip or tar", .Warn)
  }
}

free_all_globals :: proc()
{
  delete(TOOLS_DIR)
  delete(STLIB_ROOT)
  delete(BUILD_EXAMPLE_SCRIPT)
  delete(PREFLASH_CHECK_SCRIPT)
  delete(INIT_SCRIPT)
  delete(STLIB_BUILD_SCRIPT)
  delete(STLIB_SIM_TESTS_SCRIPT)
  delete(HARD_FAULT_ANALYSIS_SCRIPT)
  delete(LATEST_ELF)
  delete(REPO_ROOT)
  strings.builder_destroy(&HELP_BANNER_BUILDER)
}

ToolStatus :: struct {
  path: string,
  version_line: string,
  clt_version: string,
}

/* strip ansi escape sequences */
strip_ansi :: proc(text: string, allocator := context.temp_allocator) -> string
{
  // return re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
  if len(text) == 0 {
    return text
  }

  builder := strings.builder_make(context.temp_allocator)

  for i := 0; i < len(text); {
    if text[i] == 0x1B {
      if i + 1 < len(text) && text[i + 1] == '[' {
        i += 2

        for i < len(text) {
          c := text[i]
          if (c >= '0' && c <= '9') || c == ';' {
            i += 1
          } else {
            break
          }
        }

        if i < len(text) {
          c := text[i]
          if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') {
            i += 1
          }
        }
        continue
      }      
    }

    // Not an ANSI escape sequence, copy
    strings.write_byte(&builder, text[i])
    i += 1
  }

  return strings.clone(strings.to_string(builder), allocator)
}

read_command_first_line :: proc(cmd: []string, preferred_pattern: string = "", allocator := context.allocator) -> string
{
  desc := os.Process_Desc { command = cmd }
  _, stdout, stderr, err := os.process_exec(desc, context.temp_allocator)
  if err != nil {
    fmt.eprintfln("Could not run process %v: %v", cmd, err)
    return strings.clone("", allocator)
  }

  cleaned_lines := make([dynamic]string, context.temp_allocator)
  streams := [2][]u8{stdout, stderr}
  for stream in streams {
    str := string(stream)
    for line in strings.split_lines_iterator(&str) {
      stripped := strings.trim_space(strip_ansi(line))
      if len(stripped) != 0 {
        append(&cleaned_lines, stripped)
      }
    }
  }

  if preferred_pattern != "" {
    reg, reg_err := regex.create(preferred_pattern, {.Case_Insensitive})
    if reg_err != nil {
      fmt.eprintfln("Could not create regexpr '%s': %v", preferred_pattern, reg_err)
      return strings.clone("", allocator)
    }
    defer regex.destroy(reg)

    for line in cleaned_lines {
      capture, ok := regex.match(reg, line)
      defer regex.destroy_capture(capture)
      if ok {
        return line
      }
    }
  }

  if len(cleaned_lines) != 0 {
    return strings.clone(cleaned_lines[0], allocator)
  }
  return strings.clone("", allocator)
}

clt_root_candidates :: proc(version: string = "") -> [dynamic]string
{
  version_patterns := make([dynamic]string, context.temp_allocator)
  candidates := make([dynamic]string, context.allocator)
  defer delete(candidates)
  if DEFAULT_CLT_ROOT != "" {
    path, err := os.get_absolute_path(DEFAULT_CLT_ROOT, context.allocator)
    if err != nil {
      fmt.eprintfln("Could not get abs path of %s: %v", DEFAULT_CLT_ROOT, err)
      return candidates
    }
    append(&candidates, path)
  }

  if version != "" {
    append(&version_patterns, version)
  }

  for ver in version_patterns {
    suffixes: [4]string
    if ver != "" {
      suffixes[0] = fmt.tprintf("STM32CubeCLT_%s", ver)
      suffixes[1] = fmt.tprintf("STM32CubeCLT-%s", ver)
      when ODIN_OS == .Darwin || ODIN_OS == .Linux {
        suffixes[2] = fmt.tprintf("STM32CubeCLT_%s*", ver)
        suffixes[3] = fmt.tprintf("STM32CubeCLT-%s*", ver)
      }
    }

    when ODIN_OS == .Darwin || ODIN_OS == .Linux {
      home_dir, _ := os.user_home_dir(context.temp_allocator)
      base_dirs := []string{"/opt/ST", home_dir, "ST"}
      for base_dir in base_dirs {
        if !os.is_dir(base_dir) {
          continue
        }
        if ver != "" {
          for suffix in suffixes {
            path, _ := os.join_path({base_dir, suffix}, context.temp_allocator)
            paths, _ := os.glob(path, context.allocator)
            append(&candidates, ..paths[:])
          }
        } else {
          path, _ := os.join_path({base_dir, "STM32CubeCLT_*"}, context.temp_allocator)
          paths, _ := os.glob(path, context.allocator)
          append(&candidates, ..paths[:])

          path, _ = os.join_path({base_dir, "STM32CubeCLT-*"}, context.temp_allocator)
          paths, _ = os.glob(path, context.allocator)
          append(&candidates, ..paths[:])
        }
      }
    } else {
      program_files: string
      getenv(&program_files, "ProgramFiles", "C:\\Program Files", context.temp_allocator)
      stm_stmcube_path, _ := os.join_path({program_files, "STMicroelectronics", "STM32Cube"}, context.temp_allocator)
      stm_path, _ := os.join_path({program_files, "STMicroelectronics"}, context.temp_allocator)
      base_dirs := []string {
        stm_stmcube_path,
        stm_path,
        "C:\\ST",
      }
      for base_dir in base_dirs {
        if !os.is_dir(base_dir) {
          continue
        }
        underscorepath, dashpath: string
        if ver != "" {
          underscorepath = fmt.tprintf("STM32CubeCLT_%s*", ver)
          dashpath = fmt.tprintf("STM32CubeCLT-%s*", ver)
        } else {
          underscorepath = "STM32CubeCLT_*"
          dashpath = "STM32CubeCLT-*"
        }
        base_plus_underscore, _ := os.join_path({base_dir, underscorepath}, context.temp_allocator)
        paths, err := os.glob(base_plus_underscore, context.allocator)
        if err == nil {
          append(&candidates, ..paths[:])
        }

        base_plus_dashpath, _ := os.join_path({base_dir, dashpath}, context.temp_allocator)
        paths, err = os.glob(base_plus_dashpath, context.allocator)
        if err == nil {
          append(&candidates, ..paths[:])
        }
      }
    }
  }

  unique: [dynamic]string
  for candidate in candidates {
    resolved, err := os.clean_path(candidate, context.allocator)
    if err != nil || !os.exists(resolved) {
      continue
    }

    if slice.contains(unique[:], resolved) {
      continue
    }
    append(&unique, resolved)
  }

  return unique
}

parse_clt_version_from_path :: proc(path: string) -> string
{
  @static clt_version_regex: ^regex.Regular_Expression
  if len(path) == 0 {
    return ""
  }
  if clt_version_regex == nil {
    @static reg: regex.Regular_Expression
    reg_err: regex.Error
    reg, reg_err = regex.create(`STM32CubeCLT[_-](\d+\.\d+\.\d+)`, {.Case_Insensitive})
    if reg_err != nil {
      fmt.eprintfln("Could not create regex for clt version: %v", reg_err)
      return ""
    }
    clt_version_regex = &reg
  }
  capture, ok := regex.match_and_allocate_capture(clt_version_regex^, path)
  defer regex.destroy_capture(capture)
  if ok {
    return capture.groups[1] if len(capture.groups) >= 2 else capture.groups[0]
  }
  return ""
}

inspect_tool :: proc(name: string, version_args: []string, version_pattern: string) -> ToolStatus
{
  path := command_path(name)
  version_line := ""
  if len(path) != 0 && len(version_args) != 0 {
    cmd := make([dynamic]string, context.temp_allocator)
    append(&cmd, path)
    append(&cmd, ..version_args[:])
    version_line = read_command_first_line(cmd[:], version_pattern)
  }

  return ToolStatus{
    path = path,
    version_line = version_line,
    clt_version = parse_clt_version_from_path(path),
  }
}

infer_clt_root_from_tool :: proc(path: string, allocator := context.allocator) -> string
{
  @static clt_root_infer_regex: ^regex.Regular_Expression
  if len(path) == 0 {
    return ""
  }
  if clt_root_infer_regex == nil {
    @static reg: regex.Regular_Expression
    reg_err: regex.Error
    reg, reg_err = regex.create(`STM32CubeCLT[_-]\d+\.\d+\.\d+`, {.Case_Insensitive})
    if reg_err != nil {
      fmt.eprintfln("Could not create regex for clt root infer: %v", reg_err)
      return strings.clone("", allocator)
    }
    clt_root_infer_regex = &reg
  }

  resolved, _ := os.get_absolute_path(path, context.temp_allocator)
  parent := os.dir(resolved)
  capture, ok := regex.match_and_allocate_capture(clt_root_infer_regex^, path)
  defer regex.destroy_capture(capture)
  if ok {
    return strings.clone(parent, allocator)
  }
  return strings.clone("", allocator)
}

clt_tool_status :: proc(relpath: string, version_args: []string, version_pattern: string) -> ToolStatus
{
  root_candidates := clt_root_candidates(DEFAULT_REQUIRED_CLT_VERSION)
  defer delete(root_candidates)

  for root in root_candidates {
    tool_path, err := os.join_path({root, relpath}, context.allocator)
    if err != nil {
      fmt.eprintfln("Could not join path: {%s, %s}: %v", root, relpath, err)
      return ToolStatus{}
    }
    if os.is_file(tool_path) {
      cmd := make([dynamic]string, context.temp_allocator)
      append(&cmd, tool_path)
      append(&cmd, ..version_args[:])
      version_line := read_command_first_line(cmd[:], version_pattern)
      return ToolStatus{
        path = tool_path,
        version_line = version_line,
        clt_version = parse_clt_version_from_path(root),
      }
    }
  }

  path_status := inspect_tool(relpath, version_args, version_pattern)
  inferred_root := infer_clt_root_from_tool(path_status.path)
  if len(inferred_root) != 0 {
    path_status.clt_version = parse_clt_version_from_path(inferred_root)
  }
  return path_status
}

inspect_clt :: proc() -> (ToolStatus, ToolStatus, string)
{
  arm_gcc := clt_tool_status("GNU-tools-for-STM32/bin/arm-none-eabi-gcc", {"--version"}, "arm-none-eabi-gcc")
  programmer := clt_tool_status("STM32CubeProgrammer/bin/STM32_Programmer_CLI", {"--version"}, "version")
  clt_version := arm_gcc.clt_version
  if clt_version == "" {
    clt_version = programmer.clt_version
  }

  if clt_version == "" {
    root_candidates := clt_root_candidates()
    defer delete(root_candidates)
    for root in root_candidates {
      clt_version = parse_clt_version_from_path(root)
      if clt_version != "" {
        clt_version = strings.clone(clt_version, context.allocator)
        break
      }
    }
  }

  return arm_gcc, programmer, clt_version
}

print_detail :: proc(label, value: string, flush := true)
{
  if !COLOR_ENABLED {
    fmt.printfln("  %s: %s", label, value, flush = flush)
  } else {
    fmt.printfln("  " + ansi.CSI + ansi.FAINT + ansi.SGR + "%s:" + ansi.CSI + ansi.RESET + ansi.SGR + " %s",
      label, value, flush = flush)
  }
}

print_action :: proc(title: string, details: [][2]string)
{
  buf: [64]u8
  dashcount := min(len(title), len(buf))
  mem.set(&buf[0], '-', dashcount)
  if !COLOR_ENABLED {
    fmt.printfln("\n%s\n%.*s", title, dashcount, &buf[0])
  } else {
    fmt.printfln("\n" + ansi.CSI + ansi.FG_MAGENTA + ";" + ansi.BOLD + ansi.SGR + "%s" + ansi.CSI + ansi.RESET + ansi.SGR, title)
    fmt.printfln(ansi.CSI + ansi.FAINT + ansi.SGR + "%s" + ansi.CSI + ansi.RESET + ansi.SGR, buf[:dashcount])
  }

  for lab_val in details {
    label, _ := strings.replace(lab_val[0], "-", " ", -1, context.temp_allocator)
    value := lab_val[1]
    print_detail(label, value)
  }
}

Hyper_Status :: enum {
  Ok,
  Wrong,
  Warn,
  Missing,
  Info,
}

status_tag :: proc(status: Hyper_Status) -> string
{
  if COLOR_ENABLED {
    switch status {
      case .Ok: return ansi.CSI + ansi.FG_GREEN + ";" + ansi.SGR + "[ok]" + ansi.CSI + ansi.RESET + ansi.SGR
      case .Wrong: return ansi.CSI + ansi.FG_RED + ";" + ansi.SGR + "[wrong]" + ansi.CSI + ansi.RESET + ansi.SGR
      case .Warn: return ansi.CSI + ansi.FG_YELLOW + ";" + ansi.SGR + "[warn]" + ansi.CSI + ansi.RESET + ansi.SGR
      case .Missing: return ansi.CSI + ansi.FG_YELLOW + ";" + ansi.SGR + "[missing]" + ansi.CSI + ansi.RESET + ansi.SGR
      case .Info: return ansi.CSI + ansi.FG_CYAN + ";" + ansi.SGR + "[info]" + ansi.CSI + ansi.RESET + ansi.SGR
    }
  } else {
    switch status {
      case .Ok: return "[ok]"
      case .Wrong: return "[wrong]"
      case .Warn: return "[warn]"
      case .Missing: return "[missing]"
      case .Info: return "[info]"
    }
  }
  return ""
}

print_note :: proc(message: string, status: Hyper_Status = .Info)
{
  fmt.printfln("  %s %s", status_tag(status), message)
}

installer_matches_version :: proc(path, version: string) -> bool
{
  lower := strings.to_lower(path, context.temp_allocator)
  if !strings.contains(lower, "stm32cubeclt") {
    return false
  }

  version_dash, _ := strings.replace(version, ".", "-", -1, context.temp_allocator)
  version_underscore, _ := strings.replace(version, ".", "_", -1, context.temp_allocator)
  installer_version_names := []string{
    version,
    version_dash,
    version_underscore,
  }

  for ver in installer_version_names {
    if strings.contains(lower, ver) {
      return true
    }
  }
  return false
}

get_clt_installer_candidates :: proc(version: string) -> [dynamic]string
{
  home_dir, os_err := os.user_home_dir(context.temp_allocator)
  if os_err != nil {
    fmt.eprintfln("Could not get user home dir: %v", os_err)
    return nil
  }
  cwd, _ := os.get_working_directory(context.temp_allocator)
  downloads_dir, _ := os.join_path({home_dir, "Downloads"}, context.temp_allocator)
  desktop_dir, _ := os.join_path({home_dir, "Desktop"}, context.temp_allocator)
  directories := []string{
    REPO_ROOT,
    cwd,
    downloads_dir,
    desktop_dir,
  }
  
  candidates: [dynamic]string
  seen := make([dynamic]string, context.temp_allocator)
  for dir in directories {
    resolved: string
    resolved, os_err = os.get_absolute_path(dir, context.temp_allocator)
    if os_err != nil || !os.is_dir(resolved) {
      continue
    }
    if slice.contains(seen[:], resolved) {
      continue
    } else {
      append(&seen, resolved)
    }

    f, open_err := os.open(resolved)
    if open_err != nil {
      fmt.eprintfln("Could not read %s directory: %v", resolved, open_err)
      continue
    }
    defer os.close(f)

    it := os.read_directory_iterator_create(f)
    defer os.read_directory_iterator_destroy(&it)

    for entry_info in os.read_directory_iterator(&it) {
      if path, err := os.read_directory_iterator_error(&it); err != nil {
        fmt.eprintfln("Could not read %s: %v", path, err)
        continue
      }

      if entry_info.type != .Regular {
        continue
      }

      if installer_matches_version(entry_info.fullpath, version) {
        append(&candidates, strings.clone(entry_info.fullpath, context.allocator))
      }
    }
  }

  sort_time_less :: proc(i, j: string) -> bool
  {
    time_i, err_i := os.modification_time_by_path(i)
    if err_i != nil {
      return false
    }

    time_j, err_j := os.modification_time_by_path(j)
    if err_j != nil {
      return true
    }

    return i64(time.diff(time_i, time_j)) < 0
  }

  slice.reverse_sort_by(candidates[:], sort_time_less)
  return candidates
}

print_command_context :: proc(cmd: []string, cwd: string)
{
  @static prev_dir: string = ""

  if !COLOR_ENABLED {
    fmt.printf("== Running ==\n" +
                 "$")
  } else {
    fmt.printf(ansi.CSI + ansi.FG_BLUE + ";" + ansi.BOLD + ansi.SGR + 
                 "== Running ==\n" + "$" + ansi.CSI + ansi.RESET + ansi.SGR)
  }

  if cwd != prev_dir {
    fmt.printfln(" %s %v", cwd, cmd)
    prev_dir = cwd
  } else {
    fmt.printfln(" %v", cmd)
  }
}

exec_command :: proc(cmd: []string, cwd: string = REPO_ROOT, env: []string = nil, wait: bool = true) -> (os.Process, os.Process_State)
{
  print_command_context(cmd, cwd)
  os.flush(os.stdout)
  environment := env
  if len(env) != 0 {
    new_env := make([dynamic]string, context.temp_allocator)
    cur_env, _ := os.environ(context.temp_allocator)
    append(&new_env, ..cur_env[:])
    append(&new_env, ..env[:])
    environment = new_env[:]
  }

  desc := os.Process_Desc {
    command = cmd,
    working_dir = cwd,
    env = environment,
    stdin = os.stdin,
    stdout = os.stdout,
    stderr = os.stderr,
  }
  process, err := os.process_start(desc)
  if err != nil {
    fmt.eprintfln("Could not start process %v: %v", cmd, err)
    return os.Process{}, os.Process_State{}
  }

  state: os.Process_State
  if wait {
    state, err = os.process_wait(process)
    if err != nil {
      fmt.eprintfln("Could not wait for process %v: %v", cmd, err)
    }
    return os.Process{}, state
  } else {
    return process, os.Process_State{}
  }
}

run_command :: #force_inline proc(cmd: []string, cwd: string = REPO_ROOT, env: []string = nil) -> os.Process_State
{
  _, state := exec_command(cmd, cwd, env, wait = true)
  return state
}

download_file :: proc(url, destination: string) -> bool
{
  status: os.Process_State
  when ODIN_OS == .Windows {
    status = run_command({
      "powershell", "-NoProfile", "-Command",
      fmt.tprintf("Invoke-WebRequest -Uri %s -OutFile %s", url, destination),
    })
  } else {
    switch AVAILABLE_DOWNLOADER {
      case .curl: {
        status = run_command({"curl", "-LsSf", url, "-o", destination})
      }

      case .wget: {
        status = run_command({"wget", "-q", "-O", destination, url})
      }

      case .none: fallthrough
      case: {
        fmt.eprintln("No available downloaders, please install curl or wget")
        return false
      }
    }
  }
  if status.exit_code != 0 {
    fmt.eprintfln("Failed to download %s. Exit code: %d", url, status.exit_code)
  }
  return status.exit_code == 0
}

maybe_download_clt_installer :: proc(version: string) -> string
{
  if DEFAULT_CLT_DOWNLOAD_URL == "" {
    return ""
  }

  suffix := os.ext(DEFAULT_CLT_DOWNLOAD_URL)
  if suffix == "" {
    suffix = ".bin"
  }
  download_dir, _ := os.join_path({REPO_ROOT, "out", "downloads"}, context.temp_allocator)
  err := os.make_directory_all(download_dir)
  if err != nil {
    fmt.eprintfln("Could not make clt installer directory: %v", err)
    return ""
  }

  destination, _ := os.join_path({download_dir, fmt.tprintf("stm32cubeclt-%s%s", version, suffix)}, context.temp_allocator)
  print_detail("download url", DEFAULT_CLT_DOWNLOAD_URL)
  print_detail("download dest", destination)

  if !download_file(DEFAULT_CLT_DOWNLOAD_URL, destination) {
    return ""
  }
  return destination
}

extract_all_from_zip :: proc(filename, dest: string) -> bool
{
  status: os.Process_State
  when ODIN_OS == .Windows {
    status = run_command({"powershell", "Expand-Archive", "-LiteralPath", filename, "-DestinationPath", dest})
  } else {
    if .tar in AVAILABLE_UNZIPPER {
      status = run_command({"tar", "-xvf", filename, "-C", dest})
    } else if .unzip in AVAILABLE_UNZIPPER {
      status = run_command({"unzip", filename, "-d", dest})
    } else {
      fmt.eprintln("No available unzip programs, please install unzip or tar")
      return false
    }
  }
  if status.exit_code != 0 {
    fmt.eprintfln("Failed to extract from zip %s. Exit code: %d", filename, status.exit_code)
  }
  return status.exit_code == 0
}

extract_all_from_tar :: proc(filename, dest: string) -> bool
{
  status: os.Process_State
  if .tar in AVAILABLE_UNZIPPER {
    status = run_command({"tar", "-xvf", filename, "-C", dest})
  } else {
    fmt.eprintln("No available .tar.gz/.tgz extraction programs, please install tar")
    return false
  }
  if status.exit_code != 0 {
    fmt.eprintfln("Failed to extract from tgz %s. Exit code: %d", filename, status.exit_code)
  }
  return status.exit_code == 0
}

prepare_clt_installers :: proc(installer: string) -> (installers: [dynamic]string, cleanup_dir: string)
{
  file_less_than_cubeclt :: proc(i, j: string) -> bool {
    i_lower, _ := strings.to_lower(i, context.temp_allocator)
    j_lower, _ := strings.to_lower(j, context.temp_allocator)

    stm_i := strings.contains(i_lower, "stm32cubeclt")
    stm_j := strings.contains(i_lower, "stm32cubeclt")

    if stm_i != stm_j {
      return stm_i
    }

    return i_lower < j_lower
  }

  when ODIN_OS == .Darwin {
    ext_lower, _ := strings.to_lower(os.ext(installer), context.temp_allocator)
    if ext_lower == ".pkg" {
      append(&installers, installer)
      return
    }

    if (!strings.ends_with(installer, ".tar.gx") && !strings.ends_with(installer, ".tgz") &&
        ext_lower != ".zip")
    {
      fmt.eprintfln("Unsupported macOS STM32CubeCLT installer: %s", installer)
      return
    }

    cleanup_dir, _ = os.make_directory_temp(".", "hyper-clt-macos-", context.temp_allocator)
    if ext_lower == ".zip" {
      if !extract_all_from_zip(installer, cleanup_dir) {
        fmt.eprintfln("Could not unzip %s. Terminating program...", installer)
        return
      }

      pkg_paths, _ := os.join_path({cleanup_dir, "*.pkg"}, context.temp_allocator)
      pkgs, _ := os.glob(pkg_paths, context.temp_allocator)
      if len(pkgs) == 0 {
        pkg_paths, _ = os.join_path({cleanup_dir, "*"}, context.temp_allocator)
        nested_archives := make([dynamic]string, context.temp_allocator)
        targz_paths, _ := os.glob(fmt.tprintf("%s.tar.gz", pkg_paths), context.temp_allocator)
        tgz_paths, _ := os.glob(fmt.tprintf("%s.tar.gz", pkg_paths), context.temp_allocator)
        append(&nested_archives, ..targz_paths[:])
        append(&nested_archives, ..tgz_paths[:])

        if len(nested_archives) == 0 {
          fmt.eprintfln("No .pkg, .tar.gz or .tgz files found in %s", installer)
          return
        }

        slice.sort_by(nested_archives[:], file_less_than_cubeclt)

        for archive in nested_archives {
          if !extract_all_from_tar(archive, cleanup_dir) {
            fmt.eprintfln("Could not extract %s to %s", archive, cleanup_dir)
            return
          }
        }

        pkgs, _ = os.glob(pkg_paths, context.temp_allocator)
      }

      if len(pkgs) == 0 {
        fmt.eprintfln("No .pkg files found in %s", installer)
        return nil, ""
      }

      slice.sort_by(pkgs[:], proc(i, j: string) -> bool {
        i_lower, _ := strings.to_lower(i, context.temp_allocator)
        j_lower, _ := strings.to_lower(j, context.temp_allocator)

        stm_i := strings.contains(i_lower, "st-link")
        stm_j := strings.contains(i_lower, "st-link")

        if stm_i != stm_j {
          return stm_i
        }

        return i_lower < j_lower
      })

      for p in pkgs {
        append(&installers, strings.clone(p, context.allocator))
      }
      return
    }
  }

  when ODIN_OS == .Windows {
    ext_lower, _ := strings.to_lower(os.ext(installer), context.temp_allocator)
    if ext_lower == ".exe" {
      append(&installers, installer)
      return
    }
    if ext_lower != ".zip" {
      fmt.eprintfln("Unsupported Windows STM32CubeCLT installer %s", installer)
      return nil, ""
    }

    tmpdir, _ := os.make_directory_temp(".", "hyper-clt-windows-", context.temp_allocator)
    if !extract_all_from_zip(installer, tmpdir) {
      fmt.eprintfln("Could not unzip %s. Terminating program...", installer)
      return nil, ""
    }

    executable_paths, _ := os.join_path({tmpdir, "*.exe"}, context.temp_allocator)
    executables, _ := os.glob(executable_paths, context.allocator)
    if len(executables) == 0 {
      fmt.eprintfln("No executable files found in %s", installer)
    }
    slice.sort_by(executables, file_less_than_cubeclt)
    
    append(&installers, ..executables[:])
    cleanup_dir = tmpdir
    return
  }

  when ODIN_OS == .Linux {
    if !strings.ends_with(installer, ".sh") {
      fmt.eprintfln("Unsupported Linux STM32CubeCLT installer %s", installer)
      return
    }

    append(&installers, installer)
    return
  }

  return
}

run_clt_installer :: proc(installer: string) -> bool
{
  status: os.Process_State
  when ODIN_OS == .Darwin {
    status = run_command({"sudo", "installer", "-pkg", installer, "-target", "/"})
  } else when ODIN_OS == .Windows {
    status = run_command({installer})
  } else when ODIN_OS == .Linux {
    status = run_command({"sudo", "sh", installer})
  }
  return status.exit_code == 0
}

ensure_required_clt :: proc() -> bool
{
  arm_gcc, programmer, clt_version := inspect_clt()
  if clt_version == DEFAULT_REQUIRED_CLT_VERSION {
    print_action("STM32CubeCLT", {{"version", DEFAULT_REQUIRED_CLT_VERSION}, {"status", "ready"}})
    if arm_gcc.path != "" {
      print_detail("arm gcc", arm_gcc.path)
    }
    if programmer.path != "" {
      print_detail("programmer", programmer.path)
    }
    print_note("required STM32CubeCLT is already installed", .Ok)
    return true
  }

  print_action("STMCubeCLT", {
    {"expected", DEFAULT_REQUIRED_CLT_VERSION},
    {"detected", clt_version if clt_version != "" else "missing"},
    {"host", ODIN_OS_STRING},
  })

  installer: string
  if DEFAULT_CLT_INSTALLER != "" {
    installer, _ = os.get_absolute_path(DEFAULT_CLT_INSTALLER, context.allocator)
  } else {
    candidates := get_clt_installer_candidates(DEFAULT_REQUIRED_CLT_VERSION)
    defer delete(candidates)
    if len(candidates) != 0 {
      installer = candidates[0]
    } else {
      installer = maybe_download_clt_installer(DEFAULT_REQUIRED_CLT_VERSION)
    }
  }

  if len(installer) == 0 {
    fmt.eprintfln(
      "STM32CubeCLT installer not found. Download the official installer for\n" +
      "%s from %s\n" +
      "(release note: %s) and place it in ~/Downloads,\n" +
      "or set HYPER_STM32CLT_INSTALLER to the installer path,\n" +
      "or set HYPER_STM32CLT_DOWNLOAD_URL to a direct installer URL.\n",
      DEFAULT_REQUIRED_CLT_VERSION, CLT_PRODUCT_PAGE, CLT_RELEASE_NOTE)
    return false
  }
  defer delete(installer)

  print_detail("installer", installer)
  installers, cleanup_dir := prepare_clt_installers(installer)
  fail := false
  for inst in installers {
    print_detail("install step", inst)
    if !run_clt_installer(inst) {
      fmt.eprintfln("Could not run install step %s correctly", inst)
      fail = true
    }
  }
  if cleanup_dir != "" { os.remove_all(cleanup_dir) }
  if fail { return false }

  _, _, installed_version := inspect_clt()
  if installed_version != DEFAULT_REQUIRED_CLT_VERSION {
    fmt.eprintfln("STM32CubeCLT installation completed but detected version is %s",
                  installed_version if installed_version != "" else "missing")
    return false
  }
  print_note(fmt.tprintf("STM32CubeCLT %s installed", DEFAULT_REQUIRED_CLT_VERSION), .Ok)
  return true
}

ensure_required_toolchain :: proc(require_cmake := true) -> bool
{
  check_path :: proc(path, tool: string, ignore := false) -> bool
  {
    if path == "" {
      if ignore {
        fmt.eprintfln("Missing %s from path. You might need it for other configurations.", tool)
      } else {
        fmt.eprintfln("Missing %s from path", tool)
        return false
      }
    }
    return true
  }

  ok := true
  armtools_search := []string{
    "arm-none-eabi-gdb",
    "arm-none-eabi-gcc",
    "arm-none-eabi-as",
    "arm-none-eabi-ld",
  }
  for tool in armtools_search {
    path := command_path(tool, context.temp_allocator)
    if !check_path(path, tool) {
      ok = false
    }
  }

  gccpath := command_path("gcc", context.temp_allocator)
  clangpath := command_path("clang", context.temp_allocator)
  if gccpath == "" && clangpath == "" {
    check_path("", "gcc or clang")
    ok = false
  }

  gitpath := command_path("git", context.temp_allocator)
  if !check_path(gitpath, "git") {
    ok = false
  }

  cmaketools_search := []string{
    "cmake",
    "ninja",
  }
  for tool in cmaketools_search {
    path := command_path(tool, context.temp_allocator)
    if !check_path(path, tool, !require_cmake) {
      ok = false
    }
  }

  return ok
}

known_uv_paths :: proc(allocator := context.allocator) -> []string
{
  home_dir, _ := os.user_home_dir(context.temp_allocator)
  local_path, _ := os.join_path({home_dir, ".local", "bin", "uv" + platform.EXECUTABLE_EXTENSION}, allocator)
  cargo_path, _ := os.join_path({home_dir, ".cargo", "bin", "uv" + platform.EXECUTABLE_EXTENSION}, allocator)

  paths := make([dynamic]string, 2, allocator = allocator)
  if os.is_file(local_path) {
    append(&paths, local_path)
  }
  if os.is_file(cargo_path) {
    append(&paths, cargo_path)
  }

  return paths[:]
}

uv_executable_path :: proc() -> string
{
  path := command_path("uv")
  if path != "" { return path }
  candidates := known_uv_paths(context.temp_allocator)
  if len(candidates) != 0 { return candidates[0] }
  return ""
}

uv_install_url :: proc() -> string
{
  if DEFAULT_UV_VERSION != "" {
    return fmt.tprintf("https://astral.sh/uv/%s/install.sh", DEFAULT_UV_VERSION)
  }
  return "https://astral.sh/uv/install.sh"
}

ensure_uv :: proc() -> string
{
  uv_path := uv_executable_path()
  if uv_path != "" {
    version_line := read_command_first_line({uv_path, "--version"})
    print_action("uv", {{"status", "ready"}})
    print_detail("binary", uv_path)
    if version_line != "" {
      print_detail("version", version_line)
    }
    print_note("uv is available", .Ok)
    return uv_path
  }

  print_action("uv", {
    {"status", "installing"},
    {"host", ODIN_OS_STRING},
  })

  when ODIN_OS == .Windows {
    cmd := []string{"powershell", "-ExecutionPolicy", "ByPass", "-c", "irm https://astral.sh/uv/install.ps1 | iex"}
    status := run_command(cmd)
    if status.exit_code != 0 {
      print_note("uv install failed", .Wrong)
      return ""
    } else {
      print_note("uv install succeeded", .Ok)
      print_note("please rerun the program from a new command prompt to use the new PATH", .Warn)
      os.exit(0)
    }
    return ""
  }

  install_url := uv_install_url()
  print_detail("source", install_url)

  tmpdir, _ := os.make_directory_temp(".", "hyper-uv-install-", context.temp_allocator)
  script_name := "install.sh"
  installer, _ := os.join_path({tmpdir, script_name}, context.temp_allocator)
  download_file(install_url, installer)
  state := run_command({"sh", installer}, env = {"UV_NO_MODIFY_PATH=1"})
  os.remove_all(tmpdir)
  if state.exit_code != 0 {
    fmt.eprintfln("Failed to install uv. Exit code: %d", state.exit_code)
    return ""
  }

  uv_path = uv_executable_path()
  if uv_path == "" {
    fmt.eprintfln("uv installation completed but the binary is still not visible. See %s", UV_INSTALL_PAGE)
    return ""
  }

  version_line := read_command_first_line({uv_path, "--version"})
  print_detail("binary", uv_path)
  if version_line != "" {
    print_detail("version", version_line)
  }
  print_note("uv installed", .Ok)
  return uv_path
}

virtual_python_path :: proc(virt_dir: string, allocator := context.temp_allocator) -> string
{
  when ODIN_OS == .Windows {
    path, _ := os.join_path({REPO_ROOT, virt_dir, "Scripts", "python.exe"}, context.temp_allocator)
    if os.exists(path) {
      return strings.clone(path, allocator)
    }
    path, _ = os.join_path({REPO_ROOT, virt_dir, "bin", "python.exe"}, context.temp_allocator)
    if os.exists(path) {
      return strings.clone(path, allocator)
    }
    fmt.eprintfln("Could not find virtual python path in {{%s, %s, Scripts|bin, python.exe}}", REPO_ROOT, virt_dir)
    return strings.clone("", allocator)
  } else {
    path, _ := os.join_path({REPO_ROOT, virt_dir, "bin", "python"}, allocator)
    return path
  }
}

setup_python_env_with_uv :: proc(uv_path: string)
{
  venv_path, _ := os.join_path({REPO_ROOT, "virtual"}, context.temp_allocator)
  requirements_path, _ := os.join_path({REPO_ROOT, "requirements.txt"}, context.temp_allocator)
  print_action("Python Env", {
    {"tool", "uv"},
    {"venv", venv_path},
  })
  python_path := virtual_python_path("virtual")
  if os.exists(python_path) {
    print_note("virtual environment already exists, skipping creation", .Info)
  } else {
    run_command({uv_path, "venv", venv_path})
    python_path = virtual_python_path("virtual")
  }
  run_command({uv_path, "pip", "install", "--python", python_path, "-r", requirements_path})
  print_note("python environment ready", .Ok)
}

ensure_file :: proc(path, label: string) -> bool
{
  if !os.is_file(path) {
    fmt.eprintfln("%s not found in path: %s", label, path)
    return false
  }
  return true
}

sanitize_path_fragment :: proc(name: string) -> string {
  builder := strings.builder_make(context.temp_allocator)
  for r in name {
    if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
      strings.write_rune(&builder, r)
    } else {
      strings.write_byte(&builder, '_')
    }
  }
  return strings.to_lower(strings.to_string(builder), context.allocator)
}

normalize_example_macro :: proc(input: string) -> string {
  lower := strings.to_lower(input, context.temp_allocator)
  if lower == "main" || lower == "default" {
      return "MAIN"
  }
  base := input
  if strings.has_prefix(lower, "example_") {
    base = input[len("example_"):]
  }
  underscored, _ := strings.replace_all(base, "-", "_", context.temp_allocator)
  normalized := strings.to_upper(underscored, context.temp_allocator)
  return strings.concatenate({"EXAMPLE_", normalized})
}

normalize_test_macro :: proc(input: string) -> string {
  lower := strings.to_lower(input, context.temp_allocator)
  // If it's a plain number, just wrap it
  if _, ok := strconv.parse_int(input); ok {
    return strings.concatenate({"TEST_", input})
  }
  base := input
  if strings.has_prefix(lower, "test_") {
    base = input[len("test_"):]
  }
  underscored, _ := strings.replace_all(base, "-", "_", context.temp_allocator)
  normalized := strings.to_upper(underscored, context.temp_allocator)
  return strings.concatenate({"TEST_", normalized})
}

collect_examples :: proc() -> (macros: [dynamic]string, file_map: map[string]string) {
  examples_dir, _ := os.join_path({REPO_ROOT, "Core", "Src", "Examples"}, context.temp_allocator)
  pattern, _ := os.join_path({examples_dir, "*.cpp"}, context.temp_allocator)
  files, err := os.glob(pattern, context.temp_allocator)
  if err != nil {
    return
  }

  macro_pattern := `EXAMPLE_[A-Z0-9_]+`
  file_map = make(map[string]string, context.allocator)

  for file in files {
    data, read_err := os.read_entire_file(file, context.temp_allocator)
    if read_err != nil {
      continue
    }
    text := string(data)

    it, iter_err := regex.create_iterator(text, macro_pattern, {})
    if iter_err != nil {
      fmt.eprintfln("Could not create iterator for %s: %v", file, iter_err)
      continue
    }
    defer regex.destroy_iterator(it)

    for {
      cap, _, ok := regex.match_iterator(&it)
      if !ok {
        break
      }
      macro := cap.groups[0]
      if _, exists := file_map[macro]; !exists {
        file_map[macro] = file
        append(&macros, macro)
      }
      regex.destroy_capture(cap)
    }
  }
  return
}

find_example_file :: proc(example_macro: string) -> (file_path: string, ok: bool) {
  macros, file_map := collect_examples()
  defer delete(macros)
  defer delete(file_map)
  path, exists := file_map[example_macro]
  return path, exists
}

collect_tests_for_file :: proc(file_path: string) -> [dynamic]string {
  if file_path == "" {
    return {}
  }
  data, read_err := os.read_entire_file(file_path, context.temp_allocator)
  if read_err != nil {
    return {}
  }
  text := string(data)
  test_pattern := `TEST_[A-Z0-9_]+`

  tests := make([dynamic]string, context.allocator)
  seen := make(map[string]bool, context.allocator)

  it, err := regex.create_iterator(text, test_pattern, {})
  if err != nil {
    fmt.eprintfln("Could not create iterator for %s: %v", file_path, err)
    return tests
  }
  defer regex.destroy_iterator(it)

  for {
    cap, _, ok := regex.match_iterator(&it)
    if !ok {
      break
    }
    test_macro := cap.groups[0]
    if !seen[test_macro] {
      seen[test_macro] = true
      append(&tests, test_macro)
    }
    regex.destroy_capture(cap)
  }
  return tests
}

resolve_flash_method :: proc(req: cmdline.Hyper_FlashMethod) -> cmdline.Hyper_FlashMethod
{
  found_stm32prog := command_path("STM32_Programmer_CLI", context.temp_allocator) != ""
  found_openocd := command_path("openocd", context.temp_allocator) != ""
  if req != .auto {
    if req == .stm32prog && !found_stm32prog {
      fmt.eprintln("STM32_Programmer_CLI is not available in PATH.")
      return .auto
    }
    if req == .openocd && !found_openocd {
      fmt.eprintln("openocd is not available in PATH.")
      return .auto
    }
  }

  if found_stm32prog { return .stm32prog }
  if found_openocd { return .openocd }
  fmt.eprintln("No supported flash tool found. Install STM32_Programmer_CLI or openocd.")
  return .auto
}

run_preflash_check :: proc(skip_preflight: bool) -> bool
{
  if skip_preflight {
    print_note("preflight skipped", .Warn)
    return true
  }
  ensure_file(PREFLASH_CHECK_SCRIPT, "preflash helper")
  target, _ := os.join_path({REPO_ROOT, "out", "build"}, context.temp_allocator)
  print_action("Preflight", {{"target", target}})
  status := run_command({"python3", PREFLASH_CHECK_SCRIPT, target})
  if status.exit_code == 0 {
    print_note("preflight passed", .Ok)
  } else {
    print_note(fmt.tprintf("preflight failed. Exit code: %d", status.exit_code), .Wrong)
  }
  return status.exit_code == 0
}

flash_elf :: proc(elf: string, method: cmdline.Hyper_FlashMethod, verify, skip_preflight: bool) -> bool
{
  elf := elf
  if elf == "" { elf = LATEST_ELF }
  if !ensure_file(elf, "Elf image") { return false }
  resolved_method := method
  if method == .none { resolved_method = DEFAULT_FLASH_METHOD }
  resolved_method = resolve_flash_method(resolved_method)
  if resolved_method == .auto || resolved_method == .none {
    fmt.eprintfln("Could not resolve flash method")
    return false
  }
  print_action("Flash", {
    {"elf", elf},
    {"method", fmt.tprint(resolved_method)},
    {"verify", "yes" if verify else "no"},
  })
  if !run_preflash_check(skip_preflight) { return false }

  cmd := make([dynamic]string, context.temp_allocator)
  if resolved_method == .stm32prog {
    append(&cmd, "STM32_Programmer_CLI", "-c", "port=SWD", "mode=UR", "-w", elf)
    if verify {
      append(&cmd, "-v")
    }
    append(&cmd, "-rst")
    status := run_command(cmd[:])
    if status.exit_code == 0 {
      print_note("flash completed", .Ok)
    } else {
      print_note(fmt.tprintf("flash failed. Exit code: %d", status.exit_code), .Wrong)
    }
    return true
  }

  stlink_cfg, _ := os.join_path({REPO_ROOT, ".vscode", "stlink.cfg"}, context.temp_allocator)
  stm_cfg, _ := os.join_path({REPO_ROOT, ".vscode", "stm32h7x.cfg"}, context.temp_allocator)
  append(&cmd, "openocd", "-f", stlink_cfg, stm_cfg)
  if verify {
    verify_cmd := cmd
    append(&verify_cmd, "-c", fmt.tprintf("program %s verify reset exit", elf))
    status := run_command(verify_cmd[:])
    if status.exit_code == 0 {
      print_note("flash completed", .Ok)
      return true
    }
    print_note("OpenOCD verify failed, retrying without verify", .Warn)
  }

  append(&cmd, "-c", fmt.tprintf("program %s reset exit", elf))
  status := run_command(cmd[:])
  if status.exit_code == 0 {
    print_note("flash completed", .Ok)
  } else {
    print_note(fmt.tprintf("flash failed. Exit code: %d", status.exit_code), .Wrong)
  }
  return status.exit_code == 0
}

find_serial_ports :: proc() -> []string
{
  port_rank :: proc(port: string) -> int
  {
    if strings.starts_with(port, "/dev/serial/by-id/") { return 0 }
    if strings.starts_with(port, "/dev/cu.usbmodem") { return 1 }
    if strings.starts_with(port, "/dev/ttyACM") { return 2 }
    if strings.starts_with(port, "/dev/cu.usbserial") { return 3 }
    if strings.starts_with(port, "/dev/ttyUSB") { return 4 }
    if strings.starts_with(port, "/dev/cu.wchusbserial") { return 5 }
    if strings.starts_with(port, "/dev/tty.usbmodem") { return 6 }
    if strings.starts_with(port, "/dev/tty.usbserial") { return 7 }
    if strings.starts_with(port, "/dev/tty.wchusbserial") { return 8 }
    return 99
  }

  ports := make([dynamic]string, context.temp_allocator)
  for pat in SERIAL_PATTERNS {
    matches, _ := os.glob(pat, context.temp_allocator)
    for mat in matches {
      if !slice.contains(ports[:], mat) {
        append(&ports, mat)
      }
    }
  }

  Context :: struct {
    key: proc(string) -> int,
  }
  ctx := &Context{port_rank}
  slice.sort_by_generic_cmp(ports[:], proc(lhs, rhs: rawptr, user_data: rawptr) -> slice.Ordering {
    i, j := (^string)(lhs)^, (^string)(rhs)^

    ctx := (^Context)(user_data)
    rank_a := ctx.key(i)
    rank_b := ctx.key(j)

    switch {
      case rank_a < rank_b: return .Less
      case rank_a > rank_b: return .Greater
    }
    switch {
      case i < j: return .Less
      case i > j: return .Greater
    }
    return .Equal
  }, ctx)

  return ports[:]
}

choose_serial_port :: proc(req: string) -> string
{
  explicit := req if req != "" else DEFAULT_UART_PORT
  if explicit != "" && explicit != "auto" {
    return explicit
  }

  when ODIN_OS == .Windows {
    // Gets chosen auto in open_uart if not specified
    return "auto"
  }

  ports := find_serial_ports()
  if len(ports) == 0 {
    fmt.eprintfln("No USB serial port detected. Connect the board or pass --port explicitly")
    return ""
  }
  if len(ports) == 1 {
    return ports[0]
  }

  preferred_prefixes := []string {
    "/dev/serial/by-id/",
    "/dev/cu.usbmodem",
    "/dev/ttyACM",
    "/dev/cu.usbserial",
    "/dev/ttyUSB",
  }
  for prefix in preferred_prefixes {
    for port in ports {
      if strings.starts_with(port, prefix) {
        return port
      }
    }
  }

  fmt.eprintln("Multiple UART ports detected. Pass --port explicitly:")
  for port in ports {
    fmt.eprintfln("  - %s", port)
  }
  return ""
}

resolve_uart_tool :: proc(req: cmdline.Hyper_UartTool) -> cmdline.Hyper_UartTool
{
  tio_found := command_path("tio", context.temp_allocator) != ""
  cu_found := command_path("cu", context.temp_allocator) != ""
  if req != .auto {
    if (req == .tio && !tio_found) || (req == .cu && !cu_found) {
      fmt.eprintfln("UART tool '%v' is not available in PATH.", req)
      return .auto
    }
  }

  if tio_found { return .tio }
  if cu_found { return .cu }
  fmt.eprintfln("No supported UART tool found. Install 'tio' or ensure 'cu' is available.")
  return .auto
}

open_uart :: proc(port: string, baud: int, tool: cmdline.Hyper_UartTool) -> bool
{
  baud := baud
  resolved_port := port
  if port == "" { resolved_port = DEFAULT_UART_PORT }
  resolved_port = choose_serial_port(resolved_port)

  resolved_tool := tool
  if tool == .none { resolved_tool = DEFAULT_UART_TOOL }
  resolved_tool = resolve_uart_tool(resolved_tool)

  if resolved_port == "" {
    fmt.eprintfln("Could not resolve uart port %s", port)
    return false
  }
  if resolved_tool == .auto || resolved_tool == .none {
    fmt.eprintfln("Could not resolve uart tool %v", tool)
    return false
  }

  if baud == 0 { baud = DEFAULT_UART_BAUD }
  print_action("UART", {
    {"tool", fmt.tprint(resolved_tool)},
    {"port", resolved_port},
    {"baud", fmt.tprint(baud)},
  })
  print_note("opening interactive UART session", .Info)

  when ODIN_OS == .Windows {
    platform.open_uart(baud_rate = u32(baud), name = port)
    return true
  }

  // TODO: Inspect process info?
  if resolved_tool == .tio {
    exec_command({"tio", "--baudrate", fmt.tprint(baud), resolved_port}, wait = true)
  } else if resolved_tool == .cu {
    exec_command({"cu", "-l", resolved_port, "-s", fmt.tprint(baud)}, wait = true)
  } else {
    fmt.eprintfln("Unsupported UART tool %v", resolved_tool)
    return false
  }
  return true
}

init_repo :: proc() -> bool
{
  // init.sh
  gitmodules_cmd := []string{"git", "config", "--file", ".gitmodules", "--get-regexp", "path"}
  state, stdout, stderr, err := os.process_exec({command = gitmodules_cmd}, context.temp_allocator)
  if err != nil {
    fmt.eprintfln("Could not start git process: %v", err)
    return false
  }
  if state.exit_code != 0 {
    fmt.eprintln(string(stderr))
    fmt.eprintln("Could not get gitmodules regex")
    return false
  }

  stdout_str := string(stdout)
  for line in strings.split_lines_iterator(&stdout_str) {
    if line == "" { continue }

    _, match, submodule := strings.partition(line, " ")
    if match == "" || submodule == "" { continue }

    check_worktree_cmd := []string{"git", "-C", submodule, "rev-parse", "--is-inside-work-tree"}
    state, stdout, stderr, err = os.process_exec({command = check_worktree_cmd}, context.temp_allocator)
    if err != nil {
      fmt.eprintfln("Could not start git process: %v", err)
      return false
    }
    if state.exit_code == 0 {
      status_cmd := []string{"git", "-C", submodule, "status", "--porcelain"}
      state, stdout, stderr, err = os.process_exec({command = status_cmd}, context.temp_allocator)
      if state.exit_code == 0 && len(stderr) > 0 {
        fmt.printfln("Skipping dirty submodule: %s", submodule)
        continue
      }
    }

    update_cmd := []string{"git", "submodule", "update", "--init", "--", submodule}
    _, stdout, stderr, err = os.process_exec({command = update_cmd}, context.temp_allocator)
    if err != nil {
      fmt.eprintfln("Could not start git process: %v", err)
      return false
    }
    fmt.print(string(stdout))
    fmt.eprint(string(stderr))
  }

  // init-submodules.sh
  when ODIN_OS == .Windows {
    // Give the filesystem a moment after previous git operations
    time.sleep(time.Millisecond * 100)
  }
  print_note("Initializing ST-LIB submodules (git submodule update)...", .Info)
  /*
    git submodule update --init --depth=1
  */
  state = run_command({"git", "submodule", "update", "--init", "--depth=1"}, cwd = STLIB_ROOT)
  if state.exit_code != 0 {
    fmt.eprintfln("Could not init submodules for ST-LIB")
    return false
  }

  when ODIN_OS == .Windows {
    // Give the filesystem a moment after previous git operations
    time.sleep(time.Millisecond * 100)
  }
  stm_root, _ := os.join_path({STLIB_ROOT, "STM32CubeH7"}, context.temp_allocator)
  print_note("Initializing STM32CubeH7 submodules...", .Info)
  /*
    git submodule update --init --depth=1 Drivers/STM32H7xx_HAL_Driver Drivers/CMSIS/Device/ST/STM32H7xx Drivers/BSP/Components/lan8742
  */
  state = run_command({"git", "submodule", "update", "--init", "--depth=1",
    "Drivers/STM32H7xx_HAL_Driver",
    "Drivers/CMSIS/Device/ST/STM32H7xx",
    "Drivers/BSP/Components/lan8742",
  }, cwd = stm_root)
  if state.exit_code != 0 {
    fmt.eprintfln("Could not init submodules for ST-LIB")
    return false
  }

  print_note("Init complete", .Ok)
  return true
}

command_doctor :: proc() -> bool
{
  section_title :: proc(title: string)
  {
    if !COLOR_ENABLED {
      fmt.printfln("\n== %s ==", title)
    } else {
      fmt.printfln(ansi.CSI + ansi.BOLD + ";" + ansi.FG_CYAN + ansi.SGR + 
                   "\n== %s ==" + ansi.CSI + ansi.RESET + ansi.SGR, title)
    }
  }

  print_status_item :: proc(label, status, value: string, detail: string = "")
  {
    if !COLOR_ENABLED {
      fmt.printfln("  {:12s} {:20s} {:s}", status, label, value)
    } else {
      fmt.printfln("  {:12s} " + 
        ansi.CSI + ansi.BOLD + ansi.SGR + "{:20s}" + ansi.CSI + ansi.RESET + ansi.SGR +
        " {:s}", status, label, value)
    }
    if detail != "" {
      print_detail("detail", detail)
    }
  }

  section_title("Toolchain")
  if ensure_required_toolchain() {
    print_note("installed correctly", .Ok)
  } else {
    print_note("missing some tools", .Wrong)
  }

  issues: [dynamic]string
  arm_gcc, programmer, clt_version := inspect_clt()
  uv_path := uv_executable_path()
  uv_version: string
  if uv_path != "" {
    uv_version = read_command_first_line({uv_path, "--version"})
  }

  if arm_gcc.path == "" {
    append(&issues, "arm-none-eabi-gcc missing from PATH")
  }
  if clt_version == "" {
    append(&issues, "STM32CubeCLT version could not be inferred from tool paths")
  } else if clt_version != DEFAULT_REQUIRED_CLT_VERSION {
    append(&issues, fmt.tprintf("STM32CubeCLT %s detected, expected %s", clt_version, DEFAULT_REQUIRED_CLT_VERSION))
  }
  if uv_path == "" {
    append(&issues, "uv is not installed")
  }

  overall_status := "ok" if len(issues) == 0 else "wrong"

  buf: [32]u8
  mem.set(&buf[0], '=', 32)
  if !COLOR_ENABLED {
    fmt.printfln("Hyper Doctor %v", overall_status)
    fmt.printfln("%s", string(buf[:]))
  } else {
    fmt.printfln(ansi.CSI + ansi.BOLD + ansi.SGR + "Hyper Doctor %v" + ansi.CSI + ansi.RESET + ansi.SGR, overall_status)
    fmt.printfln(ansi.CSI + ansi.FAINT + ansi.SGR + "%s" + ansi.CSI + ansi.RESET + ansi.SGR, string(buf[:]))
  }

  section_title("Environment")
  print_detail("repo", REPO_ROOT)
  print_detail("default preset", DEFAULT_PRESET)
  print_detail("default flash", fmt.tprint(DEFAULT_FLASH_METHOD))
  print_detail("default baud", fmt.tprint(DEFAULT_UART_BAUD))
  print_detail("latest elf", "present" if os.exists(LATEST_ELF) else "missing")

  section_title("Toolchain")
  print_status_item(
    "arm-none-eabi-gcc",
    "ok" if arm_gcc.path != "" else "missing",
    arm_gcc.path if arm_gcc.path != "" else "not found",
  )
  if arm_gcc.version_line != "" {
    print_detail("version", arm_gcc.version_line)
  }
  print_status_item(
    "STM32_Programmer",
    "ok" if programmer.path != "" else "missing",
    programmer.path if programmer.path != "" else "not found",
  )
  if programmer.version_line != "" {
    print_detail("version", programmer.version_line)
  }
  print_status_item(
    "STM32CubeCLT",
    overall_status,
    fmt.tprintf("detected=%s expected=%s", clt_version if clt_version != "" else "unknown", DEFAULT_REQUIRED_CLT_VERSION),
  )

  for issue in issues {
    print_note(issue, .Wrong)
  }

  section_title("Host Tools")
  tools := []string{"python3", "cmake", "ninja", "openocd", "tio", "cu", "odin"}
  for tool in tools {
    path := command_path(tool, context.temp_allocator)
    if path != "" {
      print_status_item(tool, "ok", path)
    } else {
      print_status_item(tool, "missing", "not found")
    }
  }
  print_status_item("uv", 
    "ok" if uv_path != "" else "missing", 
    uv_path if uv_path != "" else "not found",
  )
  if uv_version != "" {
    print_detail("version", uv_version)
  }

  resolved_uart_tool := resolve_uart_tool(.auto)
  print_status_item("uart tool", "ok", fmt.tprint(resolved_uart_tool))

  section_title("Serial")
  ports := find_serial_ports()
  if len(ports) == 0 {
    print_status_item("serial ports", "warn", "none detected")
  } else if len(ports) == 1 {
    print_status_item("serial port", "ok", ports[0])
  } else {
    print_status_item("serial ports", "ok", fmt.tprint(len(ports), "detected"))
    for port in ports {
      print_detail("port", port)
    }
  }

  section_title("Repo Helpers")
  print_status_item(
    "stlib build.py",
    "ok" if os.exists(STLIB_BUILD_SCRIPT) else "missing",
    STLIB_BUILD_SCRIPT,
  )
  print_status_item(
    "stlib sim tests",
    "ok" if os.exists(STLIB_SIM_TESTS_SCRIPT) else "missing",
    STLIB_SIM_TESTS_SCRIPT,
  )
  print_status_item(
    "hard fault tool",
    "ok" if os.exists(HARD_FAULT_ANALYSIS_SCRIPT) else "missing",
    HARD_FAULT_ANALYSIS_SCRIPT,
  )

  section_title("Summary")
  if len(issues) != 0 {
    print_note("doctor failed", .Wrong)
  } else {
    print_note("doctor passed", .Ok)
  }
  return len(issues) == 0
}

command_examples :: proc(examples: ^cmdline.Hyper_ExamplesCommand) -> bool
{
  if !ensure_file(BUILD_EXAMPLE_SCRIPT, "build-example helper") {
    return false
  }

  // TODO: replace examples script...
  if examples.subcommand == .list {
    print_action("Examples", {{"mode", "list"}})
    run_command({BUILD_EXAMPLE_SCRIPT, "--list"})
  } else if examples.subcommand == .tests {
    if examples.example == "" {
      fmt.printfln("Missing example flag, required if using %s examples tests", os.args[0])
      return false
    }
    print_action("Examples", {
      {"mode", "tests"},
      {"example", examples.example},
    })
    run_command({BUILD_EXAMPLE_SCRIPT, "--list-tests", examples.example})
  }
  return true
}

command_run :: proc(run: ^cmdline.Hyper_RunCommand) -> bool
{
  buf: [16]u8
  mem.set(&buf[0], '=', 16)
  fmt.println(ansi.CSI + ansi.BOLD + ansi.SGR + "Hyper Run" + ansi.CSI + ansi.RESET + ansi.SGR)
  fmt.printfln(ansi.CSI + ansi.FAINT + ansi.SGR + "%.*s", ansi.CSI + ansi.RESET + ansi.SGR, 16, &buf[0])
  inject_at(&run.overflow, 0, run.extra_cxx_flags)
  build_ok := run_build_example(
    example = run.example,
    test = run.test,
    no_test = run.no_test,
    preset = run.preset,
    board_name = run.board_name,
    extra_cxx_flags = run.overflow[:] if run.extra_cxx_flags != "" else nil,
    jobs = run.jobs,
    use_script = run.use_script,
    use_cmake = !run.dont_use_cmake,
  )
  if !build_ok {
    fmt.eprintfln("Failed to build")
    return false
  }

  if !flash_elf(run.elf, run.method, !run.no_verify, run.skip_preflight) {
    fmt.eprintfln("Failed to flash elf")
    return false
  }
  if run.uart {
    if !open_uart(run.port, run.baud, run.uart_tool) {
      fmt.eprintfln("Failed to open uart port")
      return false
    }
  } else {
    print_note("run completed", .Ok)
  }
  return true
}

command_hardfault_analysis :: proc() -> bool
{
  if !ensure_file(HARD_FAULT_ANALYSIS_SCRIPT, "hard fault analysis helper") {
    return false
  }
  print_action("Hard Fault Analysis", {
    {"script", HARD_FAULT_ANALYSIS_SCRIPT},
    {"elf", LATEST_ELF},
  })
  status := run_command({"python3", HARD_FAULT_ANALYSIS_SCRIPT}, cwd = REPO_ROOT)
  if status.exit_code == 0 {
    print_note("hard fault analysis completed", .Ok)
  } else {
    print_note("hard fault analysis failed", .Wrong)
  }
  return status.exit_code == 0
}

command_stlib_build :: proc(stlib_build: ^cmdline.Hyper_StlibBuildCommand) -> bool
{
  if stlib_build.preset == "" {
    fmt.eprintfln("Missing preset flag")
    return false
  }

  ensure_file(STLIB_BUILD_SCRIPT, "ST-LIB build helper")
  print_action("ST-LIB Build", {
    {"preset", stlib_build.preset},
    {"tests", "yes" if stlib_build.run_tests else "no"},
  })
  cmd := make([dynamic]string, context.temp_allocator)
  append(&cmd, "python3", STLIB_BUILD_SCRIPT, "--preset", stlib_build.preset)
  if stlib_build.run_tests {
    append(&cmd, "--run-tests")
  }
  status := run_command(cmd[:], cwd = STLIB_ROOT)
  if status.exit_code == 0 {
    print_note("ST-LIB build completed", .Ok)
  } else {
    print_note("ST-LIB build failed", .Wrong)
  }
  return status.exit_code == 0
}

command_stlib_sim_tests :: proc() -> bool
{
  ensure_file(STLIB_SIM_TESTS_SCRIPT, "ST-LIB simulator test helper")
  print_action("ST-LIB Sim Tests", {
    {"script", STLIB_SIM_TESTS_SCRIPT},
  })
  status := run_command({STLIB_SIM_TESTS_SCRIPT}, cwd = STLIB_ROOT)
  if status.exit_code == 0 {
    print_note("ST-LIB sim tests completed", .Ok)
  } else {
    print_note("ST-LIB sim tests failed", .Wrong)
  }
  return status.exit_code == 0
}

main :: proc()
{
  if ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

  platform.init()
  setup_globals()
  defer free_all_globals()

  platform.write_console_unicode(HELP_BANNER)
  fmt.println()

  opts: cmdline.Hyper_Options
  if !cmdline.parse(&opts) {
    os.exit(1)
  }
  if(opts.command == .version) {
    fmt.printfln("%s v%s", os.args[0], HYPER_VERSION)
    return
  }

  switch opts.command {
    case .init: {
      if !ensure_required_clt() {
        os.exit(2)
      }

      if !ensure_required_toolchain() {
        os.exit(2)
      }

      uv_path := ensure_uv()
      if uv_path == "" {
        os.exit(2)
      }

      setup_python_env_with_uv(uv_path)

      init_repo()
    }

    case .help: {
      cmdline.handle_help_command(opts.help)
    }

    case .version: {
      fmt.printfln("%s v%s", os.args[0], HYPER_VERSION)
    }

    case .examples: {
      command_examples(&opts.examples)
    }

    case .build: {
      inject_at(&opts.build.overflow, 0, opts.build.extra_cxx_flags)
      run_build_example(
        example = opts.build.example,
        test = opts.build.test,
        no_test = opts.build.no_test,
        preset = opts.build.preset,
        board_name = opts.build.board_name,
        extra_cxx_flags = opts.build.overflow[:] if opts.build.extra_cxx_flags != "" else nil,
        jobs = opts.build.jobs,
        use_script = opts.build.use_script,
        use_cmake = !opts.build.dont_use_cmake,
      )
    }

    case .flash: {
      flash_elf(opts.flash.elf, opts.flash.method, !opts.flash.no_verify, opts.flash.skip_preflight)
    }

    case .run: {
      command_run(&opts.run)
    }

    case .uart: {
      open_uart(opts.uart.port, opts.uart.baud, opts.uart.uart_tool)
    }

    case .doctor: {
      command_doctor()
    }

    case .hardfault_analysis: {
      command_hardfault_analysis()
    }

    case .stlib_build: {
      command_stlib_build(&opts.stlib_build)
    }

    case .stlib_sim_tests: {
      command_stlib_sim_tests()
    }
  }
}
