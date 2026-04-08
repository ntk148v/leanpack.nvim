---@module 'tests.helpers'
-- Test helpers for parcel.nvim

local M = {}

-- Store original functions for restoration
local originals = {}

---Reset parcel.nvim state completely
function M.reset_parcel_state()
	-- Clear all loaded parcel modules
	for name, _ in pairs(package.loaded) do
		if name:match("^parcel") then
			package.loaded[name] = nil
		end
	end

	-- Re-require and reset state
	local ok, state = pcall(require, "parcel.state")
	if ok and state.reset then
		state.reset()
	end
end

---Create a temporary directory for test files
---@param name string Directory name
---@return string path Full path to directory
function M.create_temp_dir(name)
	local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
	local path = project_root .. "/.tests/temp/" .. name
	vim.fn.mkdir(path, "p")
	return path
end

---Clean up temporary directory
---@param name string Directory name
function M.remove_temp_dir(name)
	local project_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
	local path = project_root .. "/.tests/temp/" .. name
	vim.fn.delete(path, "rf")
end

---Mock a vim function
---@param name string Function name (e.g., "fn.mkdir")
---@param mock_fn function Mock implementation
function M.mock(name, mock_fn)
		local parts = vim.split(name, "[.]")
	local obj = _G
	local key = nil

	for i, part in ipairs(parts) do
		if i == #parts then
			key = part
		else
			obj = obj[part]
		end
	end

	-- Store original
	originals[name] = obj[key]
	obj[key] = mock_fn
end

---Restore all mocked functions
function M.restore_all()
	for name, orig in pairs(originals) do
	local parts = vim.split(name, "[.]")
		local obj = _G
		local key = nil

		for i, part in ipairs(parts) do
			if i == #parts then
				key = part
			else
				obj = obj[part]
			end
		end

		obj[key] = orig
	end
	originals = {}
end

---Create a mock plugin directory structure
---@param name string Plugin name (e.g., "test-plugin")
---@param opts? {main?: string, version?: string}
---@return string path Path to mock plugin
function M.create_mock_plugin(name, opts)
	opts = opts or {}
	local path = M.create_temp_dir("plugins/" .. name)

	-- Create plugin directory structure
	vim.fn.mkdir(path .. "/lua/" .. name:gsub("-", "_"), "p")

	-- Create main module file
	local main_name = opts.main or name:gsub("-", "_")
	local main_file = path .. "/lua/" .. main_name:gsub("[.]", "/") .. ".lua"
	vim.fn.mkdir(vim.fn.fnamemodify(main_file, ":h"), "p")

	local content = string.format([[
-- Mock plugin: %s
local M = {}
M._loaded = true
M.name = "%s"
return M
]], name, name)

	local f = io.open(main_file, "w")
	if f then
		f:write(content)
		f:close()
	end

	return path
end

---Create a mock git repository
---@param name string Repository name
---@param opts? {remote?: string, commits?: number}
---@return string path Path to mock repo
function M.create_mock_git_repo(name, opts)
	opts = opts or {}
	local path = M.create_temp_dir("repos/" .. name)

	-- Initialize git repo
	vim.fn.system({ "git", "init", path })
	vim.fn.system({ "git", "-C", path, "config", "user.email", "test@test.com" })
	vim.fn.system({ "git", "-C", path, "config", "user.name", "Test User" })

	-- Create initial commit
	local readme = path .. "/README.md"
	local f = io.open(readme, "w")
	if f then
		f:write("# " .. name .. "\n")
		f:close()
	end

	vim.fn.system({ "git", "-C", path, "add", "." })
	vim.fn.system({ "git", "-C", path, "commit", "-m", "Initial commit" })

	-- Add more commits if requested
	if opts.commits then
		for i = 2, opts.commits do
			local file = path .. "/file" .. i .. ".txt"
			f = io.open(file, "w")
			if f then
				f:write("Content " .. i .. "\n")
				f:close()
			end
			vim.fn.system({ "git", "-C", path, "add", "." })
			vim.fn.system({ "git", "-C", path, "commit", "-m", "Commit " .. i })
		end
	end

	return path
end

---Mock vim.uv filesystem operations
---@param filesystem table<string, {type: string, content?: string}> Virtual filesystem
function M.mock_filesystem(filesystem)
	local uv = vim.uv or vim.loop

	-- Store original fs_stat
	originals["uv.fs_stat"] = uv.fs_stat

	uv.fs_stat = function(path)
		local entry = filesystem[path]
		if entry then
			return {
				type = entry.type,
				size = entry.content and #entry.content or 0,
				mtime = { sec = 0, nsec = 0 },
			}
		end
		return nil
	end
end

---Mock vim.pack.add to prevent actual git operations
---@param plugins table<string, {spec: vim.pack.Spec, path: string}> Mock plugins
function M.mock_vim_pack_add(plugins)
	plugins = plugins or {}

	-- Store original vim.pack.add
	originals["vim.pack.add"] = vim.pack.add

	vim.pack.add = function(specs, opts)
		opts = opts or {}
		local results = {}

		for _, spec in ipairs(specs) do
			local plugin_key = spec.src or spec.name
			if not plugins[plugin_key] then
				-- Create a mock plugin entry
				plugins[plugin_key] = {
					spec = spec,
					path = "/tmp/mock-plugins/" .. spec.name,
				}
			end
			table.insert(results, plugins[plugin_key])
		end

		return results
	end
end

---Create a test spec
---@param overrides? table Fields to override
---@return parcel.Spec
function M.make_spec(overrides)
	local spec = {
		[1] = "user/test-plugin",
		src = "https://github.com/user/test-plugin",
		name = "test-plugin",
		priority = 50,
	}

	if overrides then
		for k, v in pairs(overrides) do
			spec[k] = v
		end
	end

	return spec
end

---Create a test plugin entry
---@param overrides? table Fields to override
---@return parcel.RegistryEntry
function M.make_entry(overrides)
	local entry = {
		specs = { M.make_spec() },
		merged_spec = M.make_spec(),
		plugin = {
			spec = { src = "https://github.com/user/test-plugin", name = "test-plugin" },
			path = "/tmp/test-plugin",
		},
		load_status = "pending",
	}

	if overrides then
		for k, v in pairs(overrides) do
			entry[k] = v
		end
	end

	return entry
end

---Assert that a table contains expected keys
---@param t table
---@param keys string[]
function M.assert_has_keys(t, keys)
	for _, key in ipairs(keys) do
		if t[key] == nil then
			error("Expected table to have key: " .. key)
		end
	end
end

---Assert that two tables are deeply equal
---@param t1 table
---@param t2 table
function M.assert_deep_equal(t1, t2)
	local function deep_equal(a, b, path)
		path = path or ""

		if type(a) ~= type(b) then
			error(string.format("Type mismatch at %s: %s vs %s", path, type(a), type(b)))
		end

		if type(a) ~= "table" then
			if a ~= b then
				error(string.format("Value mismatch at %s: %s vs %s", path, tostring(a), tostring(b)))
			end
			return
		end

		-- Check all keys in a
		for k, v in pairs(a) do
			local new_path = path .. "." .. tostring(k)
			if b[k] == nil then
				error(string.format("Missing key at %s", new_path))
			end
			deep_equal(v, b[k], new_path)
		end

		-- Check for extra keys in b
		for k, _ in pairs(b) do
			if a[k] == nil then
				error(string.format("Extra key at %s.%s", path, tostring(k)))
			end
		end
	end

	deep_equal(t1, t2)
end

return M
