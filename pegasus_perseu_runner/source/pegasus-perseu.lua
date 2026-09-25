#!/usr/bin/env lua

-- pegasus-perseu: lifecycle manager for Pegasus.lua web applications
-- A contribution to the Pegasus.lua community.
-- Usage: pegasus-perseu  (run from the application folder)
-- audit:v7(adjusts|bugged.version)
-- ============================================================
-- ANSI colors (compatible with Lua 5.1 → 5.5, no \x)
-- ============================================================
local C = {
    reset   = "\27[0m",
    red     = "\27[1;31m",
    green   = "\27[1;32m",
    yellow  = "\27[1;33m",
    cyan    = "\27[1;36m",
    blue    = "\27[1;34m",
    dim     = "\27[2;37m",
    bold    = "\27[1m",
}

-- ============================================================
-- Helpers (declared before use)
-- ============================================================
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sanitize_path(p)
    if not p or p == "" then return nil end
    if not p:match("^[%w_%.%-/\\:]+$") then return nil end
    return p
end

local function sanitize_home_path(p)
    if not p or p == "" then return nil end
    if p:find("[;`$&|<>%z\"']") then return nil end
    return p
end

-- ============================================================
-- Platform detection
-- ============================================================
local IS_WINDOWS = (package.config:sub(1, 1) == "\\")
local IS_MACOS   = false
if not IS_WINDOWS then
    local f = io.popen("uname -s 2>/dev/null")
    if f then
        local os_name = f:read("*l") or ""
        f:close()
        IS_MACOS = (os_name == "Darwin")
    end
end

local LOG_PATH
if IS_WINDOWS then
    local tmp = sanitize_path(os.getenv("TEMP"))
             or sanitize_path(os.getenv("TMP"))
             or "."
    LOG_PATH = tmp .. "\\pegasus-perseu.log"
else
    LOG_PATH = "/tmp/pegasus-perseu.log"
end

-- ============================================================
-- Runtime state
-- ============================================================
local server_pid = nil
local app_file   = nil
local app_port   = nil

-- ============================================================
-- Helpers (continued)
-- ============================================================
local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local c = f:read("*all")
    f:close()
    return c
end

local function uses_pegasus(path)
    local content = read_file(path)
    if not content then return false end
    return content:match("require%s*%(%s*[\"']pegasus") ~= nil
end

local function read_port(path)
    local content = read_file(path)
    if not content then return nil end

    content = content:gsub("%-%-%[%[.-%]%]", "")

    for line in content:gmatch("[^\r\n]+") do
        local l = trim(line)
        if l:sub(1, 2) ~= "--" then
            local port = l:match("port%s*=%s*(%d+)")
            if port then return tonumber(port) end
            port = l:match("port%s*=%s*tonumber%s*%([^)]*%)%s*or%s*(%d+)")
            if port then return tonumber(port) end
        end
    end

    return nil
end

local function sanitize_arg(s)
    if not s or s == "" then return nil end
    if not s:match("^[%w_%.%-/]+$") then return nil end
    return s
end

local function sanitize_port(p)
    local n = tonumber(p)
    if not n then return nil end
    if n < 1 or n > 65535 then return nil end
    return n
end

local function get_cwd()
    if IS_WINDOWS then
        local f = io.popen("cd 2>nul")
        if f then
            local cwd = f:read("*l") or "."
            f:close()
            return cwd
        end
        return "."
    end
    return os.getenv("PWD") or "."
end

local function get_home()
    if IS_WINDOWS then
        local home = sanitize_home_path(os.getenv("USERPROFILE"))
        if home then return home end
        local drive = sanitize_home_path(os.getenv("HOMEDRIVE"))
        local path  = sanitize_home_path(os.getenv("HOMEPATH"))
        if drive and path then return drive .. path end
        return nil
    end
    return sanitize_home_path(os.getenv("HOME"))
end

local function is_root()
    if IS_WINDOWS then return false end
    local f = io.popen("id -u 2>/dev/null")
    if not f then return false end
    local uid = trim(f:read("*l") or "")
    f:close()
    return uid == "0"
end

-- ============================================================
-- Allowlist: CWD must be inside the user's home directory
-- ============================================================
local function is_inside_home(cwd)
    local home = get_home()
    if not home then
        return false, "cannot determine user home directory"
    end

    local cwd_n  = cwd:gsub("\\", "/")
    local home_n = home:gsub("\\", "/")

    if IS_WINDOWS then
        cwd_n  = cwd_n:lower()
        home_n = home_n:lower()
    end

    if home_n:sub(-1) ~= "/" then home_n = home_n .. "/" end
    if cwd_n:sub(-1)  ~= "/" then cwd_n  = cwd_n  .. "/" end

    if cwd_n == home_n then return true end
    if cwd_n:sub(1, #home_n) == home_n then return true end

    return false, home
end

-- ============================================================
-- ASCII art + headers
-- ============================================================
local function print_logo()
    print(C.cyan .. [[                                    
▛▌█▌▛▌▀▌▛▘▌▌▛▘▄▖▛▌█▌▛▘▛▘█▌▌▌▄▖▛▘▛▘▌▌
▙▌▙▖▙▌█▌▄▌▙▌▄▌  ▙▌▙▖▌ ▄▌▙▖▙▌  ▄▌▌ ▚▘
▌   ▄▌          ▌                   
]] .. C.reset)
    print()
end

local function print_server_header()
    print(C.bold .. "🚀 " .. (app_file or "pegasus app") .. C.reset)
    print(C.green .. "✅ Server running at " .. C.reset
        .. C.blue .. "http://localhost:" .. app_port .. C.reset)
    print(C.yellow .. "🛑 type --stop to stop app/server." .. C.reset)
    print()
end

local function print_prompt_header()
    print("🐴🪽 " .. C.red .. "pegasus-perseu(v1.0.0):" .. C.reset
        .. " -h/-help/--help")
end

local function print_prompt()
    io.write(C.cyan .. "\n@pegasus-perseu~>" .. C.reset .. " ")
    io.flush()
end

-- ============================================================
-- Start / Stop (platform-aware)
-- ============================================================
local function start_server()
    if server_pid then
        print(C.yellow .. "⚠ server already running (pid=" .. server_pid .. ")" .. C.reset)
        return
    end

    local safe_app = sanitize_arg(app_file)
    if not safe_app then
        print(C.red .. "❌ invalid application file name" .. C.reset)
        return
    end

    local cmd

    if IS_WINDOWS then
        cmd = 'powershell -NoProfile -Command "' ..
            '$p = Start-Process -FilePath lua ' ..
            '-ArgumentList \'' .. safe_app .. '\' ' ..
            '-RedirectStandardOutput \'' .. LOG_PATH .. '\' ' ..
            '-RedirectStandardError \'' .. LOG_PATH .. '\' ' ..
            '-WindowStyle Hidden -PassThru; ' ..
            'Write-Output $p.Id"'

    elseif IS_MACOS then
        cmd = "umask 077; lua " .. safe_app
            .. " > " .. LOG_PATH .. " 2>&1 < /dev/null & echo $!"

    else
        cmd = "umask 077; setsid lua " .. safe_app
            .. " > " .. LOG_PATH .. " 2>&1 < /dev/null & echo $!"
    end

    local handle = io.popen(cmd)
    if not handle then
        print(C.red .. "❌ failed to spawn " .. safe_app .. C.reset)
        return
    end
    local raw = handle:read("*a") or ""
    handle:close()

    raw = trim(raw)

    if not raw:match("^%d+$") then
        print(C.red .. "❌ failed to capture server PID" .. C.reset)
        return
    end

    server_pid = tonumber(raw)
    print(C.green .. "✅ Server started" .. C.reset)
    print()
end

-- Kill the entire process group (setsid leader + children) on POSIX.
-- This prevents orphaned `lua` processes from holding the port after
-- --stop or exit. On Windows, PowerShell targets the exact PID.
local function kill_app()
    if not server_pid then return end

    if IS_WINDOWS then
        os.execute('powershell -NoProfile -Command "Stop-Process -Id '
            .. server_pid .. ' -Force" 2>nul')
    else
        -- Negative PID: kill the whole process group (setsid session).
        -- Positive PID: fallback in case the process is not a group leader.
        os.execute("kill -TERM -" .. server_pid .. " 2>/dev/null")
        os.execute("kill -TERM "  .. server_pid .. " 2>/dev/null")
    end
end

local function stop_server()
    if not server_pid then
        print(C.yellow .. "⚠ server is not running" .. C.reset)
        return
    end

    kill_app()
    server_pid = nil
    print(C.red .. "🛑 server stopped" .. C.reset)
    print()
end

-- ============================================================
-- Commands
-- ============================================================
local function cmd_help()
    print(C.bold .. "Available commands:" .. C.reset)
    print("  --start               :start app/server")
    print("  --stop                :stop app/server (keeps pegasus-perseu alive)")
    print("  --log                 :show application log")
    print("  exit                  :stop app/server and close pegasus-perseu")
    print("  -h / -help / --help   :show this message")
    print()
end

local function cmd_log()
    print("🐴🪽 " .. C.green .. "local application(user):" .. C.reset
        .. " " .. (app_file or "?"))
    print("📅 " .. os.date("%Y-%m-%d %H:%M:%S"))
    print()

    local content = read_file(LOG_PATH)
    if not content then
        print(C.dim .. "(no log yet)" .. C.reset)
        return
    end
    io.write(content)
    if content:sub(-1) ~= "\n" then print() end
end

local function cmd_exit()
    if server_pid then
        kill_app()
        server_pid = nil
    end
    print(C.dim .. "👋 closing pegasus-perseu" .. C.reset)
    os.exit(0)
end

-- ============================================================
-- Command loop
-- ============================================================
local function loop()
    while true do
        print_prompt()
        local line = io.read("*l")
        if not line then
            cmd_exit()
        end

        if trim(line) == "" then
            -- ignore

        elseif line:find("%s") then
            local cleaned = trim(line)
            local is_command = cleaned == "--start" or cleaned == "--stop"
                or cleaned == "--log" or cleaned == "exit"
                or cleaned == "-h" or cleaned == "-help" or cleaned == "--help"
            if is_command then
                print(C.red .. "❌ invalid command: avoid typing spaces when entering commands" .. C.reset)
            else
                print(C.red .. "❌ unknown command: " .. cleaned .. C.reset)
                print(C.dim .. "   type -h for available commands" .. C.reset)
            end

        elseif line == "--start" then
            start_server()
        elseif line == "--stop" then
            stop_server()
        elseif line == "--log" then
            cmd_log()
        elseif line == "exit" then
            cmd_exit()
        elseif line == "-h" or line == "-help" or line == "--help" then
            cmd_help()
        else
            print(C.red .. "❌ unknown command: " .. line .. C.reset)
            print(C.dim .. "   type -h for available commands" .. C.reset)
        end
    end
end

-- ============================================================
-- Bootstrap
-- ============================================================
local function main()
    if is_root() then
        io.stderr:write(C.red
            .. "pegasus-perseu: refusing to run as root.\n"
            .. C.reset)
        io.stderr:write(C.dim
            .. "run as a regular user; the spawned application "
            .. "would inherit root privileges.\n" .. C.reset)
        os.exit(1)
    end

    local cwd = get_cwd()
    if cwd:sub(-1) ~= "/" and cwd:sub(-1) ~= "\\" then
        cwd = cwd .. (IS_WINDOWS and "\\" or "/")
    end

    local inside, home_or_err = is_inside_home(cwd)
    if not inside then
        io.stderr:write(C.red
            .. "pegasus-perseu: refusing to run outside the user's home directory.\n"
            .. C.reset)
        io.stderr:write(C.dim
            .. "current: " .. cwd .. "\n"
            .. "expected home: " .. tostring(home_or_err) .. "\n"
            .. "the project must live inside the user folder "
            .. "(e.g. /home/<user>/... or C:\\Users\\<user>\\...).\n"
            .. C.reset)
        os.exit(1)
    end

    local candidates = { "server.lua", "app.lua", "main.lua", "api.lua" }
    local found = nil

    for _, name in ipairs(candidates) do
        if file_exists(name) and uses_pegasus(name) then
            found = name
            break
        end
    end

    if not found then
        io.stderr:write(C.red
            .. "pegasus-perseu: no Pegasus.lua web application found "
            .. "in the current folder.\n" .. C.reset)
        io.stderr:write(C.dim
            .. "Looked for: server.lua, app.lua, main.lua, api.lua "
            .. "(must require \"pegasus\")\n" .. C.reset)
        os.exit(1)
    end

    local port = read_port(found)
    app_port = sanitize_port(port)

    if not app_port then
        io.stderr:write(C.red .. "🚫 "
            .. "pegasus-perseu: the application does not declare a port.\n"
            .. C.reset)
        io.stderr:write(C.dim
            .. "add an explicit line like  port = 5600  to: "
            .. found .. "\n" .. C.reset)
        os.exit(1)
    end

    io.write(C.yellow
        .. "there is a pegasus web application in file: "
        .. found .. ", would you like to start this application? [y/N] "
        .. C.reset)
    io.flush()
    local answer = trim(io.read("*l") or ""):lower()
    if answer ~= "y" and answer ~= "yes" then
        print(C.dim .. "👋 nothing to do, closing pegasus-perseu" .. C.reset)
        os.exit(0)
    end

    app_file = found

    print_logo()
    print_server_header()
    print_prompt_header()

    start_server()

    loop()
end

main()