local config = require("cmp-llm.config")
local debug = require("cmp-llm.debug")

local M = {}

--- Execute a vim movement from cursor and return the resulting line number usin g operatorfunc
---@param movement string The vim movement command (e.g., "2{", "3k", "5j")
---@param direction number Direction hint: -1 for backward, 1 for forward
---@return number? line_number The line number after movement (1-indexed), nil i f movement failed
function M.execute_movement_from_cursor(movement, direction)
    if not movement or movement == "" then
        return nil
    end

    local total_lines = vim.api.nvim_buf_line_count(0)

    -- Save current state
    local original_operatorfunc = vim.o.operatorfunc
    local original_cursor = vim.api.nvim_win_get_cursor(0)
    local original_view = vim.fn.winsaveview()

    -- Set up operatorfunc to capture movement result
    -- vim.o.operatorfunc = 'v:lua.require("cmp-llm.prompt")._movement_operatorfunc'
    _G.CmpLlmMovementOperator = M._movement_operatorfunc
    vim.o.operatorfunc = 'v:lua.CmpLlmMovementOperator'
    M._movement_result = nil

    local success = pcall(function()
        -- Execute the movement using g@ - this will call our operatorfunc
        vim.cmd('noautocmd normal! g@' .. movement)
    end)

    -- Immediately restore cursor position and view to prevent any visual movement
    vim.fn.winrestview(original_view)
    vim.api.nvim_win_set_cursor(0, original_cursor)

    -- Restore original operatorfunc
    vim.o.operatorfunc = original_operatorfunc

    -- Get the result
    if success and M._movement_result then
        local result_line = M._movement_result.start[1]
        if direction == 1 then
            result_line = M._movement_result.fin[1]
        end
        M._movement_result = nil  -- cleanup

        debug.log_completion("execute_movement_from_cursorss", {
            success = success,
            result_line = result_line,
        })
        -- Ensure we stay within buffer bounds
        -- result_line = math.max(1, math.min(total_lines, result_line))
        return result_line
    end

    -- Fallback for unsupported movements
    if direction == -1 then
        return 1  -- Go to beginning if backward movement fails
    else
        return total_lines  -- Go to end if forward movement fails
    end
end

--- Operatorfunc callback to capture movement result
---@param type string The type of operation
---@return nil
function M._movement_operatorfunc(type)
    -- Get the position after the movement and store it
    -- local pos = vim.api.nvim_win_get_cursor(0)
    M._movement_result = {
        start = vim.api.nvim_buf_get_mark(0, '['),
        fin = vim.api.nvim_buf_get_mark(0, ']'),
    }
    debug.log_completion("_movement_operatorfunc", {
        pos = M._movement_result,
    })
end

--- Get context for completion with partial word removed
---@return string context The clean code context with <CURSOR> marker
function M.get_context_for_completion()
    return M.get_context_for_completion_by_movements()
end

--- Get context for completion using movement-based method with partial word removed
---@return string context The clean code context with <CURSOR> marker
function M.get_context_for_completion_by_movements()
    local cfg = config.get()
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    -- Find start and end positions using movement simulation
    local start_line = M.execute_movement_from_cursor(cfg.context_before, -1) or 1
    local end_line = M.execute_movement_from_cursor(cfg.context_after, 1) or vim.api.nvim_buf_line_count(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

    debug.log_completion("movement_boundary", {
        cursor_line = cursor_line,
        before_movement = cfg.context_after,
        after_movement = cfg.context_before,
        end_col = end_line,
        start_col = start_line,
    })

    -- Insert cursor marker with word boundary handling
    local current_line_idx = cursor_line - start_line + 1
    if current_line_idx > 0 and current_line_idx <= #lines then
        local current_line = lines[current_line_idx] or ""

        -- Keep the partial word visible to LLM but mark completion point with <CURSOR>
        local before_cursor = current_line:sub(1, cursor_col)
        local after_cursor = current_line:sub(cursor_col + 1)
        lines[current_line_idx] = before_cursor .. "<CURSOR>" .. after_cursor
    end

    local context = table.concat(lines, "\n")

    return context
end

--- Build prompt for LLM from context and metadata
---@param context string The code context
---@param filetype string The file type
---@param filename string The file name
---@return string The complete prompt text
function M.build_prompt(context, filetype, filename)
    local prompt_parts = {}

    if filetype ~= "" then
        table.insert(prompt_parts, "Language: " .. filetype)
    end

    if filename ~= "untitled" then
        table.insert(prompt_parts, "File: " .. filename)
    end

    table.insert(prompt_parts, "")
    table.insert(prompt_parts, "Complete only the function or statement at the <CURSOR> position. Do not complete other parts of the code:")
    table.insert(prompt_parts, "")
    table.insert(prompt_parts, context)

    return table.concat(prompt_parts, "\n")
end

--- Build prompt for word completion
---@param callback function Callback called with (prompt_text: string)
---@return nil
function M.build_prompt_for_completion(callback)
    local bufnr = vim.api.nvim_get_current_buf()

    -- Get filetype and filename
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    local filename = vim.api.nvim_buf_get_name(bufnr)
    filename = filename ~= "" and vim.fn.fnamemodify(filename, ":t") or "untitled"
    -- Get context without the partial word
    local context = M.get_context_for_completion()

    -- Get context lines for enhanced symbol detection
    local context_lines = vim.split(context, "\n")

    local prompt = M.build_prompt(context, filetype, filename)
    callback(prompt)
end

--- Get word boundary at cursor position
---@return table Word boundary info {row: number, col: number}
function M.get_word_boundary()
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  -- Find the start of the current word
  local start_col = cursor_col
  while start_col > 1 do
    local char = line:sub(start_col - 1, start_col - 1)
    if char:match("[%s%p]") and char ~= "_" then
      break
    end
    start_col = start_col - 1
  end

  -- Find the end of the current word
  local end_col = cursor_col
  while end_col < #line do
    local char = line:sub(end_col + 1, end_col + 1)
    if char:match("[%s%p]") and char ~= "_" then
      break
    end
    end_col = end_col + 1
  end

  local result = {
    row = cursor_line - 1,
    col = start_col,
    end_col = end_col
  }

  debug.log_completion("word_boundary", {
    cursor_line = cursor_line,
    cursor_col = cursor_col,
    line = line,
    start_col = start_col,
    end_col = end_col,
    full_word = line:sub(start_col, end_col),
    word_before_cursor = line:sub(start_col, cursor_col),
    result = result
  })

  return result
end

return M
