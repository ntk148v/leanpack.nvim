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
