# pegasus-perseu

A lifecycle manager for Pegasus.lua web applications.

`pegasus-perseu` is a small CLI runner that starts, stops, and monitors a
Pegasus.lua web application running from the current folder. It captures the
process ID, shows the port it is serving on, streams the application log, and
shuts the process down cleanly on demand.

Built with **Lua 5.3+** in mind, and tested on Linux, macOS, and Windows.

---

## Why

Pegasus.lua is a lightweight HTTP server — it does not ship with a process
manager, and stopping it via `Ctrl+C` requires pressing it twice.
`pegasus-perseu` fills that gap: it spawns the application as a child process,
captures its PID, and gives you a clean REPL to control it.

It is a community contribution to the Pegasus.lua ecosystem.

---

## Features

- Auto-detects the Pegasus web application in the current folder.
- Reads and displays the port the application serves on.
- Starts and stops the application without touching the rest of your system.
- Streams the application log through `--log`.
- Cross-platform: Linux, macOS, Windows.
- Security hardened: refuses to run as root, restricts execution to the user's
  home directory, sanitizes every string that reaches a shell command.

---

## Requirements

- **Lua 5.3 or newer** (also compatible with 5.4 and 5.5).
- **Pegasus.lua** installed (`luarocks install pegasus`).
- On Windows: **PowerShell** (ships with Windows 10+).

---

## Installation

### Option 1 — Run as a Lua script

Copy `pegasus-perseu.lua` anywhere in your `PATH` and make it executable:

    chmod +x pegasus-perseu.lua
    mv pegasus-perseu.lua ~/.local/bin/pegasus-perseu

Run it with the Lua interpreter:

    lua ~/.local/bin/pegasus-perseu

### Option 2 — Compile to a standalone binary (recommended)

`luastatic` bundles the Lua runtime and your script into a single executable.
The result runs on machines without Lua installed.

**Prerequisites:**

- `luastatic` (`luarocks install luastatic`)
- Lua static library and headers (see the section below per platform)

**Linux (Debian/Ubuntu/Mint):**

    sudo apt install liblua5.3-dev

**macOS (Homebrew):**

    brew install lua

**Windows:** use a MinGW toolchain (MSYS2) with the Lua source compiled as a
static library.

**Compile:**

    luastatic pegasus-perseu.lua \
      /usr/lib/x86_64-linux-gnu/liblua5.3.a \
      -I/usr/include/lua5.3 \
      -o pegasus-perseu

Adjust the library and header paths to match your system.
On macOS with Homebrew:

    luastatic pegasus-perseu.lua \
      /opt/homebrew/lib/liblua.a \
      -I/opt/homebrew/include/lua \
      -o pegasus-perseu

The resulting `pegasus-perseu` binary has no external dependencies — Lua is
embedded.

---

### Adding to PATH

**Linux / macOS:**

Add the folder that contains the binary to your `PATH` by appending one line
to your shell profile.

For Bash (`~/.bashrc` or `~/.bash_profile`):

    export PATH="$PATH:$HOME/.local/bin"

For Zsh (`~/.zshrc`, default on macOS):

    export PATH="$PATH:$HOME/.local/bin"

Then reload the profile:

    source ~/.bashrc      # or ~/.zshrc

Confirm it works:

    which pegasus-perseu

If the binary lives somewhere else (e.g. `~/bin`), replace `$HOME/.local/bin`
with the correct folder.

**Windows (PowerShell):**

Add the folder to the user-level PATH permanently:

    [Environment]::SetEnvironmentVariable(
      "Path",
      [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Tools\pegasus-perseu",
      "User"
    )

Replace `C:\Tools\pegasus-perseu` with the folder that contains
`pegasus-perseu.exe`.

Close and reopen the terminal, then confirm:

    where.exe pegasus-perseu

**Windows (CMD):**

    setx PATH "%PATH%;C:\Tools\pegasus-perseu"

Same note: replace the folder path, then open a new terminal window.

---

## Usage

Place `pegasus-perseu` inside the folder that contains your Pegasus web
application (a `.lua` file that calls `require("pegasus")`), then run it:

    pegasus-perseu

It will:

1. Check that the current directory is inside your home folder.
2. Look for a Pegasus web application (`server.lua`, `app.lua`, `main.lua`,
   or `api.lua`).
3. Ask for confirmation.
4. Start the application as a child process.
5. Show the port it is serving on.
6. Drop you into an interactive prompt.
```
    ┌─┐┌─┐┌─┐┌─┐┌─┐┬ ┬┌─┐   ┌─┐┬─┐┬  ┬
    ├─┘├┤ │ ┬├─┤└─┐│ │└─┐───└─┐├┬┘└┐┌┘
    ┴  └─┘└─┘┴ ┴└─┘└─┘└─┘   └─┘┴└─ └┘

    🚀 server.lua
    ✅ Server running at http://localhost:5600
    🛑 type --stop to stop app/server.

    🐴🪽 pegasus-perseu(v1.0.0): -h/-help/--help

    @pegasus-perseu~>
```
### Commands

| Command                   | Description                                      |
| ------------------------- | ------------------------------------------------ |
| `--start`                 | Start the application (already started on boot)  |
| `--stop`                  | Stop the application (keeps the runner alive)    |
| `--log`                   | Show the application log                         |
| `exit`                    | Stop the application and close the runner        |
| `-h` / `-help` / `--help` | Show available commands                          |

### Example session

    @pegasus-perseu~> --log
    🐴🪽 local application(user): server.lua
    📅 2026-09-24 10:58:56

    Pegasus is up on 0.0.0.0:5600
    [2026-09-24 10:58:56] GET - /
    [2026-09-24 10:58:57] GET - /favicon.ico

    @pegasus-perseu~> --stop
    🛑 server stopped

    @pegasus-perseu~> --start
    ✅ Server started

    @pegasus-perseu~> exit
    👋 closing pegasus-perseu

---

## Security

`pegasus-perseu` spawns a subprocess and interacts with the shell, so it
enforces several safety guarantees:

- **Home-only execution.** The current working directory must be inside the
  user's home folder (`/home/<user>/`, `/Users/<user>/`, or
  `C:\Users\<user>\`). Running from anywhere else is refused.
- **No root.** The runner refuses to execute as root on Linux and macOS. The
  spawned application would inherit root privileges otherwise.
- **Input sanitization.** Every string that reaches a shell command is
  validated against a strict allowlist. `TEMP`, `TMP`, and `HOME` are
  sanitized before use.
- **Isolated child process.** Only the specific child process spawned by the
  runner is terminated on `--stop` or `exit`. Other Lua processes on the
  system are untouched.
- **Restricted log file.** On POSIX systems, the log is created with
  `umask 077` (mode `600`), readable only by the owner.

---

## Platform notes

| Platform | Start method                           | Stop method                            |
| -------- | -------------------------------------- | -------------------------------------- |
| Linux    | `setsid` + `$!` PID capture            | `kill <PID>`                           |
| macOS    | `&` + `$!` PID capture (no `setsid`)   | `kill <PID>`                           |
| Windows  | `Start-Process -PassThru` (PowerShell) | `Stop-Process -Id <PID>` (PowerShell)  |

**macOS without `setsid`:** the child process may receive `SIGHUP` if the
parent terminal is closed. If the application must survive terminal closure,
install `luaposix` and use `posix.fork()` + `posix.setsid()`.

**Windows PID capture:** Windows does not expose child PIDs through
`cmd.exe`. `pegasus-perseu` uses PowerShell's `Start-Process -PassThru` to
capture the exact `lua.exe` PID, and `Stop-Process -Id` to terminate only
that process.

---

## How it detects the application

`pegasus-perseu` scans the current folder for one of these filenames, in
order:

1. `server.lua`
2. `app.lua`
3. `main.lua`
4. `api.lua`

It picks the first one whose content matches `require("pegasus")` or
`require('pegasus')`. If none match, it exits with a clear message.

The port is extracted from the application file by looking for either:

    port = 5600

or

    port = tonumber(os.getenv("PORT")) or 5600

If no port is found, `pegasus-perseu` displays `0` in the header. The
application itself is still started — the port shown is informational.

---

## Contributing

This is a community contribution to the Pegasus.lua ecosystem. Issues and
pull requests are welcome.

- Feedback and bug reports: open an issue.
- Feature requests: describe the use case.

The intent is to fill a real gap in the Pegasus.lua tooling — clean process
lifecycle, cross-platform — without altering the server internals.

---

## License

MIT.
