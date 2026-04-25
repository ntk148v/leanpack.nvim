---@module 'leanpack.import'
local M = {}

---Import specs from a module path
---@param import_path string Module path (e.g., "plugins" for lua/plugins/)
---@param ctx table Context with import order tracking
---@return leanpack.Spec[]
function M.import_specs(import_path, ctx)
    ctx = ctx or { import_order = 0, seen = {} }

    -- Prevent circular imports
    if ctx.seen[import_path] then
        return {}
    end
    ctx.seen[import_path] = true

    local specs = {}
    local paths = vim.api.nvim_get_runtime_file("lua/" .. import_path:gsub("%.", "/") .. ".lua", true)
    local init_paths = vim.api.nvim_get_runtime_file("lua/" .. import_path:gsub("%.", "/") .. "/init.lua", true)

    -- Combine both paths
    local all_paths = {}
    for _, p in ipairs(paths) do
        all_paths[p] = true
    end
    for _, p in ipairs(init_paths) do
        all_paths[p] = true
    end

    -- Also check for directory with multiple files
    local dir_path = "lua/" .. import_path:gsub("%.", "/")
    local dir_files = vim.api.nvim_get_runtime_file(dir_path .. "/*.lua", true)
    for _, p in ipairs(dir_files) do
        all_paths[p] = true
    end

    -- Load each file
    for path in pairs(all_paths) do
        -- Convert path to module name
        -- Find the lua/ directory in the path and extract module name
        local module_name = path:match("lua/(.+)%.lua$")
        if module_name then
            module_name = module_name:gsub("/", ".")
            -- Handle init.lua
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

    return specs
end

---Process import result (can be single spec, list of specs, or nested import)
---@param result any
---@param ctx table Context
---@return leanpack.Spec[]
function M.process_import_result(result, ctx)
    if result == nil then
        return {}
    end

    -- Handle import field
    if result.import then
        local nested_specs = M.import_specs(result.import, ctx)
        -- Merge with current specs
        local all_specs = {}
        for _, s in ipairs(nested_specs) do
            table.insert(all_specs, s)
        end
        -- Also include any specs in the same table
        for k, v in pairs(result) do
            if type(k) == "number" then
                table.insert(all_specs, v)
            end
        end
        return all_specs
    end

    -- Single spec
    if result[1] and type(result[1]) == "string" then
        return { result }
    end

    -- List of specs
    if type(result) == "table" then
        local specs = {}
        for _, item in ipairs(result) do
            if type(item) == "table" then
                -- Check if it's a nested import
                if item.import then
                    local nested = M.import_specs(item.import, ctx)
                    for _, s in ipairs(nested) do
                        table.insert(specs, s)
                    end
                else
                    table.insert(specs, item)
                end
            end
        end
        return specs
    end

    return {}
end

return M
