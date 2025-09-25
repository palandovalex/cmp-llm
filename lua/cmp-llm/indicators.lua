local M = {}

--- Sign configuration for the processing indicator
local SIGN_NAME = "CmpLlmProcessing"
local SIGN_TEXT = "🤖"  -- Robot emoji
local SIGN_HL = "CmpLlmProcessingSign"

--- Current sign state tracking
local current_signs = {}  -- { bufnr = { line_number = sign_id, ... }, ... }
local sign_counter = 1

--- Initialize sign definition
---@return nil
function M.setup()
  -- Define the sign
  vim.fn.sign_define(SIGN_NAME, {
    text = SIGN_TEXT,
    texthl = SIGN_HL,
    culhl = "",
    numhl = ""
  })

  -- Define highlight group for the sign
  vim.api.nvim_set_hl(0, SIGN_HL, {
    fg = "#61AFEF",  -- Blue color (you can customize this)
    bold = true
  })
end

--- Show processing indicator at cursor position
---@return table indicator_info Information about the placed indicator {bufnr: number, line: number, sign_id: number}
function M.show_processing()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Generate unique sign ID
  local sign_id = sign_counter
  sign_counter = sign_counter + 1

  -- Place the sign
  vim.fn.sign_place(sign_id, "", SIGN_NAME, bufnr, {
    lnum = cursor_line,
    priority = 10
  })

  -- Track the sign
  if not current_signs[bufnr] then
    current_signs[bufnr] = {}
  end
  current_signs[bufnr][cursor_line] = sign_id

  local indicator_info = {
    bufnr = bufnr,
    line = cursor_line,
    sign_id = sign_id
  }

  return indicator_info
end

--- Hide processing indicator by indicator info
---@param indicator_info table The indicator info returned by show_processing()
---@return nil
function M.hide_processing(indicator_info)
  if not indicator_info then
    return
  end

  local bufnr = indicator_info.bufnr
  local line = indicator_info.line
  local sign_id = indicator_info.sign_id

  -- Remove the sign
  vim.fn.sign_unplace("", {
    buffer = bufnr,
    id = sign_id
  })

  -- Remove from tracking
  if current_signs[bufnr] and current_signs[bufnr][line] == sign_id then
    current_signs[bufnr][line] = nil

    -- Clean up empty buffer entries
    local has_signs = false
    for _ in pairs(current_signs[bufnr]) do
      has_signs = true
      break
    end
    if not has_signs then
      current_signs[bufnr] = nil
    end
  end
end

--- Hide all processing indicators for a buffer
---@param bufnr number Buffer number (optional, defaults to current buffer)
---@return nil
function M.hide_all_processing(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not current_signs[bufnr] then
    return
  end

  -- Remove all signs for this buffer
  for line, sign_id in pairs(current_signs[bufnr]) do
    vim.fn.sign_unplace("", {
      buffer = bufnr,
      id = sign_id
    })
  end

  -- Clear tracking
  current_signs[bufnr] = nil
end

--- Check if there's a processing indicator at a specific line
---@param bufnr number Buffer number
---@param line number Line number (1-indexed)
---@return boolean has_indicator Whether there's an indicator at that position
function M.has_processing_at_line(bufnr, line)
  return current_signs[bufnr] and current_signs[bufnr][line] ~= nil
end

--- Get indicator info for a specific position
---@param bufnr number Buffer number
---@param line number Line number (1-indexed)
---@return table? indicator_info The indicator info if it exists
function M.get_indicator_at_line(bufnr, line)
  if not current_signs[bufnr] or not current_signs[bufnr][line] then
    return nil
  end

  return {
    bufnr = bufnr,
    line = line,
    sign_id = current_signs[bufnr][line]
  }
end

--- Clean up all indicators when plugin is disabled or on error
---@return nil
function M.cleanup_all()
  for bufnr, _ in pairs(current_signs) do
    M.hide_all_processing(bufnr)
  end
  current_signs = {}
end

return M