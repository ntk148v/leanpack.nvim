# Leanpack Review Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the highest-impact correctness, security, reliability, and startup-performance issues found in the leanpack.nvim code review while preserving the existing public `require("leanpack").setup(...)` API.

**Architecture:** Keep `vim.pack` as the package backend and improve leanpack's orchestration around it. Add small internal helpers for safe filesystem sourcing and persistent cache metadata, make dependency resolution fail-fast, make lazy trigger replay more faithful, and ensure background install/update runs build hooks in the parent process.

**Tech Stack:** Lua 5.1/LuaJIT, Neovim 0.12 APIs, `vim.pack`, `vim.uv`, `vim.system`, mini.test child Neovim test harness.

---

## File Structure

- Modify: `lua/leanpack/deps.lua` for fail-fast cycle detection.
- Modify: `lua/leanpack/import.lua` for deterministic imports.
- Create: `lua/leanpack/fs.lua` for escaped file sourcing and directory helpers.
- Modify: `lua/leanpack/init.lua` to use filesystem helpers, avoid duplicate save autocmds, and run builds after background installs.
- Modify: `lua/leanpack/hooks.lua` to use `vim.system` for shell build hooks and expose build-by-pack helpers.
- Modify: `lua/leanpack/job.lua` to reject concurrent jobs.
- Modify: `lua/leanpack/lazy.lua` for command replay fidelity.
- Modify: `lua/leanpack/lazy_trigger/event.lua` and `lua/leanpack/lazy_trigger/util.lua` for narrow event replay.
- Modify: `lua/leanpack/lazy_trigger/keys.lua` and `lua/leanpack/keymap.lua` for better key option preservation and replay.
- Create: `lua/leanpack/cache.lua` for persistent cache records with invalidation stamps.
- Modify: `lua/leanpack/spec.lua` and `lua/leanpack/lazy_trigger/module.lua` to use cache stamps and reduce startup scans.
- Modify tests: `tests/deps_spec.lua`, `tests/spec_spec.lua`, `tests/lazy_spec.lua`, `tests/hooks_spec.lua`, `tests/job_spec.lua`, `tests/installation_spec.lua`, `tests/module_trigger_spec.lua`.
- Create tests: `tests/fs_spec.lua`, `tests/cache_spec.lua`.

## Task 1: Dependency Cycle Failure And Deterministic Imports

**Files:**

- Modify: `lua/leanpack/deps.lua`
- Modify: `lua/leanpack/import.lua`
- Test: `tests/deps_spec.lua`
- Test: `tests/spec_spec.lua`

- [ ] **Step 1: Add failing cycle tests**

Add to `tests/deps_spec.lua` under `T["toposort_startup()"]`:

```lua
T["toposort_startup()"]["fails fast with explicit cycle path"] = function()
    child.lua([[
        state.add_dependency("a", "b")
        state.add_dependency("b", "c")
        state.add_dependency("c", "a")

        _G.ok, _G.err = pcall(function()
            deps.toposort_startup({
                { src = "a", name = "a", data = { priority = 50 } },
                { src = "b", name = "b", data = { priority = 50 } },
                { src = "c", name = "c", data = { priority = 50 } },
            })
        end)
    ]])

    MiniTest.expect.equality(child.lua_get("_G.ok"), false)
    MiniTest.expect.equality(child.lua_get("_G.err"):match("Circular dependency: a %-> b %-> c %-> a") ~= nil, true)
end
```

- [ ] **Step 2: Add deterministic import test**

Add to `tests/spec_spec.lua` or a new `import_specs` test group if one exists:

```lua
T["import order"]["loads lua plugin files in sorted path order"] = function()
    child.lua([[
        local import = require("leanpack.import")
        local original_get_runtime_file = vim.api.nvim_get_runtime_file
        local required = {}

        vim.api.nvim_get_runtime_file = function(pattern, all)
            if pattern == "lua/plugins.lua" or pattern == "lua/plugins/init.lua" then
                return {}
            end
            if pattern == "lua/plugins/*.lua" then
                return {
                    "/tmp/nvim/lua/plugins/zeta.lua",
                    "/tmp/nvim/lua/plugins/alpha.lua",
                    "/tmp/nvim/lua/plugins/middle.lua",
                }
            end
            return {}
        end

        package.loaded["plugins.alpha"] = { "owner/alpha" }
        package.loaded["plugins.middle"] = { "owner/middle" }
        package.loaded["plugins.zeta"] = { "owner/zeta" }

        local original_require = require
        _G.require = function(name)
            table.insert(required, name)
            return package.loaded[name] or original_require(name)
        end

        import.import_specs("plugins", { import_order = 0, seen = {} })

        _G.required = required
        _G.require = original_require
        vim.api.nvim_get_runtime_file = original_get_runtime_file
    ]])

    MiniTest.expect.equality(child.lua_get("_G.required"), {
        "plugins.alpha",
        "plugins.middle",
        "plugins.zeta",
    })
end
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
./scripts/test tests/deps_spec.lua tests/spec_spec.lua
```

Expected: the new cycle test fails because no error is thrown; the import order test fails because `pairs(all_paths)` is nondeterministic.

- [ ] **Step 4: Implement fail-fast cycle detection**

Replace `M.toposort_startup` internals in `lua/leanpack/deps.lua` with DFS that tracks stack order and errors on cycles:

```lua
function M.toposort_startup(packs)
    local src_to_pack = {}
    for _, pack in ipairs(packs) do
        src_to_pack[pack.src] = pack
    end

    local in_progress = {}
    local done = {}
    local stack = {}
    local result = {}

    local function make_cycle(src)
        local start_idx = 1
        for i, item in ipairs(stack) do
            if item == src then
                start_idx = i
                break
            end
        end
        local cycle = {}
        for i = start_idx, #stack do
            table.insert(cycle, stack[i])
        end
        table.insert(cycle, src)
        return table.concat(cycle, " -> ")
    end

    local function visit(pack)
        if done[pack.src] then
            return
        end
        if in_progress[pack.src] then
            error(("Circular dependency: %s"):format(make_cycle(pack.src)))
        end

        in_progress[pack.src] = true
        table.insert(stack, pack.src)

        local deps = state.get_dependencies(pack.src)
        if deps then
            local dep_srcs = {}
            for dep_src in pairs(deps) do
                table.insert(dep_srcs, dep_src)
            end
            table.sort(dep_srcs)

            for _, dep_src in ipairs(dep_srcs) do
                local dep_pack = src_to_pack[dep_src]
                if dep_pack then
                    visit(dep_pack)
                end
            end
        end

        stack[#stack] = nil
        in_progress[pack.src] = nil
        done[pack.src] = true
        table.insert(result, pack)
    end

    table.sort(packs, function(a, b)
        local pa = (a.data and a.data.priority) or 50
        local pb = (b.data and b.data.priority) or 50
        if pa == pb then
            return a.src < b.src
        end
        return pa > pb
    end)

    for _, pack in ipairs(packs) do
        visit(pack)
    end

    return result
end
```

- [ ] **Step 5: Implement sorted imports**

Change `lua/leanpack/import.lua` to build a sorted path list before requiring modules:

```lua
local sorted_paths = {}
for path in pairs(all_paths) do
    table.insert(sorted_paths, path)
end
table.sort(sorted_paths)

for _, path in ipairs(sorted_paths) do
    local module_name = path:match("lua/(.+)%.lua$")
    if module_name then
        module_name = module_name:gsub("/", ".")
        module_name = module_name:gsub("%.init$", "")
    end

    if module_name then
        local ok, result = pcall(require, module_name)
        if ok then
            local file_specs = M.process_import_result(result, ctx)
            for _, spec in ipairs(file_specs) do
                spec._import_order = ctx.import_order
                ctx.import_order = ctx.import_order + 1
                table.insert(specs, spec)
            end
        end
    end
end
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
./scripts/test tests/deps_spec.lua tests/spec_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/deps.lua lua/leanpack/import.lua tests/deps_spec.lua tests/spec_spec.lua
git commit -m "fix: fail fast on dependency cycles"
```

## Task 2: Safe Filesystem Sourcing

**Files:**

- Create: `lua/leanpack/fs.lua`
- Modify: `lua/leanpack/init.lua`
- Test: `tests/fs_spec.lua`
- Test: `tests/installation_spec.lua`

- [ ] **Step 1: Add failing filesystem tests**

Create `tests/fs_spec.lua`:

```lua
local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
                vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
                _G.fs = require("leanpack.fs")
            ]])
        end,
        post_once = child.stop,
    },
})

T["source_ftdetect_dir()"] = MiniTest.new_set()

T["source_ftdetect_dir()"]["escapes paths with spaces and command separators"] = function()
    child.lua([[
        local commands = {}
        local original_cmd = vim.cmd
        vim.cmd = function(cmd)
            table.insert(commands, cmd)
        end

        local original_scandir = vim.uv.fs_scandir
        local original_next = vim.uv.fs_scandir_next

        vim.uv.fs_scandir = function(path)
            _G.scanned_path = path
            return true
        end

        local entries = {
            { "a file.lua", "file" },
            { "evil|echo.lua", "file" },
            { "skip.txt", "file" },
            { "b.vim", "file" },
        }
        local index = 0
        vim.uv.fs_scandir_next = function()
            index = index + 1
            local entry = entries[index]
            if not entry then
                return nil
            end
            return entry[1], entry[2]
        end

        fs.source_ftdetect_dir("/tmp/plugin path/ftdetect")

        _G.commands = commands
        vim.cmd = original_cmd
        vim.uv.fs_scandir = original_scandir
        vim.uv.fs_scandir_next = original_next
    ]])

    local commands = child.lua_get("_G.commands")
    MiniTest.expect.equality(#commands, 3)
    MiniTest.expect.equality(commands[1]:match("silent! source ") ~= nil, true)
    MiniTest.expect.equality(commands[1]:find("\\ ", 1, true) ~= nil, true)
    MiniTest.expect.equality(commands[2]:find("\\|", 1, true) ~= nil, true)
end

return T
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
./scripts/test tests/fs_spec.lua
```

Expected: FAIL because `leanpack.fs` does not exist.

- [ ] **Step 3: Implement filesystem helper**

Create `lua/leanpack/fs.lua`:

```lua
local M = {}

function M.is_dir(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory" or false
end

function M.source_ftdetect_dir(dir)
    local fd = vim.uv.fs_scandir(dir)
    if not fd then
        return
    end

    local files = {}
    while true do
        local name, type = vim.uv.fs_scandir_next(fd)
        if not name then
            break
        end
        if type == "file" or type == "link" then
            if name:match("%.vim$") or name:match("%.lua$") then
                table.insert(files, dir .. "/" .. name)
            end
        end
    end

    table.sort(files)
    for _, file in ipairs(files) do
        vim.cmd("silent! source " .. vim.fn.fnameescape(file))
    end
end

return M
```

- [ ] **Step 4: Replace unsafe ftdetect sourcing**

At the top of `lua/leanpack/init.lua`, add:

```lua
local fs = require("leanpack.fs")
```

Replace both duplicated blocks:

```lua
local ftdetect_dir = opt_path .. p.name .. "/ftdetect"
if vim.uv.fs_stat(ftdetect_dir) then
    vim.cmd("silent! source " .. ftdetect_dir .. "/*.vim")
    vim.cmd("silent! source " .. ftdetect_dir .. "/*.lua")
end
```

with:

```lua
local ftdetect_dir = opt_path .. p.name .. "/ftdetect"
if fs.is_dir(ftdetect_dir) then
    fs.source_ftdetect_dir(ftdetect_dir)
end
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
./scripts/test tests/fs_spec.lua tests/installation_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/fs.lua lua/leanpack/init.lua tests/fs_spec.lua tests/installation_spec.lua
git commit -m "fix: escape ftdetect sourcing paths"
```

## Task 3: Build Hook Execution And Parent-Process Build Recovery

**Files:**

- Modify: `lua/leanpack/hooks.lua`
- Modify: `lua/leanpack/init.lua`
- Modify: `lua/leanpack/commands.lua`
- Test: `tests/hooks_spec.lua`
- Test: `tests/installation_spec.lua`

- [ ] **Step 1: Add failing `vim.system` build test**

Add to `tests/hooks_spec.lua`:

```lua
T["execute_build()"]["runs shell build with vim.system in plugin cwd"] = function()
    child.lua([[
        local hooks = require("leanpack.hooks")
        local calls = {}

        local original_system = vim.system
        vim.system = function(cmd, opts)
            table.insert(calls, { cmd = cmd, opts = opts })
            return {
                wait = function()
                    return { code = 0, stdout = "ok", stderr = "" }
                end,
            }
        end

        hooks.execute_build("make install", {
            spec = { name = "plugin-a" },
            path = "/tmp/plugin-a",
        })

        _G.calls = calls
        vim.system = original_system
    ]])

    local calls = child.lua_get("_G.calls")
    MiniTest.expect.equality(#calls, 1)
    MiniTest.expect.equality(calls[1].opts.cwd, "/tmp/plugin-a")
    MiniTest.expect.equality(calls[1].opts.text, true)
end
```

- [ ] **Step 2: Add failing parent build recovery test**

Add to `tests/installation_spec.lua`:

```lua
T["Background Installation"]["runs build hooks in parent after missing plugin install succeeds"] = function()
    child.lua([[
        local leanpack = require("leanpack")
        local original_stat = vim.uv.fs_stat
        local original_job_run = require("leanpack.job").run
        local built = {}

        vim.uv.fs_stat = function(path)
            if path:match("build%-plugin$") then
                return nil
            end
            return { type = "directory" }
        end

        require("leanpack.job").run = function(kind, payload, cb)
            cb(true)
        end

        package.loaded["leanpack.hooks"].execute_build = function(build, plugin)
            table.insert(built, plugin.spec.name)
        end

        leanpack.setup({
            spec = {
                { "owner/build-plugin", build = ":BuildPlugin" },
            },
        })

        _G.built = built
        vim.uv.fs_stat = original_stat
        require("leanpack.job").run = original_job_run
    ]])

    MiniTest.expect.equality(child.lua_get("_G.built"), { "build-plugin" })
end
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
./scripts/test tests/hooks_spec.lua tests/installation_spec.lua
```

Expected: FAIL because `execute_build` uses `vim.cmd("!" .. build)` and parent callback does not explicitly run builds.

- [ ] **Step 4: Implement `vim.system` shell builds**

Change `hooks.execute_build` string branch:

```lua
if type(build) == "string" then
    get_log().info(("Executing build command for %s: %s"):format(plugin.spec.name, build))
    if build:sub(1, 1) == ":" then
        ok, err = pcall(vim.cmd, build)
    else
        ok, err = pcall(function()
            local shell = vim.o.shell
            local shellcmdflag = vim.o.shellcmdflag
            local result = vim.system({ shell, shellcmdflag, build }, {
                cwd = plugin.path ~= "" and plugin.path or nil,
                text = true,
            }):wait()

            if result.code ~= 0 then
                error((result.stderr ~= "" and result.stderr or result.stdout or "build command failed"))
            end
        end)
    end
elseif type(build) == "function" then
    get_log().info(("Executing build function for %s"):format(plugin.spec.name))
    ok, err = pcall(build, plugin)
end
```

- [ ] **Step 5: Add pack-based build helper**

Add to `lua/leanpack/hooks.lua`:

```lua
function M.run_builds_for_packs(pack_specs)
    local count = 0

    for _, pack_spec in ipairs(pack_specs or {}) do
        local entry = state.get_entry(pack_spec.src)
        if entry and entry.merged_spec and entry.merged_spec.build then
            if entry.plugin then
                M.execute_build(entry.merged_spec.build, entry.plugin)
                count = count + 1
            end
        end
    end

    return count
end
```

- [ ] **Step 6: Run builds after background install**

In `lua/leanpack/init.lua`, after missing startup/lazy packs are registered and paths are set, call:

```lua
hooks.run_builds_for_packs(missing_packs)
```

Place it before UI refresh and success notification in the `job.run("install", ...)` callback.

- [ ] **Step 7: Run tests and commit**

Run:

```bash
./scripts/test tests/hooks_spec.lua tests/installation_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/hooks.lua lua/leanpack/init.lua tests/hooks_spec.lua tests/installation_spec.lua
git commit -m "fix: run build hooks after background installs"
```

## Task 4: Background Job Concurrency Guard

**Files:**

- Modify: `lua/leanpack/job.lua`
- Modify: `lua/leanpack/commands.lua`
- Test: `tests/job_spec.lua`

- [ ] **Step 1: Add failing concurrency test**

Add to `tests/job_spec.lua`:

```lua
T["run()"]["rejects concurrent jobs"] = function()
    child.lua([[
        local job = require("leanpack.job")
        local starts = 0
        local messages = {}

        local original_jobstart = vim.fn.jobstart
        local original_notify = vim.notify

        vim.fn.jobstart = function(cmd, opts)
            starts = starts + 1
            _G.first_opts = opts
            return 1
        end

        vim.notify = function(msg, level)
            table.insert(messages, msg)
        end

        _G.first = job.run("update", nil)
        _G.second = job.run("update", nil)
        _G.starts = starts
        _G.messages = messages

        _G.first_opts.on_exit(1, 0)

        vim.fn.jobstart = original_jobstart
        vim.notify = original_notify
    ]])

    MiniTest.expect.equality(child.lua_get("_G.first"), true)
    MiniTest.expect.equality(child.lua_get("_G.second"), false)
    MiniTest.expect.equality(child.lua_get("_G.starts"), 1)
    MiniTest.expect.equality(child.lua_get("_G.messages")[1]:match("already running") ~= nil, true)
end
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
./scripts/test tests/job_spec.lua
```

Expected: FAIL because `job.run` does not return status or block concurrent jobs.

- [ ] **Step 3: Implement guard**

At module scope in `lua/leanpack/job.lua`:

```lua
local active_job = false
```

At the top of `M.run`:

```lua
if active_job then
    vim.notify("Leanpack background job is already running", vim.log.levels.WARN)
    return false
end
active_job = true
```

Before each early return after setting `active_job`, reset it. In `on_exit`, add:

```lua
active_job = false
```

At successful `jobstart`, return `true`.

- [ ] **Step 4: Run tests and commit**

Run:

```bash
./scripts/test tests/job_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/job.lua tests/job_spec.lua
git commit -m "fix: prevent concurrent package jobs"
```

## Task 5: Lazy Command Replay Fidelity

**Files:**

- Modify: `lua/leanpack/lazy.lua`
- Test: `tests/lazy_spec.lua`

- [ ] **Step 1: Add failing command replay test**

Add under command trigger tests in `tests/lazy_spec.lua`:

```lua
T["cmd trigger"]["replays bang range and raw args"] = function()
    child.lua([[
        local replayed = nil

        state.set_entry("test-src", {
            specs = {},
            merged_spec = { cmd = "ReplayCommand" },
            load_status = "pending",
            plugin = { spec = { src = "test-src", name = "test-plugin" }, path = "/tmp/test-plugin" },
        })
        state.register_pack_spec({ src = "test-src", name = "test-plugin" })

        package.loaded["leanpack.loader"] = {
            load_plugin = function(pack_spec)
                local entry = state.get_entry(pack_spec.src)
                entry.load_status = "loaded"
                vim.api.nvim_create_user_command("ReplayCommand", function(opts)
                    replayed = {
                        bang = opts.bang,
                        args = opts.args,
                        range = opts.range,
                        line1 = opts.line1,
                        line2 = opts.line2,
                    }
                end, { nargs = "*", bang = true, range = true })
            end,
        }

        lazy.process_lazy({
            lazy_packs = {
                { src = "test-src", name = "test-plugin", data = { leanpack = true } },
            },
        })

        vim.cmd("1,3ReplayCommand! alpha beta")

        _G.replayed = replayed
    ]])

    MiniTest.expect.equality(child.lua_get("_G.replayed"), {
        bang = true,
        args = "alpha beta",
        range = 2,
        line1 = 1,
        line2 = 3,
    })
end
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
./scripts/test tests/lazy_spec.lua
```

Expected: FAIL because placeholder command uses only `fargs`.

- [ ] **Step 3: Implement full command replay**

In `lua/leanpack/lazy.lua`, add helper:

```lua
local function replay_command(cmd_name, cmd_args)
    local cmd = {
        cmd = cmd_name,
        args = cmd_args.args,
        bang = cmd_args.bang,
        mods = cmd_args.smods,
    }

    if cmd_args.range and cmd_args.range > 0 then
        cmd.range = { cmd_args.line1, cmd_args.line2 }
    end

    if cmd_args.count and cmd_args.count >= 0 then
        cmd.count = cmd_args.count
    end

    if cmd_args.reg and cmd_args.reg ~= "" then
        cmd.reg = cmd_args.reg
    end

    pcall(vim.api.nvim_cmd, cmd, {})
end
```

Change placeholder creation options:

```lua
vim.api.nvim_create_user_command(cmd_name, function(cmd_args)
    pcall(vim.api.nvim_del_user_command, cmd_name)
    for _, pack_spec in ipairs(pack_specs) do
        local entry = state.get_entry(pack_spec.src)
        if entry and entry.load_status == "pending" then
            loader.load_plugin(pack_spec)
        end
    end
    replay_command(cmd_name, cmd_args)
end, { nargs = "*", bang = true, range = true, bar = true })
```

- [ ] **Step 4: Run tests and commit**

Run:

```bash
./scripts/test tests/lazy_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/lazy.lua tests/lazy_spec.lua
git commit -m "fix: preserve lazy command replay context"
```

## Task 6: Narrow Event Replay

**Files:**

- Modify: `lua/leanpack/lazy_trigger/event.lua`
- Modify: `lua/leanpack/lazy_trigger/util.lua`
- Modify: `lua/leanpack/lazy.lua`
- Test: `tests/lazy_spec.lua`

- [ ] **Step 1: Add failing narrow replay test**

Add to `tests/lazy_spec.lua`:

```lua
T["event trigger"]["replays only triggering event"] = function()
    child.lua([[
        local util = require("leanpack.lazy_trigger.util")
        local replayed = {}

        local original_exec = vim.api.nvim_exec_autocmds
        vim.api.nvim_exec_autocmds = function(event, opts)
            table.insert(replayed, event)
        end

        util.retrigger_event("BufReadPost", vim.api.nvim_get_current_buf())

        vim.wait(50, function()
            return #replayed > 0
        end)

        _G.replayed = replayed
        vim.api.nvim_exec_autocmds = original_exec
    ]])

    MiniTest.expect.equality(child.lua_get("_G.replayed"), { "BufReadPost" })
end
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
./scripts/test tests/lazy_spec.lua
```

Expected: FAIL because current utility always replays `BufReadPre`, `BufReadPost`, and `FileType`.

- [ ] **Step 3: Implement narrow event utility**

Replace `retrigger_events` in `lua/leanpack/lazy_trigger/util.lua` with:

```lua
function M.retrigger_event(event_name, bufnr)
    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_exec_autocmds(event_name, { buffer = bufnr, modeline = false })
        end
    end)
end

function M.load_and_retrigger(pack_spec, bufnr, event_name)
    local entry = state.get_entry(pack_spec.src)
    if entry and entry.load_status ~= "pending" then
        if event_name then
            M.retrigger_event(event_name, bufnr or vim.api.nvim_get_current_buf())
        end
        return
    end

    require("leanpack.loader").load_plugin(pack_spec)
    if event_name then
        M.retrigger_event(event_name, bufnr or vim.api.nvim_get_current_buf())
    end
end
```

- [ ] **Step 4: Pass event names from triggers**

In `lua/leanpack/lazy_trigger/event.lua`, change callback to:

```lua
require("leanpack.lazy_trigger.util").load_and_retrigger(pack_spec, ev.buf, ev.event)
```

In `lua/leanpack/lazy.lua`, change FileType trigger callback to:

```lua
require("leanpack.lazy_trigger.util").load_and_retrigger(pack_spec, ev.buf, "FileType")
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
./scripts/test tests/lazy_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/lazy.lua lua/leanpack/lazy_trigger/event.lua lua/leanpack/lazy_trigger/util.lua tests/lazy_spec.lua
git commit -m "fix: narrow lazy event replay"
```

## Task 7: Keymap Option Preservation And Count Replay

**Files:**

- Modify: `lua/leanpack/keymap.lua`
- Modify: `lua/leanpack/lazy_trigger/keys.lua`
- Test: `tests/lazy_spec.lua`

- [ ] **Step 1: Add failing key option test**

Add to `tests/lazy_spec.lua`:

```lua
T["keys trigger"]["preserves silent expr and noremap-compatible options"] = function()
    child.lua([[
        state.set_entry("key-src", {
            specs = {},
            merged_spec = {
                keys = {
                    { "<leader>x", "<cmd>echo 'x'<cr>", mode = "n", desc = "X", silent = true, expr = false, nowait = true },
                },
            },
            load_status = "pending",
            plugin = { spec = { src = "key-src", name = "key-plugin" }, path = "/tmp/key-plugin" },
        })
        state.register_pack_spec({ src = "key-src", name = "key-plugin" })

        require("leanpack.lazy_trigger.keys").setup({
            { src = "key-src", name = "key-plugin" },
        })

        local maps = vim.api.nvim_get_keymap("n")
        local found = nil
        for _, map in ipairs(maps) do
            if map.lhs == "<leader>x" then
                found = map
                break
            end
        end

        _G.found = found
    ]])

    local found = child.lua_get("_G.found")
    MiniTest.expect.equality(found.silent, 1)
    MiniTest.expect.equality(found.expr, 0)
    MiniTest.expect.equality(found.nowait, 1)
end
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
./scripts/test tests/lazy_spec.lua
```

Expected: FAIL because `silent` and `expr` are not passed.

- [ ] **Step 3: Add shared key option helper**

In `lua/leanpack/keymap.lua`, add:

```lua
function M.key_opts(key)
    return {
        desc = key.desc,
        remap = key.remap or false,
        nowait = key.nowait or false,
        silent = key.silent or false,
        expr = key.expr or false,
    }
end
```

Change `apply_keys` to use:

```lua
vim.keymap.set(m, lhs, rhs, M.key_opts(key))
```

- [ ] **Step 4: Use shared options and replay count**

In `lua/leanpack/lazy_trigger/keys.lua`, replace local option construction with:

```lua
local opts = keymap.key_opts(info.key_spec)
```

Change feedkeys replay to preserve count:

```lua
local count = vim.v.count and vim.v.count > 0 and tostring(vim.v.count) or ""
vim.api.nvim_feedkeys(vim.keycode(count .. lhs), "m", false)
```

Use this replay in both `rhs` string and no-rhs branches.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
./scripts/test tests/lazy_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/keymap.lua lua/leanpack/lazy_trigger/keys.lua tests/lazy_spec.lua
git commit -m "fix: preserve lazy keymap options"
```

## Task 8: Cache Invalidation And Module Map Startup Optimization

**Files:**

- Create: `lua/leanpack/cache.lua`
- Modify: `lua/leanpack/spec.lua`
- Modify: `lua/leanpack/state.lua`
- Modify: `lua/leanpack/lazy_trigger/module.lua`
- Test: `tests/cache_spec.lua`
- Test: `tests/main_detection_spec.lua`
- Test: `tests/module_trigger_spec.lua`

- [ ] **Step 1: Add failing cache tests**

Create `tests/cache_spec.lua`:

```lua
local MiniTest = require("mini.test")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ "-u", "NONE" })
            child.lua([[
                vim.opt.rtp:prepend("]] .. vim.fn.getcwd() .. [[")
                _G.cache = require("leanpack.cache")
            ]])
        end,
        post_once = child.stop,
    },
})

T["stamp_for_dir()"] = MiniTest.new_set()

T["stamp_for_dir()"]["changes when lua directory mtime changes"] = function()
    child.lua([[
        local original_stat = vim.uv.fs_stat
        local mtimes = {
            ["/tmp/plugin/lua"] = { type = "directory", mtime = { sec = 10, nsec = 0 } },
        }

        vim.uv.fs_stat = function(path)
            return mtimes[path]
        end

        _G.first = cache.stamp_for_dir("/tmp/plugin")
        mtimes["/tmp/plugin/lua"] = { type = "directory", mtime = { sec = 20, nsec = 0 } }
        _G.second = cache.stamp_for_dir("/tmp/plugin")

        vim.uv.fs_stat = original_stat
    ]])

    MiniTest.expect.equality(child.lua_get("_G.first") ~= child.lua_get("_G.second"), true)
end

T["records"]["returns nil when stamp mismatches"] = function()
    child.lua([[
        cache.set("main", "plugin:/tmp/plugin", "stamp-a", "plugin")
        _G.same = cache.get("main", "plugin:/tmp/plugin", "stamp-a")
        _G.diff = cache.get("main", "plugin:/tmp/plugin", "stamp-b")
    ]])

    MiniTest.expect.equality(child.lua_get("_G.same"), "plugin")
    MiniTest.expect.equality(child.lua_get("_G.diff"), vim.NIL)
end

return T
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
./scripts/test tests/cache_spec.lua
```

Expected: FAIL because `leanpack.cache` does not exist.

- [ ] **Step 3: Implement cache module**

Create `lua/leanpack/cache.lua`:

```lua
local M = {}

local loaded = false
local data = {
    main = {},
    module_map = {},
}

local function cache_path()
    return vim.fn.stdpath("cache") .. "/leanpack/cache.json"
end

local function ensure_loaded()
    if loaded then
        return
    end

    local f = io.open(cache_path(), "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, decoded = pcall(vim.json.decode, content)
        if ok and type(decoded) == "table" then
            data.main = decoded.main or {}
            data.module_map = decoded.module_map or {}
        end
    end

    loaded = true
end

function M.stamp_for_dir(dir)
    local lua_stat = vim.uv.fs_stat(dir .. "/lua")
    if not lua_stat then
        return "missing"
    end

    local mtime = lua_stat.mtime or {}
    return table.concat({
        dir,
        tostring(mtime.sec or 0),
        tostring(mtime.nsec or 0),
    }, ":")
end

function M.get(namespace, key, stamp)
    ensure_loaded()
    local bucket = data[namespace]
    local record = bucket and bucket[key]
    if record and record.stamp == stamp then
        return record.value
    end
    return nil
end

function M.set(namespace, key, stamp, value)
    ensure_loaded()
    data[namespace] = data[namespace] or {}
    data[namespace][key] = {
        stamp = stamp,
        value = value,
    }
end

function M.save()
    ensure_loaded()

    local dir = vim.fn.stdpath("cache") .. "/leanpack"
    if vim.fn.isdirectory(dir) ~= 1 then
        vim.fn.mkdir(dir, "p")
    end

    local ok, encoded = pcall(vim.json.encode, data)
    if not ok then
        return false
    end

    local f = io.open(cache_path(), "w")
    if not f then
        return false
    end

    f:write(encoded)
    f:close()
    return true
end

function M.reset()
    loaded = true
    data = { main = {}, module_map = {} }
end

return M
```

- [ ] **Step 4: Route main detection cache through cache module**

In `lua/leanpack/spec.lua`, require cache:

```lua
local cache = require("leanpack.cache")
```

In `detect_main`, replace state main cache reads/writes with:

```lua
local stamp = cache.stamp_for_dir(dir)
local cache_key = name .. ":" .. dir
local cached = cache.get("main", cache_key, stamp)
if cached then
    return cached
end
```

Replace each `state.cache_main(name, dir, value)` with:

```lua
cache.set("main", cache_key, stamp, value)
```

- [ ] **Step 5: Save cache on exit through cache module**

In `lua/leanpack/init.lua`, update the existing `VimLeavePre` callback to call:

```lua
require("leanpack.cache").save()
```

Keep `state.save_main_cache()` only if compatibility is required by existing tests; otherwise remove `main_cache` fields from `state.lua` in a separate cleanup commit.

- [ ] **Step 6: Cache module map**

In `lua/leanpack/lazy_trigger/module.lua`, before scanning `lua_dir`, compute:

```lua
local cache = require("leanpack.cache")
local stamp = cache.stamp_for_dir(path)
local map_key = pack_spec.name .. ":" .. path
local cached_modules = cache.get("module_map", map_key, stamp)
```

If `cached_modules` exists, register those module names without scanning. If not, scan and save the list:

```lua
local discovered = {}
-- during scan:
table.insert(discovered, mod)
-- after scan:
cache.set("module_map", map_key, stamp, discovered)
```

- [ ] **Step 7: Run tests and commit**

Run:

```bash
./scripts/test tests/cache_spec.lua tests/main_detection_spec.lua tests/module_trigger_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/cache.lua lua/leanpack/spec.lua lua/leanpack/init.lua lua/leanpack/lazy_trigger/module.lua tests/cache_spec.lua tests/main_detection_spec.lua tests/module_trigger_spec.lua
git commit -m "perf: cache module detection with invalidation"
```

## Task 9: Setup Idempotency And Skipped Load State

**Files:**

- Modify: `lua/leanpack/init.lua`
- Modify: `lua/leanpack/loader.lua`
- Modify: `lua/leanpack/state.lua`
- Test: `tests/loader_spec.lua`
- Test: `tests/state_spec.lua`

- [ ] **Step 1: Add failing skipped-state test**

Add to `tests/loader_spec.lua`:

```lua
T["load_plugin()"]["marks cond false plugin as skipped not loaded"] = function()
    child.lua([[
        state.set_entry("skip-src", {
            specs = {},
            merged_spec = { src = "skip-src", name = "skip-plugin", cond = false },
            load_status = "pending",
            plugin = { spec = { src = "skip-src", name = "skip-plugin" }, path = "/tmp/skip-plugin" },
        })
        state.register_pack_spec({ src = "skip-src", name = "skip-plugin" })

        local loader = require("leanpack.loader")
        loader.load_plugin({ src = "skip-src", name = "skip-plugin" })

        _G.status = state.get_entry("skip-src").load_status
    ]])

    MiniTest.expect.equality(child.lua_get("_G.status"), "skipped")
end
```

- [ ] **Step 2: Add failing duplicate autocmd test**

Add to `tests/state_spec.lua` or `tests/installation_spec.lua`:

```lua
T["setup()"]["registers cache save autocmd only once"] = function()
    child.lua([[
        local leanpack = require("leanpack")
        vim.pack.add = function() end
        vim.uv.fs_stat = function() return { type = "directory" } end

        leanpack.setup({ spec = {} })
        leanpack.setup({ spec = {} })

        local autocmds = vim.api.nvim_get_autocmds({ event = "VimLeavePre" })
        local count = 0
        for _, autocmd in ipairs(autocmds) do
            if autocmd.desc == "leanpack save cache" then
                count = count + 1
            end
        end

        _G.count = count
    ]])

    MiniTest.expect.equality(child.lua_get("_G.count"), 1)
end
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
./scripts/test tests/loader_spec.lua tests/state_spec.lua
```

Expected: FAIL because `cond=false` uses `loaded` and setup adds duplicate save autocmds.

- [ ] **Step 4: Implement skipped state**

In `lua/leanpack/loader.lua`, change:

```lua
entry.load_status = "loaded"
```

inside the `cond=false` branch to:

```lua
entry.load_status = "skipped"
```

Update `state.get_unloaded_names()` to exclude skipped entries:

```lua
if entry.merged_spec and entry.load_status ~= "loaded" and entry.load_status ~= "skipped" then
    table.insert(names, entry.merged_spec.name)
end
```

- [ ] **Step 5: Guard save autocmd**

In `lua/leanpack/init.lua`, add module-scope flag:

```lua
local save_cache_autocmd_registered = false
```

Replace the current `VimLeavePre` creation with:

```lua
if not save_cache_autocmd_registered then
    save_cache_autocmd_registered = true
    vim.api.nvim_create_autocmd("VimLeavePre", {
        desc = "leanpack save cache",
        callback = function()
            local ok_cache, cache = pcall(require, "leanpack.cache")
            if ok_cache and cache.save then
                cache.save()
            end
            state.save_main_cache()
        end,
    })
end
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
./scripts/test tests/loader_spec.lua tests/state_spec.lua
```

Expected: PASS.

Commit:

```bash
git add lua/leanpack/init.lua lua/leanpack/loader.lua lua/leanpack/state.lua tests/loader_spec.lua tests/state_spec.lua
git commit -m "fix: make setup cache hooks idempotent"
```

## Task 10: Final Verification, Benchmark, And Documentation

**Files:**

- Modify: `docs/technical.md`
- Modify: `docs/troubleshooting.md`

- [ ] **Step 1: Run full unit suite**

Run:

```bash
./scripts/test
```

Expected: `Fails (0) and Notes (0)`.

- [ ] **Step 2: Run startup benchmark at scale**

Run:

```bash
nvim --headless -u NONE -c "set rtp^=$PWD" -l scripts/bench.lua 100
nvim --headless -u NONE -c "set rtp^=$PWD" -l scripts/bench.lua 500
nvim --headless -u NONE -c "set rtp^=$PWD" -l scripts/bench.lua 1000
```

Expected: all commands exit 0. Record before/after times manually if execution environment has existing benchmark logs.

- [ ] **Step 3: Document reliability behavior**

Add to `docs/technical.md`:

```markdown
## Reliability Notes

leanpack.nvim prevents concurrent background package jobs in a single Neovim session. Install and update jobs still execute through Neovim's native `vim.pack`, but parent-session build hooks run after successful background installs so build behavior is deterministic from the user's active session.

Dependency cycles are treated as configuration errors. Startup dependency sorting fails fast with a cycle path instead of continuing with partial ordering.
```

- [ ] **Step 4: Document troubleshooting messages**

Add to `docs/troubleshooting.md`:

```markdown
## Circular Dependency Errors

If setup fails with `Circular dependency: a -> b -> a`, remove the cycle from your plugin specs. A plugin dependency graph must be acyclic because leanpack loads dependencies before dependents.

## Background Job Already Running

If `Leanpack background job is already running` appears, wait for the current install, update, or sync job to complete before starting another package operation.
```

- [ ] **Step 5: Final full verification**

Run:

```bash
./scripts/test
```

Expected: PASS.

Run:

```bash
git status --short
```

Expected: only intended source, test, and documentation files are modified before commit.

- [ ] **Step 6: Commit**

Commit:

```bash
git add docs/technical.md docs/troubleshooting.md
git commit -m "docs: document leanpack reliability behavior"
```

## Test Plan

- Run targeted tests after each task using the exact commands above.
- Run `./scripts/test` before final handoff.
- Run 100, 500, and 1000 plugin benchmark commands after cache changes.
- Confirm no command writes tracked files except planned source, test, and docs changes.
- Confirm public setup examples in `README.md` still work without changes.

## Assumptions And Defaults

- Preserve the public `require("leanpack").setup(...)` API.
- Keep Neovim 0.12+ as the compatibility target.
- Keep `vim.pack` as the install/update/delete backend.
- Keep string `build = "..."` compatibility, but execute shell builds through `vim.system` for cwd control and output capture.
- Conservative update behavior may run build hooks for requested updated plugins after a successful background update even if `vim.pack` does not expose exact changed plugin metadata.
- Module cache invalidation uses `lua/` directory mtime as the minimum reliable local stamp; deeper Git commit-aware invalidation can be added later if needed.
- This plan is staged so each task can be implemented, tested, reviewed, and committed independently.
