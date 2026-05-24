local M = {}

function M.setup()
    require("rookie_c.commands").setup()
    require("rookie_c.keymaps").setup()
end

return M
