#+vet style
#+vet unused
#+vet unused-variables
#+vet unused-imports
#+vet shadowing
package hyper

import "core:os"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:dynlib"
import "core:strings"
import "core:encoding/json"

Hyper_Compile_Type :: enum {
  Executable = 0,
  Object,
  DynamicLibrary,
  StaticLibrary,
}

Hyper_Optimization_Option :: enum {
  Nothing = 0,
  Speed = 1, /* -O3 for gcc, clang */
  Size = 2, /* -Os for gcc, clang */
}

Hyper_Compile_Ctx :: struct {
  // c compiler (all compilers are assumed to have the same flag style as gcc)
  cc: string,
  // executable by default
  type: Hyper_Compile_Type,
  optimize: Hyper_Optimization_Option,

  debug: bool,
  /* adds "-Wl,--gc-sections" or nothing */
  gcSections: bool,
  /* adds "-Wall -Wextra" or nothing */
  warnings: bool,
  /* adds "-Werror" or nothing */
  warningsAsErrors: bool,
  sourceFiles: []string,

  output: string,
  outputDirectory: string,
  outputExtension: string,
  
  includePaths: []string,
  extraCompilerFlags: []string,

  libPaths: []string,
  libs: []string,
}

get_filepath_from_compile_ctx :: proc(ctx: Hyper_Compile_Ctx) -> string
{
  if ctx.output == "" && (ctx.type != .Object) {
    fmt.eprintln("Output path must be specified unless compiling for object file")
    return ctx.output
  }
  
  output := fmt.tprintf("%s/%s", ctx.outputDirectory, ctx.output)
  if ctx.outputExtension != "" {
    return fmt.tprintf("%s%s", output, ctx.outputExtension)
  }

  when ODIN_OS == .Windows {
    if ctx.type == .Executable {
      return fmt.tprintf("%s.exe", output)
    }
  }

  if ctx.type == .Object {
    if ctx.output != "" {
      return fmt.tprintf("%s.o", output)
    }
  } else if ctx.type == .DynamicLibrary {
    return fmt.tprintf("%s" + dynlib.LIBRARY_FILE_EXTENSION, output)
  } else if ctx.type == .StaticLibrary {
    return fmt.tprintf("%s.o", output)
  }
  return output
}

// Only checks the filetime of all the input files vs output file
// returns 1 on need rebuild, -1 on error and 0 if not need rebuild
needs_rebuild :: proc(out: string, input_paths: []string) -> int
{
  outTime, err := os.modification_time_by_path(out)
  if err != nil {
    return 1
  }

  for path in input_paths {
    inTime: time.Time
    inTime, err = os.modification_time_by_path(path)
    if err != nil {
      return -1
    }

    if time.diff(outTime, inTime) > 0 {
      return 1
    }
  }

  return 0
}

/* assumes at least the compiler has been included in cmd at the start */
needs_c_rebuild_cmd :: proc(cmd: ^[dynamic]string, output: string, sourceFiles: []string) -> int
{
  needsRebuildSimple := needs_rebuild(output, sourceFiles)
  if needsRebuildSimple != 0 {
    return needsRebuildSimple
  }

  mark := len(cmd)
  defer resize(cmd, mark)
  append(cmd, "-MM")
  append(cmd, ..sourceFiles[:])

  desc := os.Process_Desc {
    command = cmd[:],
  }
  state, stdout, _, err := os.process_exec(desc, context.temp_allocator)
  if state.exit_code != 0 || err != nil {
    fmt.eprintfln("Failed to check if %s needs rebuild", output)
    return -1
  }

  includes := make([dynamic]string, context.temp_allocator)
  data := string(stdout)

  // output from gcc is structured like this:
  // file1.o: file1.c <include list>
  // file2.o: file2.c <include list>
  // etc.
  lines := strings.split_lines(data, context.temp_allocator)
  for i := 0; i < len(lines); i += 1 {
    line := lines[i]
    // NOTE: "file.o: "
    _, _, line = strings.partition(line, ": ")
    // NOTE: "file.c"
    _, _, line = strings.partition(line, " ")

    for len(line) > 0 {
      inc: string
      inc, _, line = strings.partition(line, " ")
      if inc[0] == '\\' {
        /* Skip '\n' and ' ' after '\n' */
        i += 1
        line = lines[i][1:]
        continue
      }

      append(&includes, inc)
    }
  }

  outTime, time_err := os.modification_time_by_path(output)
  if time_err != nil {
    return 1
  }

  for path in includes {
    inTime: time.Time
    inTime, time_err = os.modification_time_by_path(path)
    if time_err != nil {
      return -1
    }

    if time.diff(outTime, inTime) > 0 {
      return 1
    }
  }

  return 0
}

needs_c_rebuild :: proc(ctx: Hyper_Compile_Ctx) -> int
{
  cmd := make([dynamic]string, context.temp_allocator)
  append(&cmd, "gcc", "-MM")

  output := get_filepath_from_compile_ctx(ctx)

  for path in ctx.includePaths {
    append(&cmd, "-I", path)
  }

  return needs_c_rebuild_cmd(&cmd, output, ctx.sourceFiles)
}

compile_c_context :: proc(ctx: Hyper_Compile_Ctx, parallel := false) -> (os.Process, bool)
{
  ctx := ctx
  cmd := make([dynamic]string, context.temp_allocator)
  if ctx.outputDirectory == "" {
    ctx.outputDirectory = "."
  }
  output := get_filepath_from_compile_ctx(ctx)
  append(&cmd, ctx.cc)

  // compile only, don't link
  if ctx.type == .StaticLibrary || ctx.type == .Object {
    append(&cmd, "-c")
  }
  append(&cmd, ..ctx.sourceFiles[:])
  if output != "" {
    append(&cmd, "-o", ctx.output)
  }

  if ctx.optimize == .Speed {
    append(&cmd, "-O3")
  } else if ctx.optimize == .Size {
    append(&cmd, "-Os")
  }

  if ctx.debug { append(&cmd, "-g") }
  if ctx.warnings { append(&cmd, "-Wall", "-Wextra") }
  if ctx.warningsAsErrors { append(&cmd, "-Werror") }
  for inc in ctx.includePaths {
    append(&cmd, "-I", inc)
  }

  append(&cmd, ..ctx.extraCompilerFlags[:])

  for libPath in ctx.libPaths {
    append(&cmd, "-L", libPath)
  }
  for lib in ctx.libs {
    append(&cmd, "-l", lib)
  }

  if ctx.type == .DynamicLibrary {
    append(&cmd, "-shared")
  }
  if ctx.gcSections {
    append(&cmd, "-Wl,--gc-sections")
  }

  desc := os.Process_Desc {
    command = cmd[:],
  }
  process, err := os.process_start(desc)
  if err != nil {
    fmt.eprintfln("Could not run process %v: %v", cmd[:], err)
    return os.Process{}, false
  }

  if parallel {
    return process, true
  } else {
    state: os.Process_State
    state, err = os.process_wait(process)
    if err != nil {
      fmt.eprintfln("Could not wait for process %v: %v", cmd[:], err)
      return os.Process{}, false
    }
    return os.Process{}, state.exit_code == 0
  }
}

wait_all_processes :: proc(processes: []os.Process) -> bool
{
  ok := true
  for p in processes {
    state, err := os.process_wait(p)
    if err != nil || state.exit_code != 0 {
      ok = false
    }
  }
  return ok
}

run_build_example_script :: proc(example, test: string, no_test: bool, preset, board_name: string, extra_cxx_flags: []string, jobs: int) -> bool
{
  if !ensure_file(BUILD_EXAMPLE_SCRIPT, "build-example helper") {
    return false
  }
  main_targets := []string{"", "main", "default"}
  is_main_target := slice.contains(main_targets, strings.to_lower(example, context.temp_allocator))
  selected_test := "none" if no_test || is_main_target else test
  if selected_test == "" { selected_test = "default" }

  if is_main_target {
    print_action("Build", {
      {"preset", preset},
      {"test", selected_test},
      {"board_name", board_name if board_name != "" else "default"},
    })
  } else {
    print_action("Build", {
      {"example", example},
      {"preset", preset},
      {"test", selected_test},
      {"board_name", board_name if board_name != "" else "default"},
    })
  }

  cmd := make([dynamic]string, context.temp_allocator)
  append(&cmd, BUILD_EXAMPLE_SCRIPT)
  if example != "" { append(&cmd, "--example", example) }
  append(&cmd, "--preset", preset)
  if no_test { append(&cmd, "--no-test") }
  else if test != "" { append(&cmd, "--test", test) }

  if board_name != "" { append(&cmd, "--board-name", board_name) }
  for flag in extra_cxx_flags {
    append(&cmd, "--extra-cxx-flags", flag)
  }

  status := run_command(cmd[:])
  if status.exit_code == 0 {
    print_note("build completed", .Ok)
  } else {
    print_note(fmt.tprintf("Could not complete build. Exit code: %d", status.exit_code), .Wrong)
  }
  return status.exit_code == 0
}

run_build_example_cmake :: proc(example, test: string, no_test: bool, preset, board_name: string, extra_cxx_flags: []string, jobs: int) -> bool
{
  example_macro: string
  if example == "" {
    example_macro = "MAIN"
  } else {
    example_macro = normalize_example_macro(example)
  }
  is_main := example_macro == "MAIN"

  available_macros: [dynamic]string
  file_map: map[string]string
  if !is_main {
    available_macros, file_map = collect_examples()
    defer delete(available_macros)
    defer delete(file_map)

    found := false
    for macro in available_macros {
      if macro == example_macro {
        found = true
        break
      }
    }
    if !found {
      fmt.eprintfln("Unknown example macro '%s'.", example_macro)
      fmt.eprintln("Available examples:")
      for macro in available_macros {
        fmt.eprintfln("  - %s", macro)
      }
      return false
    }
  }

  test_macro: string
  if no_test {
    test_macro = ""
  } else if test != "" {
    test_macro = normalize_test_macro(test)
    if is_main {
      fmt.eprintln("Target 'main' does not support TEST_* macros.")
      return false
    }
  } else {
    if is_main {
      test_macro = ""
    } else {
      file_path := file_map[example_macro]
      tests := collect_tests_for_file(file_path)
      defer delete(tests)
      if len(tests) > 0 {
        test_macro = "TEST_0"
      } else {
        test_macro = ""
      }
    }
  }

  define_flags: string
  if !is_main {
    if test_macro != "" {
      define_flags = strings.join(a = {
        "-D", example_macro,
        " -D", test_macro,
      }, sep = "", allocator = context.temp_allocator)
    } else {
      define_flags = strings.join(a = {
        "-D", example_macro,
      }, sep = "", allocator = context.temp_allocator)
    }
  } else {
    if test_macro != "" {
      fmt.eprintln("Target 'main' does not support TEST_* macros.")
      return false
    }
  }

  build_examples := "OFF" if is_main else "ON"

  preset_san := sanitize_path_fragment(preset)
  example_san := sanitize_path_fragment(example_macro)
  test_san := "no_test"
  if test_macro != "" {
    test_san = sanitize_path_fragment(test_macro)
  }
  binary_dir, _ := os.join_path({REPO_ROOT, "out", "build", "examples", preset_san, example_san, test_san}, context.allocator) // TODO: make this context.temp_allocator

  details := make([dynamic][2]string, context.temp_allocator)
  if is_main {
    append(&details, [2]string{"example", "main"})
  } else {
    append(&details, [2]string{"example", example_macro})
  }
  append(&details, [2]string{"preset", preset})
  if test_macro != "" {
    append(&details, [2]string{"test", test_macro})
  } else {
    append(&details, [2]string{"test", "<none>"})
  }
  if board_name != "" {
    append(&details, [2]string{"board_name", board_name})
  }
  if len(extra_cxx_flags) > 0 {
    append(&details, [2]string{"extra_cxx_flags", strings.join(extra_cxx_flags, " ", context.temp_allocator)})
  }
  print_action("Build", details[:])

  configure_cmd := make([dynamic]string, context.temp_allocator)
  append(&configure_cmd, "cmake", "--preset", preset, "-B", binary_dir,
    "-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON")
  append(&configure_cmd, fmt.tprintf("-DBUILD_EXAMPLES=%s", build_examples))
  append(&configure_cmd, "-DCMAKE_EXPORT_COMPILE_COMMANDS=OFF")
  if define_flags != "" {
    append(&configure_cmd, fmt.tprintf("-DCMAKE_CXX_FLAGS=\"%s\"", define_flags))
  }
  if board_name != "" {
    append(&configure_cmd, fmt.tprintf("-DBOARD_NAME=%s", board_name))
  }

  state := run_command(configure_cmd[:], REPO_ROOT)
  if state.exit_code != 0 {
    print_note(fmt.tprintf("CMake configure failed. Exit code: %d", state.exit_code), .Wrong)
    return false
  }

  build_cmd := make([dynamic]string, context.temp_allocator)
  append(&build_cmd, "cmake", "--build", binary_dir, "--", 
    "-d", /* "keeprsp" */ "keepdepfile")
  if jobs > 0 {
    append(&build_cmd, "-j", fmt.tprint(jobs))
  }
  state = run_command(build_cmd[:], REPO_ROOT)
  if state.exit_code != 0 {
    print_note(fmt.tprintf("Build failed. Exit code: %d", state.exit_code), .Wrong)
    return false
  }

  print_note("build completed", .Ok)
  return true
}

ord_number :: proc(n: int) -> string
{
  switch n {
    case 0: return "1st"
    case 1: return "2nd"
    case 2: return "3rd"
    case: return fmt.tprintf("%dth", n)
  }
}

/* Replaces any ${VARIABLE} in format if it is in vars and return false if it doesn't exist */
format_variable :: proc(vars: map[string]string, format: string, what: string) -> (result: string, ok: bool)
{
  builder := strings.builder_make(context.temp_allocator)
  pos := 0
  ok = true

  for pos < len(format) {
    start_offset := strings.index(format[pos:], "${")
    if start_offset == -1 {
      // no more variables to format
      strings.write_string(&builder, format[pos:])
      break
    }

    // Copy everything before the format
    strings.write_string(&builder, format[pos:pos + start_offset])

    format_start := pos + start_offset
    // Find the closing '}' after "${"
    close_offset := strings.index(format[format_start + 2:], "}")
    if close_offset == -1 {
      // Malformed format (no closing '}')
      print_note(fmt.tprintf("Missing closing '}' in '%s' in %s", format, what), .Wrong)
      strings.write_string(&builder, format[format_start:])
      ok = false
      pos = len(format)
      break
    }

    close_abs := format_start + 2 + close_offset
    name := format[format_start + 2 : close_abs]

    if val, exists := vars[name]; exists {
      strings.write_string(&builder, val)
    } else {
      // Variable not found
      print_note(fmt.tprintf("Missing variable '%s' in '%s' ", format, what), .Wrong)
      strings.write_string(&builder, format[format_start:close_abs + 1])
      ok = false
    }

    // continue after '}'
    pos = close_abs + 1
  }

  result = strings.to_string(builder)
  return
}

error_from_stderr_handle :: proc(cmd: []string, handle: ^os.File, exit_code: int)
{
  data, err := os.read_entire_file_from_file(handle, context.temp_allocator)
  if err != nil {
    fmt.eprintfln("Failed to read stderr from %v: %v", cmd, err)
    fmt.eprintfln("Exited with code %d", exit_code)
  } else {
    fmt.eprintfln("Error in %v", cmd)
    fmt.eprint(string(data))
    fmt.eprintfln("Exited with code %d", exit_code)
  }
}

/* structure for "hyper-build.json" scripts */
Hyper_BuildConfig :: struct {
  presets: []struct {
    name: string,
    hidden: bool,
    displayName: string,
    binaryDir: string,
    toolchainPrefix: string,
    targetType: string,
    inherits: []string,
    targetMode: string,
    defines: map[string]string,
  },

  variables: map[string]string,

  buildInfo: []struct {
    name: string,
    /* this field is called 'when' in json but it's a keyword in odin */
    cond: struct {
      variable: string,
      op: string,
      value: string,
    } `json:"when"`,
    /* extra C compiler flags */
    compilerFlags: []string,
    linkerFlags: []string,
    /* These will be added as "-D" <define>. So you may do:
     * "cDefines": [ "DEFINITION=VALUE" ] and it will also work
     */
    cDefines: []string,
    includePaths: []string,
    sources: []string,
  },
}

build_objects_parallel :: proc(cmd: ^[dynamic]string, binaryDir: string, includePaths, sources: []string) -> ([]string, bool)
{
  //parallel_max := os.get_processor_core_count()
  //RunningProcess :: struct {
  //  handle: os.Process,
  //  cmd: []string,
  //  stderr_r: ^os.File,
  //}
  //processes := make([dynamic]RunningProcess, context.temp_allocator)

  // TODO...

  /*
  stderr_r, stderr_w: ^os.File
  stderr_r, stderr_w, err = os.pipe()
  if err != nil {
    fmt.printfln("Could not create pipe for process %v: %v", cmd[:], err)
    ok = false
    continue
  }

  process: os.Process
  desc := os.Process_Desc {
    command = cmd[:],
    stderr = stderr_w,
  }
  process, err = os.process_start(desc)
  if err != nil {
    fmt.eprintfln("Could not run process %v: %v", cmd[:], err)
    os.close(stderr_r)
    os.close(stderr_w)
    ok = false
    continue
  }
  fmt.printfln("[INFO] compiling %s", src)
  os.close(stderr_w)

  if len(processes) >= parallel_max {
    for pIdx := 0; pIdx < len(processes); {
      state: os.Process_State
      state, err = os.process_wait(processes[pIdx].handle, 0)
      if state.exited {
        os.close(processes[pIdx].stderr_r)
        unordered_remove(&processes, pIdx)
        if state.exit_code != 0 {
          error_from_stderr_handle(processes[pIdx].cmd, processes[pIdx].stderr_r, state.exit_code)
          ok = false
        }
        continue
      }
      pIdx += 1
    }

    if len(processes) >= parallel_max {
      state: os.Process_State
      state, err = os.process_wait(processes[0].handle, 0)
      if err != nil {
        fmt.eprintfln("Failed to wait for %v", processes[0].cmd)
        ok = false
      } else if state.exit_code != 0 {
        error_from_stderr_handle(processes[0].cmd, processes[0].stderr_r, state.exit_code)
        ok = false
      }
      os.close(processes[0].stderr_r)
      unordered_remove(&processes, 0)
    }
  }

  p := RunningProcess {
    handle = process,
    stderr_r = stderr_r,
    cmd = slice.clone(cmd[:], context.temp_allocator),
  }
  append(&processes, p)
  */

  /*
  for pIdx := 0; pIdx < len(processes); pIdx += 1 {
    state: os.Process_State
    state, err = os.process_wait(processes[pIdx].handle)
    os.close(processes[pIdx].stderr_r)
    if state.exit_code != 0 {
      error_from_stderr_handle(processes[pIdx].cmd, processes[pIdx].stderr_r, state.exit_code)
      ok = false
    }
  }

  */

  return []string{}, false
}

get_all_dependencies :: proc(cmd: []string, sources: []string) -> (deps_map: map[string][]string, ok: bool)
{
  desc := os.Process_Desc {
    command = cmd[:],
  }
  state, stdout, stderr, err := os.process_exec(desc, context.temp_allocator)
  if err != nil {
    fmt.eprintfln("Failed to get dependencies %v: %v", cmd[:], err)
    return nil, false
  }
  if state.exit_code != 0 {
    fmt.eprintfln("Failed to get dependencies %v", cmd[:])
    fmt.eprintln(string(stderr))
    fmt.eprintfln("Exited with code %d", state.exit_code)
    return nil, false
  }

  deps_map = make(map[string][]string, len(sources), context.temp_allocator)
  data := string(stdout)
  lines := strings.split_lines(data, context.temp_allocator)

  // output from gcc is structured like this:
  // file1.o: file1.c <include list>
  // file2.o: file2.c <include list>
  // etc.
  // The include list could be in different lines separated by '\'.
  for i := 0; i < len(lines); i += 1 {
    line := lines[i]
    colon := strings.index(line, ": ")
    if colon == -1 do continue

    target_part := line[:colon]
    dep_part := line[colon+2:]

    src := strings.trim_suffix(target_part, ".o")
    if src == target_part {
      // fallback: use the first dependency if the target doesn't end with .o
      // (e.g. if we used -MMD with different suffix)
      deps := strings.split(dep_part, " ", context.temp_allocator)
      if len(deps) > 0 {
        src = deps[0]
      } else {
        continue
      }
    }

    all_deps := make([dynamic]string, 0, context.temp_allocator)
    // Handle '\' at the end of a line
    for len(dep_part) > 0 {
      dep_part = strings.trim_space(dep_part)
      if dep_part == "" do break

      parts := strings.split(dep_part, " ", context.temp_allocator)
      for p in parts {
        if p == "" || p == "\\" do continue
        append(&all_deps, p)
      }

      if strings.has_suffix(line, "\\") {
        i += 1
        if i >= len(lines) do break
        line = lines[i]
        dep_part = line
      } else {
        break
      }
    }

    deps_map[src] = all_deps[:]
  }

  return deps_map, true
}

get_info_for_all_sources :: proc(cmd: ^[dynamic]string, binaryDir: string, includePaths, sources: []string) -> (outputFiles: []string, needRebuild: []bool) {
  outputFiles = make([]string, len(sources), context.temp_allocator)
  needRebuild = make([]bool, len(sources), context.temp_allocator)

  mark := len(cmd)
  defer resize(cmd, mark)
  append(cmd, "-MM")

  deps_map, ok := get_all_dependencies(cmd[:], sources)
  if !ok {
    for src, idx in sources {
      output := fmt.tprintf("%s/%s.o", binaryDir, src)
      os.make_directory_all(os.dir(output))

      outputFiles[idx] = output
      needRebuild[idx] = needs_rebuild(output, []string{src}) != 0
    }
    return
  }

  for src, idx in sources {
    output := fmt.tprintf("%s/%s.o", binaryDir, src)
    os.make_directory_all(os.dir(output))

    outputFiles[idx] = output

    outTime, err := os.modification_time_by_path(output)
    if err != nil {
      needRebuild[idx] = true
      continue
    }

    deps := deps_map[src]
    rebuild := false
    for dep in deps {
      inTime: time.Time
      inTime, err = os.modification_time_by_path(dep)
      if err != nil {
        // missing dependency - needs rebuild
        rebuild = true
        break
      }
      if time.diff(outTime, inTime) > 0 {
        rebuild = true
        break
      }
    }
    needRebuild[idx] = rebuild
  }

  return
}

build_objects_serial :: proc(cmd: ^[dynamic]string, binaryDir: string, includePaths, sources: []string) -> ([]string, bool)
{
  outputFiles, needRebuild := get_info_for_all_sources(cmd, binaryDir, includePaths, sources)

  ok := true
  for src, srcIdx in sources {
    if needRebuild[srcIdx] {
      mark := len(cmd)
      defer resize(cmd, mark)

      output := outputFiles[srcIdx]

      append(cmd, src, "-o", output)
      
      fmt.printfln("[%d/%d] %s", srcIdx + 1, len(sources), src)

      desc := os.Process_Desc {
        command = cmd[:],
      }
      state, _, stderr, err := os.process_exec(desc, context.temp_allocator)
      if err != nil {
        fmt.eprintfln("Could not exec process %v: %v", cmd[:], err)
        ok = false
        continue
      }
      if state.exit_code != 0 {
        fmt.eprintfln("Error in %v", cmd[:])
        fmt.eprint(string(stderr))
        fmt.eprintfln("Exited with code %d", state.exit_code)
        ok = false
      }
    }
  }

  return outputFiles, ok
}

run_build_example :: proc(example, test: string, no_test: bool, preset, board_name: string, extra_cxx_flags: []string, jobs: int, use_script := false, use_cmake := true) -> bool
{
  preset := preset
  if preset == "" {
    preset = DEFAULT_PRESET
  }
  if use_script {
    return run_build_example_script(example, test, no_test, preset, board_name, extra_cxx_flags, jobs)
  }
  if use_cmake {
    return run_build_example_cmake(example, test, no_test, preset, board_name, extra_cxx_flags, jobs)
  }

  if os.exists("hyper-build.json") {
    data, err := os.read_entire_file("hyper-build.json", context.temp_allocator)
    if err != nil {
      fmt.eprintfln("Could not read hyper-build.json: %v", err)
      return false
    }

    buildCfg: Hyper_BuildConfig
    // TODO: More manual parse of json instead of json.unmarshal? (for better error messages)
    unmarshal_err := json.unmarshal(data, &buildCfg, allocator = context.temp_allocator)
    if unmarshal_err != nil {
      fmt.eprintfln("Could not unmarshall hyper-build.json: %v", unmarshal_err)
      return false
    }

    // step 1: handle preset
    configureIdx := -1
    for p, idx in buildCfg.presets {
      if p.name == preset && !p.hidden { configureIdx = idx; break }
    }

    if configureIdx == -1 {
      fmt.eprintfln("Could not find preset %s in presets in hyper-build.json", preset)
      return false
    }

    binaryDir := "out/build/${presetName}"
    toolchainPrefix := ""
    targetType := ""
    targetMode := "Debug"
    presetDefines := make(map[string]string, context.temp_allocator)

    // TODO: Guard circular dependencies in preset inherits
    inheritStack := make([dynamic]string, context.temp_allocator)
    append(&inheritStack, ..buildCfg.presets[configureIdx].inherits[:])
    for len(inheritStack) > 0 {
      inherit := inheritStack[0]
      ordered_remove(&inheritStack, 0)

      idx := -1
      for p, i in buildCfg.presets {
        if p.name == inherit { idx = i; break }
      }

      if idx == -1 {
        fmt.eprintfln("Unknown preset %s in %s's inherited presets", inherit, preset)
        return false
      }

      if buildCfg.presets[idx].binaryDir != "" {
        binaryDir = buildCfg.presets[idx].binaryDir
      }
      if buildCfg.presets[idx].toolchainPrefix != "" {
        toolchainPrefix = buildCfg.presets[idx].toolchainPrefix
      }
      if buildCfg.presets[idx].targetType != "" {
        targetType = buildCfg.presets[idx].targetType
      }
      if buildCfg.presets[idx].targetMode != "" {
        targetMode = buildCfg.presets[idx].targetMode
      }
      // Ignore the possibility of overwriting a define.
      // I don't really care if this map gets a little larger than it should be
      reserve(&presetDefines, len(presetDefines) + len(buildCfg.presets[idx].defines))
      for key, val in buildCfg.presets[idx].defines {
        presetDefines[key] = val
      }

      if len(buildCfg.presets[idx].inherits) > 0 {
        append(&inheritStack, ..buildCfg.presets[idx].inherits[:])
      }
    }

    if buildCfg.presets[configureIdx].binaryDir != "" {
      binaryDir = buildCfg.presets[configureIdx].binaryDir
    }
    if buildCfg.presets[configureIdx].toolchainPrefix != "" {
      toolchainPrefix = buildCfg.presets[configureIdx].toolchainPrefix
    }
    if buildCfg.presets[configureIdx].targetType != "" {
      targetType = buildCfg.presets[configureIdx].targetType
    }
    if buildCfg.presets[configureIdx].targetMode != "" {
      targetMode = buildCfg.presets[configureIdx].targetMode
    }
    reserve(&presetDefines, len(presetDefines) + len(buildCfg.presets[configureIdx].defines))
    for key, val in buildCfg.presets[configureIdx].defines {
      presetDefines[key] = val
    }

    presetMap := make(map[string]string, context.temp_allocator)
    presetMap["presetName"] = preset
    bin_ok: bool
    binaryDir, bin_ok = format_variable(presetMap, binaryDir, "Binary Directory")
    if !bin_ok {
      return false
    }

    reserve(&presetDefines, len(presetDefines) + len(buildCfg.variables))
    for key, val in buildCfg.variables {
      presetDefines[key] = val
    }

    // step 2: gather buildInfo
    // cDefines field will be included here since it just means more flags
    // includePaths will also be included here since it just means more flags
    compilerFlags := make([dynamic]string, context.temp_allocator)
    includePaths := make([dynamic]string, context.temp_allocator)
    linkerFlags := make([dynamic]string, context.temp_allocator)
    sources := make([dynamic]string, context.temp_allocator)
    infoloop: for info, infoIdx in buildCfg.buildInfo {
      if info.cond.variable != "" {
        switch info.cond.op {
          case "": {
            fmt.eprintfln("Missing 'op' field in %s buildInfo 'when' field", 
              info.name if info.name != "" else ord_number(infoIdx))
            return false
          }

          case "equal": {
            val := presetDefines[info.cond.variable]
            if val != info.cond.value {
              continue infoloop
            }
          }

          case "not equal": {
            val := presetDefines[info.cond.variable]
            if val == info.cond.value {
              continue infoloop
            }
          }
        }
      }

      append(&compilerFlags, ..info.compilerFlags[:])
      append(&linkerFlags, ..info.linkerFlags[:])
      for def in info.cDefines {
        append(&compilerFlags, "-D", def)
      }

      for inc in info.includePaths {
        var, ok := format_variable(presetDefines, inc, "include paths")
        if !ok { return false }
        append(&compilerFlags, "-I", var)
        append(&includePaths, var)
      }

      for src in info.sources {
        var, ok := format_variable(presetDefines, src, "source files")
        if !ok { return false }
        append(&sources, var)
      }
    }

    // step 3: Compile!
    cmd := make([dynamic]string, context.temp_allocator)
    append(&cmd, fmt.tprintf("{:s}gcc", toolchainPrefix))
    append(&cmd, "-c")
    append(&cmd, ..compilerFlags[:])
    if targetMode == "Debug" {
      append(&cmd, "-g")
    } else if targetMode == "Release" {
      append(&cmd, "-O3")
    } else if targetMode == "RelWithDebInfo" {
      append(&cmd, "-g", "-O3")
    }

    parallel := false

    ok: bool
    outputFiles: []string
    if parallel {
      outputFiles, ok = build_objects_parallel(&cmd, binaryDir, includePaths[:], sources[:])
    } else {
      outputFiles, ok = build_objects_serial(&cmd, binaryDir, includePaths[:], sources[:])
    }

    clear(&cmd)
    append(&cmd, fmt.tprintf("{:s}gcc", toolchainPrefix))
    append(&cmd, "-o", "out/build/latest.elf")
    append(&cmd, ..outputFiles[:])
    append(&cmd, ..linkerFlags[:])

    if ok {
      // link
      ok = run_command(cmd[:]).exit_code == 0
    }

    if ok {
      print_note("Build success", .Ok)
    } else {
      print_note("Build fail", .Wrong)
    }
    return ok
  } else {
    fmt.eprintln("ERROR: Missing 'hyper-build.json' file")
    return false
  }
}
