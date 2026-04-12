-- scripts/bench.lua
-- Benchmark initialization for leanpack.nvim
local leanpack = require("leanpack")

-- Get number of plugins from command line or default to 100
local count = tonumber(arg[1]) or 100

local specs = {}
for i = 1, count do
    table.insert(specs, { "user/plugin-" .. i, lazy = true })
end

leanpack.setup({
    spec = specs,
    performance = {
        vim_loader = true,
    },
})

-- Simulate activity that triggers state lookups
for i = 1, count do
    require("leanpack.state").mark_loaded("plugin-" .. i)
end

vim.cmd("q")
