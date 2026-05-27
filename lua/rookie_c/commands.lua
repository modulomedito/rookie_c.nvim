local M = {}

-- Search and collect files matching patterns recursively
local function search_and_collect(dir, patterns)
    local result = {}

    -- Ensure the directory path ends with a slash and uses forward slashes
    local dir_with_slash = dir:gsub("\\", "/")
    if not dir_with_slash:match("/$") then
        dir_with_slash = dir_with_slash .. "/"
    end

    -- Get all files recursively using globpath with the '**' wildcard
    local files = vim.fn.globpath(dir, "**", false, true)
    for _, file in ipairs(files) do
        -- Skip directories – process only files
        if vim.fn.isdirectory(file) == 0 then
            for _, pattern in ipairs(patterns) do
                if file:match(pattern) then
                    local file_with_slash = file:gsub("\\", "/")
                    table.insert(result, file_with_slash)
                end
            end
        end
    end

    return result
end

-- Remove duplicates from a list
local function remove_duplicates(items)
    local seen = {}
    local result = {}
    for _, item in ipairs(items) do
        if not seen[item] then
            seen[item] = true
            table.insert(result, item)
        end
    end
    return result
end

local function get_clangd_clients()
    if vim.lsp.get_clients then
        return vim.lsp.get_clients({ name = "clangd" })
    end

    return vim.tbl_filter(function(client)
        return client.name == "clangd"
    end, vim.lsp.get_active_clients())
end

local function restart_clangd_clients()
    local clients = get_clangd_clients()
    if #clients == 0 then
        return
    end

    local attached_buffers = {}
    for _, client in ipairs(clients) do
        for buf, _ in pairs(client.attached_buffers or {}) do
            attached_buffers[buf] = true
        end
        client.stop(true)
    end

    vim.defer_fn(function()
        for buf, _ in pairs(attached_buffers) do
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype ~= "" then
                vim.api.nvim_exec_autocmds("FileType", {
                    buffer = buf,
                    modeline = false,
                })
            end
        end

        vim.notify("Restarted clangd after updating compile_commands.json", vim.log.levels.INFO)
    end, 200)
end

-- Search and collect parent folders of matching files
local function search_and_collect_parent(dir, patterns)
    local raw_result = {}
    local match_files = search_and_collect(dir, patterns)

    for _, match_file in ipairs(match_files) do
        local parent = vim.fn.fnamemodify(match_file, ":h")
        parent = parent:gsub("\\", "/")
        table.insert(raw_result, parent)
    end

    return remove_duplicates(raw_result)
end

-- Main function to create compile_commands.json
function M.create_compile_commands_json()
    local current_dir = vim.fn.getcwd():gsub("\\", "/")

    -- Search header parent folders
    local header_patterns = {}
    for _, pattern in ipairs(vim.g.rookie_toys_clangd_header_patterns) do
        table.insert(header_patterns, "%." .. pattern .. "$")
    end
    local header_dirs = search_and_collect_parent(current_dir, header_patterns)

    -- Search source files
    local source_patterns = {}
    for _, pattern in ipairs(vim.g.rookie_toys_clangd_source_patterns) do
        table.insert(source_patterns, "%." .. pattern .. "$")
    end
    local sources = search_and_collect(current_dir, source_patterns)

    -- First line output content
    local output_content = { "[" }

    -- Setup compile command
    local compile_cmd = '    "command": "\\"'
        .. vim.g.rookie_toys_clangd_compiler
        .. '\\" '

    -- Append arguments
    for _, arg in ipairs(vim.g.rookie_toys_clangd_args) do
        compile_cmd = compile_cmd .. '\\"' .. arg .. '\\" '
    end

    -- Append includes
    for _, header_dir in ipairs(header_dirs) do
        compile_cmd = compile_cmd .. '\\"-I' .. header_dir .. '\\" '
    end

    -- Body of the output content
    local num_sources = #sources
    for i, src_file in ipairs(sources) do
        table.insert(output_content, "  {")
        table.insert(
            output_content,
            '    "directory": "' .. current_dir .. '",'
        )
        table.insert(output_content, compile_cmd .. src_file .. '",')
        table.insert(output_content, '    "file": "' .. src_file .. '",')
        table.insert(output_content, '    "output": "' .. src_file .. '.o"')
        if i == num_sources then
            table.insert(output_content, "  }")
        else
            table.insert(output_content, "  },")
        end
    end

    -- Last line output content
    table.insert(output_content, "]")

    vim.fn.writefile(output_content, "compile_commands.json")
    print("Created compile_commands.json")
end

local function create_compile_commands_and_restart_clangd()
    M.create_compile_commands_json()
    restart_clangd_clients()
end

function M.toggle_header_source()
    local filename = vim.fn.expand('%:t:r')
    local extension = vim.fn.expand('%:e')
    local pattern = '**/' .. filename .. '.h'
    if extension == 'h' then
        pattern = '**/' .. filename .. '.c'
    end
    local matches = vim.fn.glob(pattern, 0, 1)
    if #matches == 0 then
        vim.notify('Corresponding header/source not exists', vim.log.levels.INFO)
        return
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(matches[1]))
end

-- Default configuration
local function set_defaults()
    if vim.g.rookie_toys_clangd_source_patterns == nil then
        vim.g.rookie_toys_clangd_source_patterns = { "c", "cpp" }
    end
    if vim.g.rookie_toys_clangd_header_patterns == nil then
        vim.g.rookie_toys_clangd_header_patterns = { "h", "hpp" }
    end
    if vim.g.rookie_toys_clangd_compiler == nil then
        vim.g.rookie_toys_clangd_compiler = "gcc"
    end
    if vim.g.rookie_toys_clangd_args == nil then
        vim.g.rookie_toys_clangd_args = { "-ferror-limit=3000" }
    end
end

function M.setup()
    set_defaults()

    -- RkClangdGenerate
    vim.api.nvim_create_user_command("RkClangdGenerate", function()
        create_compile_commands_and_restart_clangd()
    end, { desc = "Generate compile_commands.json for clangd" })

    -- CC as alias for RkClangdGenerate
    vim.api.nvim_create_user_command("CC", function()
        create_compile_commands_and_restart_clangd()
    end, { desc = "Alias for RkClangdGenerate" })

    -- Create the user command for toggling header/source
    vim.api.nvim_create_user_command('RkToggleHeaderSource', function()
        M.toggle_header_source()
    end, {
        desc = 'Toggle between C/C++ header and source file'
    })

    vim.api.nvim_create_user_command('RkCCommentToSlash', function()
        vim.cmd('%:s/\\/\\*\\+\\s\\+\\(.*\\)\\*\\//\\/\\/ \\1/g')
    end, {
        desc = 'Convert C/C++ comment to slash comment'
    })
end

return M
