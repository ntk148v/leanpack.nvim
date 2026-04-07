---@class parcel.KeySpec
---@field [1] string LHS keymap
---@field [2]? string|fun() RHS function or command
---@field mode? string|string[] Mode(s), default "n"
---@field desc? string Description
---@field remap? boolean Allow remapping, default false
---@field nowait? boolean Default false

---@class parcel.EventSpec
---@field event string|string[] Event name(s)
---@field pattern? string|string[] Pattern(s) for the event

---@class parcel.Plugin
---@field spec vim.pack.Spec Resolved vim.pack spec
---@field path string Absolute path to plugin directory
---@field main? string Detected main module name

---@alias parcel.EventValue string|string[]|parcel.EventSpec|(string|parcel.EventSpec)[]
---@alias parcel.CmdValue string|string[]
---@alias parcel.KeysValue string|string[]|parcel.KeySpec|parcel.KeySpec[]
---@alias parcel.FtValue string|string[]

---@class parcel.Spec
---@field [1]? string Plugin short name (e.g., "user/repo"). Required if src/dir/url not provided
---@field src? string Custom git URL or local path
---@field dir? string Local plugin directory (lazy.nvim compat, mapped to src)
---@field url? string Custom git URL (lazy.nvim compat, mapped to src)
---@field name? string Custom plugin name, overrides auto-derived name
---@field dependencies? string|string[]|parcel.Spec|parcel.Spec[] Plugin dependencies
---@field enabled? boolean|(fun():boolean) Enable/disable plugin
---@field cond? boolean|(fun(plugin: parcel.Plugin):boolean) Condition to load plugin
---@field lazy? boolean Force lazy/eager loading
---@field priority? number Load priority, higher = earlier, default 50
---@field version? string|vim.VersionRange Git branch/tag/commit or semver range
---@field sem_version? string Semver range string (lazy.nvim compat)
---@field branch? string Git branch (lazy.nvim compat)
---@field tag? string Git tag (lazy.nvim compat)
---@field commit? string Git commit (lazy.nvim compat)
---@field init? fun(plugin: parcel.Plugin) Runs before plugin loads
---@field config? fun(plugin: parcel.Plugin, opts: table)|true Runs after plugin loads
---@field build? string|fun(plugin: parcel.Plugin) Build command or function
---@field opts? table|fun(plugin: parcel.Plugin, opts: table):table Options for setup()
---@field main? string Explicit main module name
---@field event? parcel.EventValue|fun(plugin: parcel.Plugin):parcel.EventValue Lazy load on event
---@field pattern? string|string[] Global fallback pattern for events
---@field cmd? parcel.CmdValue|fun(plugin: parcel.Plugin):parcel.CmdValue Lazy load on command
---@field keys? parcel.KeysValue|fun(plugin: parcel.Plugin):parcel.KeysValue Lazy load on keymap
  ---@field ft? parcel.FtValue|fun(plugin: parcel.Plugin):parcel.FtValue Lazy load on filetype
  ---@field module? string|string[] Auto-load when require()'d with matching module pattern
  ---@field import? string Module path to import specs from
  ---@field dev? boolean Development mode, use ~/projects/{plugin-name} as source
  ---@field optional? boolean Optional dependency, warn instead of error if not found

---@alias parcel.LoadStatus "pending"|"loading"|"loaded"

---@class parcel.RegistryEntry
---@field specs parcel.Spec[] Raw specs for this plugin
---@field merged_spec? parcel.Spec Merged and normalized spec
---@field plugin? parcel.Plugin Plugin data
---@field load_status parcel.LoadStatus Current load status

---@class parcel.Config.Defaults
---@field cond? boolean|(fun(plugin: parcel.Plugin):boolean) Global condition for all plugins
---@field confirm? boolean Ask for confirmation on install, default true

---@class parcel.Config.Performance
---@field vim_loader? boolean Enable vim.loader for faster startup, default true

---@class parcel.Config.Lockfile
---@field path? string Path to lockfile, default "{config}/parcel-lock.json"

---@class parcel.Config.Checker
---@field enabled? boolean Default false
---@field frequency? number Seconds between checks, default 3600
---@field notify? boolean Show notification on updates, default true

---@class parcel.Config.Git
---@field throttle? { enabled?: boolean, rate?: number, duration?: number }
---@field timeout? number Git timeout in seconds, default 120

---@class parcel.Config
---@field spec? parcel.Spec[] Plugin specifications
---@field cmd_prefix? string Command prefix, default "Parcel"
---@field defaults? parcel.Config.Defaults
---@field performance? parcel.Config.Performance
---@field lockfile? parcel.Config.Lockfile
---@field checker? parcel.Config.Checker
---@field git? parcel.Config.Git

return {}