---@class leanpack.KeySpec
---@field [1] string LHS keymap
---@field [2]? string|fun() RHS function or command
---@field mode? string|string[] Mode(s), default "n"
---@field desc? string Description
---@field remap? boolean Allow remapping, default false
---@field nowait? boolean Default false

---@class leanpack.EventSpec
---@field event string|string[] Event name(s)
---@field pattern? string|string[] Pattern(s) for the event

---@class leanpack.Plugin
---@field spec vim.pack.Spec Resolved vim.pack spec
---@field path string Absolute path to plugin directory
---@field main? string Main module name (explicit or auto-detected)

---@alias leanpack.EventValue string|string[]|leanpack.EventSpec|(string|leanpack.EventSpec)[]
---@alias leanpack.CmdValue string|string[]
---@alias leanpack.KeysValue string|string[]|leanpack.KeySpec|leanpack.KeySpec[]
---@alias leanpack.FtValue string|string[]

---@class leanpack.Spec
---@field [1]? string Plugin short name (e.g., "user/repo"). Required if src/dir/url not provided
---@field src? string Custom git URL or local path
---@field dir? string Local plugin directory (lazy.nvim compat, mapped to src)
---@field url? string Custom git URL (lazy.nvim compat, mapped to src)
---@field name? string Custom plugin name, overrides auto-derived name
---@field dependencies? string|string[]|leanpack.Spec|leanpack.Spec[] Plugin dependencies
---@field enabled? boolean|(fun():boolean) Enable/disable plugin
---@field cond? boolean|(fun(plugin: leanpack.Plugin):boolean) Condition to load plugin
---@field lazy? boolean Force lazy/eager loading
---@field priority? number Load priority, higher = earlier, default 50
---@field version? string|vim.VersionRange Git branch/tag/commit or semver range
---@field sem_version? string Semver range string (lazy.nvim compat)
---@field branch? string Git branch (lazy.nvim compat)
---@field tag? string Git tag (lazy.nvim compat)
---@field commit? string Git commit (lazy.nvim compat)
---@field init? fun(plugin: leanpack.Plugin) Runs before plugin loads
---@field config? fun(plugin: leanpack.Plugin, opts: table)|true Runs after plugin loads
---@field build? string|fun(plugin: leanpack.Plugin) Build command or function
---@field opts? table|fun(plugin: leanpack.Plugin, opts: table):table Options for setup()
---@field main? string Explicit main module name (auto-detected if not provided)
---@field event? leanpack.EventValue|fun(plugin: leanpack.Plugin):leanpack.EventValue Lazy load on event
---@field pattern? string|string[] Global fallback pattern for events
---@field cmd? leanpack.CmdValue|fun(plugin: leanpack.Plugin):leanpack.CmdValue Lazy load on command
---@field keys? leanpack.KeysValue|fun(plugin: leanpack.Plugin):leanpack.KeysValue Lazy load on keymap
  ---@field ft? leanpack.FtValue|fun(plugin: leanpack.Plugin):leanpack.FtValue Lazy load on filetype
  ---@field import? string Module path to import specs from
  ---@field dev? boolean Development mode, use ~/projects/{plugin-name} as source
  ---@field optional? boolean Optional dependency, warn instead of error if not found

---@alias leanpack.LoadStatus "pending"|"loading"|"loaded"

---@class leanpack.RegistryEntry
---@field specs leanpack.Spec[] Raw specs for this plugin
---@field merged_spec? leanpack.Spec Merged and normalized spec
---@field plugin? leanpack.Plugin Plugin data
---@field load_status leanpack.LoadStatus Current load status

---@class leanpack.Config.Defaults
---@field cond? boolean|(fun(plugin: leanpack.Plugin):boolean) Global condition for all plugins
---@field confirm? boolean Ask for confirmation on install, default true

---@class leanpack.Config.Performance
---@field vim_loader? boolean Enable vim.loader for faster startup, default true

---@class leanpack.Config
---@field spec? leanpack.Spec[] Plugin specifications
---@field cmd_prefix? string Command prefix, default "Leanpack"
---@field defaults? leanpack.Config.Defaults
---@field performance? leanpack.Config.Performance

return {}