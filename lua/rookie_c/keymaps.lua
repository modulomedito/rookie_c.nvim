local M = {}

function M.setup()
    -- Set up the default keymapping
    vim.keymap.set('n', '<leader>hh', ':RkToggleHeaderSource<CR>', {
        silent = true,
        desc = 'Toggle header/source (RookieToys)'
    })
end

return M
