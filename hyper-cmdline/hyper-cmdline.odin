#+vet style
#+vet unused
#+vet shadowing
package hyper_cmdline

import "core:os"
import "core:fmt"
import "core:flags"

Hyper_Command :: enum {
  init,
  help,
  examples,
  run,
  build,
  flash,
  uart,
  doctor,
  hardfault_analysis,
  stlib_build,
  stlib_sim_tests,
}

Hyper_FlashMethod :: enum {
  auto = 0,
  stm32prog,
  openocd,
}

Hyper_UartTool :: enum {
  auto = 0,
  tio,
  cu,
}

Hyper_StlibPreset :: enum {
  simulator = 0,
}

Hyper_FlagStyle :: flags.Parsing_Style.Unix

Hyper_HelpCommand :: struct {
  command: string `args:"pos=0" usage:"Hyper command to get help for, can be any of ['init', 'help', 'examples', 'run', 'build', 'flash', 'uart', 'doctor', 'hardfault-analysis', 'stlib-build', 'stlib-sim-tests']"`,
}

Hyper_ExamplesSubcommand :: enum {
  list,
  tests,
}

Hyper_ExamplesCommand :: struct {
  subcommand: Hyper_ExamplesSubcommand `args:"pos=0" usage:"Hyper subcommand e.g. examples 'list' or examples 'tests'"`,
  example: string `usage:"Example to build, required when using Hyper tests"`,
}

Hyper_BuildCommand :: struct {
  example: string `usage:"Example to build, e.g. adc"`,
  test: string `usage:"Test selector, e.g. 0, 1 or TEST_1"`,
  no_test: bool `usage:"Do not inject any TEST_* macro"`,
  preset: string `usage:"ST-LIB preset to build"`,
  board_name: string `usage:"Override BOARD_NAME for code generation"`,
  jobs: int `usage:"Set CMAKE_BUILD_PARALLEL_LEVEL"`,
  extra_cxx_flags: string `usage:"Extra c++ flags appended after the injected defines, this should be the last flag to be able to use more than one."`,
  overflow: [dynamic]string `usage:"Any extra arguments go here. Used for extra-cxx-flags"`,
}

Hyper_FlashCommand :: struct {
  elf: string `usage:"Elf image to flash. LATEST_ELF is default"`,
  method: Hyper_FlashMethod `usage:"Flash tool selection"`,
  no_verify: bool `usage:"Skip flash verification when supported"`,
  skip_preflight: bool `usage:"Skip tools/preflash_check.py before flashing"`,
}

Hyper_RunCommand :: struct {
  // build
  example: string `usage:"Example to build, e.g. adc"`,
  test: string `usage:"Test selector, e.g. 0, 1 or TEST_1"`,
  no_test: bool `usage:"Do not inject any TEST_* macro"`,
  preset: string `usage:"ST-LIB preset to build"`,
  board_name: string `usage:"Override BOARD_NAME for code generation"`,
  jobs: int `usage:"Set CMAKE_BUILD_PARALLEL_LEVEL"`,

  // flash
  elf: string `usage:"Elf image to flash. LATEST_ELF is default"`,
  method: Hyper_FlashMethod `usage:"Flash tool selection"`,
  no_verify: bool `usage:"Skip flash verification when supported"`,
  skip_preflight: bool `usage:"Skip tools/preflash_check.py before flashing"`,

  // uart
  uart: bool `usage:"Open UART after flashing"`,
  port: string `usage:"Serial port path or 'auto'"`,
  baud: int `usage:"UART baud rate"`,
  uart_tool: Hyper_UartTool `usage:"Serial terminal program"`,

  extra_cxx_flags: string `usage:"Extra c++ flags appended after the injected defines, this should be the last flag to be able to use more than one."`,
  overflow: [dynamic]string `usage:"Any extra arguments go here. Used for extra-cxx-flags"`,
}

Hyper_UartCommand :: struct {
  list_ports: bool `usage:"List candidate serial ports and exit"`,
  port: string `usage:"Serial port path or 'auto'"`,
  baud: int `usage:"UART baud rate"`,
  uart_tool: Hyper_UartTool `usage:"Serial terminal program"`,
}

Hyper_StlibBuildCommand :: struct {
  preset: string `args:"required" usage:"ST-LIB build preset for cmake"`,
  run_tests: bool `usage:"Run tests after build"`,
}

Hyper_Options :: struct {
  command: Hyper_Command,
  using info: struct #raw_union {
    // Hyper_CommandInfoInit (has no fields)
    help: Hyper_HelpCommand,
    examples: Hyper_ExamplesCommand,
    build: Hyper_BuildCommand,
    flash: Hyper_FlashCommand,
    uart: Hyper_UartCommand,
    // Hyper_DoctorCommand (has no fields)
    run: Hyper_RunCommand,
    // Hyper_HardfaultAnalysisCommand (has no fields)
    stlib_build: Hyper_StlibBuildCommand,
    // Hyper_StlibSimTests (has no fields)
  },
}

get_command :: proc(cmd: string, command: ^Hyper_Command) -> bool
{
  switch cmd {
    case "init":               command^ = .init
    case "help":               command^ = .help
    case "examples":           command^ = .examples
    case "run":                command^ = .run
    case "build":              command^ = .build
    case "flash":              command^ = .flash
    case "uart":               command^ = .uart
    case "doctor":             command^ = .doctor
    case "hardfault-analysis": command^ = .hardfault_analysis
    case "stlib-build":        command^ = .stlib_build
    case "stlib-sim-tests":    command^ = .stlib_sim_tests
    case: return false
  }
  return true
}

print_usage :: proc()
{
  fmt.printfln("Usage: %s <command> [options]", os.args[0])
  fmt.println(`Commands can be any of ["init", "help", "examples", "run", "build", "flash", "uart", "doctor", "hardfault-analysis", "stlib-build", "stlib-sim-tests"]`)
  fmt.printfln("Use '%s help <command>' to get usage of a specific command", os.args[0])
}

handle_help_command :: proc(help: Hyper_HelpCommand)
{
  req := flags.Help_Request(true)
  usage := fmt.tprintf("%s %s", os.args[0], help.command)
  switch help.command {
    case "init": {
      fmt.println("Setup the repository")
      fmt.printfln("Usage:\n\t%s", usage)
    }

    case "help": {
      fmt.println("Get help for a specific command")
      flags.print_errors(Hyper_HelpCommand, req, usage, Hyper_FlagStyle)
    }

    case "examples": {
      fmt.println("Inspect available examples")
      flags.print_errors(Hyper_ExamplesCommand, req, usage, Hyper_FlagStyle)
    }

    case "build": {
      fmt.println("Build a firmware target")
      flags.print_errors(Hyper_BuildCommand, req, usage, Hyper_FlagStyle)
    }

    case "flash": {
      fmt.println("Flash an ELF image onto the board")
      flags.print_errors(Hyper_FlashCommand, req, usage, Hyper_FlagStyle)
    }

    case "uart": {
      fmt.println("Open the board UART")
      flags.print_errors(Hyper_UartCommand, req, usage, Hyper_FlagStyle)
    }

    case "doctor": {
      fmt.println("Show tool and serial-port availability")
      fmt.printfln("Usage:\n\t%s", usage)
    }

    case "run": {
      fmt.println("Build then flash one firmware target")
      flags.print_errors(Hyper_RunCommand, req, usage, Hyper_FlagStyle)
    }

    case "hardfault-analysis": {
      fmt.printfln("Usage:\n\t%s", usage)
    }

    case "stlib-build": {
      fmt.println("Build ST-LIB and other helper flows")
      flags.print_errors(Hyper_StlibBuildCommand, req, usage, Hyper_FlagStyle)
    }

    case "stlib-sim-tests": {
      fmt.printfln("Usage:\n\t%s stlib-sim-tests", os.args[0])
    }
  
    case: {
      if help.command != "" {
        fmt.printfln("Unknown help command %s", help.command)
        handle_help_command({command = "help"})
      } else {
        print_usage()
      }
    }
  }
}

parse_single_command :: proc(args: []string, $T: typeid, data: ^T, pgm: string) -> bool
{
  argerr := flags.parse(data, args, Hyper_FlagStyle)
  if argerr != nil {
    flags.print_errors(T, argerr, pgm, Hyper_FlagStyle)
    return false
  }
  return true
}

parse :: proc(opt: ^Hyper_Options) -> bool
{
  args := os.args
  if len(args) < 2 {
    fmt.eprintfln("Missing a command")
    print_usage()
    return false
  }

  if !get_command(args[1], &opt.command) {
    print_usage()
    return false
  }

  args = args[2:]
  pgm := fmt.tprintf("%s %s", os.args[0], opt.command)
  ok: bool = true
  switch opt.command {
    // NOTE: nothing to parse on these
    case .init: {}
    case .hardfault_analysis: {}
    case .stlib_sim_tests: {}
    case .doctor: {}

    case .help: ok = parse_single_command(args, Hyper_HelpCommand, &opt.info.help, pgm)
    case .examples: ok = parse_single_command(args, Hyper_ExamplesCommand, &opt.info.examples, pgm)
    case .run: ok = parse_single_command(args, Hyper_RunCommand, &opt.info.run, pgm)
    case .build: ok = parse_single_command(args, Hyper_BuildCommand, &opt.info.build, pgm)
    case .flash: ok = parse_single_command(args, Hyper_FlashCommand, &opt.info.flash, pgm)
    case .uart: ok = parse_single_command(args, Hyper_UartCommand, &opt.info.uart, pgm)
    case .stlib_build: ok = parse_single_command(args, Hyper_StlibBuildCommand, &opt.info.stlib_build, pgm)

    case: unreachable()
  }

  return ok
}
