# Changelog

All notable changes to **pegasus-perseu** are documented in this file.

The format is based on Keep a Changelog
(https://keepachangelog.com/en/1.1.0/),
and this project adheres to Semantic Versioning
(https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-09-24

First public release. A community contribution to the Pegasus.lua
ecosystem.

### Added

- **Lifecycle management** for Pegasus.lua web applications running from
  the current folder:
  - `--start` — spawn the application and capture its PID.
  - `--stop` — terminate the application's process group, keeping the
    runner alive.
  - `--log` — display the application log.
  - `exit` — terminate the application and close the runner.
  - `-h` / `-help` / `--help` — display available commands.

- **Application auto-detection** in the current folder, in order:
  `server.lua`, `app.lua`, `main.lua`, `api.lua`. A file is only
  considered if its content matches `require("pegasus")` or
  `require('pegasus')`.

- **Port extraction** from the application file, supporting two patterns:
  - `port = 5600`
  - `port = tonumber(os.getenv("PORT")) or 5600`

  Lines inside block comments (`--[[ ... ]]`) and line comments (`--`)
  are ignored during extraction.

- **Interactive prompt** with ANSI colors and emoji, hinting at the help
  command (`-h / -help / --help`) on entry.

- **Confirmation prompt** before starting an application:
  `there is a pegasus web application in file: <name>, would you like to
  start this application? [y/N]`

- **Strict command parsing**: every command must be typed alone, with no
  leading, trailing, or internal whitespace. The parser distinguishes
  two rejection cases:
  - Combined or space-padded commands that match a known verb
    (e.g. `--stop -h`, `--stop `) → rejected with
    `invalid command: avoid typing spaces when entering commands`.
  - Inputs that do not match any known command (e.g. `xyz`) → rejected
    with `unknown command: <input>`.

- **Cross-platform process handling**:
  - **Linux** — `setsid` + `$!` for PID capture; `kill -TERM -PID`
    (process group) with a `kill -TERM PID` fallback for cleanup.
  - **macOS** — `&` + `$!` for PID capture (no `setsid` available by
    default); `kill -TERM -PID` with a `kill -TERM PID` fallback.
  - **Windows** — `powershell Start-Process -PassThru` for exact PID
    capture; `Stop-Process -Id <PID> -Force` for targeted termination.
    Only the child process spawned by the runner is killed.

- **Process group termination** on POSIX systems: `--stop` and `exit`
  terminate the entire process group (`kill -TERM -PID`, note the
  leading minus), guaranteeing that no orphaned `lua` process is left
  holding the port.

- **Log file**:
  - POSIX: `/tmp/pegasus-perseu.log`
  - Windows: `%TEMP%\pegasus-perseu.log`
  - POSIX creation uses `umask 077`, so the file is created with
    permissions `600` (owner-only).

### Security

- **Home-only execution** — the current working directory must be inside
  the user's home folder:
  - `/home/<user>/` on Linux
  - `/Users/<user>/` on macOS
  - `C:\Users\<user>\` on Windows

  Anywhere else is refused with an explanatory message.

- **Refuses to run as root** on Linux and macOS. The spawned application
  would inherit root privileges otherwise.

- **Input sanitization** for every string that reaches a shell command:
  - `sanitize_arg` — application file name restricted to
    `[A-Za-z0-9_./-]`.
  - `sanitize_port` — port must be an integer between 1 and 65535.
  - `sanitize_path` — `TEMP` / `TMP` values restricted to
    `[A-Za-z0-9_./\\:]`.
  - `sanitize_home_path` — `HOME` / `USERPROFILE` / `HOMEDRIVE` /
    `HOMEPATH` values reject shell metacharacters (`;`, backtick, `$`,
    `&`, `|`, `<`, `>`, NUL, `"`, `'`).

- **Isolated child process** — only the process spawned by the runner is
  terminated on `--stop` or `exit`. Other Lua processes on the system
  are untouched (unlike `pkill lua`).

- **No dynamic code loading** — the runner never uses `dofile`, `load`,
  `loadstring`, or any dynamic evaluation of user input.

- **Port requirement** — the runner refuses to start an application that
  does not declare an explicit port. Prevents the runner from reporting
  a false "Server running at http://localhost:0" header.

### Known limitations

- **Block comment stripping** — `read_port` removes `--[[ ... ]]` blocks
  with a single regex pass. Nested or multi-level long comments
  (`--[==[ ... ]==]`) are not fully handled.

- **macOS process survival** — without `setsid`, the child may receive
  `SIGHUP` if the parent terminal is closed. For durable background
  execution, install `luaposix` and use `posix.fork()` +
  `posix.setsid()`.

- **Windows PID capture** — depends on PowerShell being available. On
  Windows 10 and later it ships by default; older Windows versions may
  require a manual install.

### Notes

- Designed for **Lua 5.3 or newer** (compatible with 5.4 and 5.5).
- Requires **Pegasus.lua** installed via LuaRocks
  (`luarocks install pegasus`).
- No HTTP server is started by the runner itself. It only manages the
  lifecycle of the Pegasus application.
- Not responsible for application-level security (XSS, injection,
  authentication). Its scope is process lifecycle and self-protection
  against command injection.
