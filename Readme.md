## HyperloopUPV Hyper utility

This is a utility program to use for HyperloopUPV Firmware subsystem

## Usage

```
hyper <command> [options]
```
Commmand can be any of ["init", "help", "version", "examples", "run", "build", "flash", "uart", "doctor", "hardfault-analysis", "stlib-build", "stlib-sim-tests"]

Use `hyper help <command>` to get usage of a specific command

Prebuilt binaries for macos arm64 and linux x64 and arm64 can be found [here](https://github.com/Hyperloop-UPV/Hyper-fw-cli/actions/workflows/build.yml)

### Building

Install odinlang if you don't have it: https://odin-lang.org/docs/install/

Alternatively, get the latest release with `get-odin-latest.py`

windows: **From this directory**, run
```
odin build . -out:hyper.exe -o:speed
```

linux/macos: **From this directory**, run
```
odin build . -out:hyper -o:speed
```
