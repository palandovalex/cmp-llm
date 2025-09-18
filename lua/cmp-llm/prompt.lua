local config = require("cmp-llm.config")
local lsp = require("cmp-llm.lsp")
local debug = require("cmp-llm.debug")

local M = {}

--- Get context around cursor for completion
---@return string context The code context with <CURSOR> marker
---@return string filetype The buffer filetype
---@return string filename The buffer filename
function M.get_context()
  local cfg = config.get()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

  cursor_line = cursor_line - 1

  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local start_line = math.max(0, cursor_line - cfg.max_lines_before)
  local end_line = math.min(total_lines - 1, cursor_line + cfg.max_lines_after)

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)

  local current_line_idx = cursor_line - start_line + 1
  if current_line_idx <= #lines then
    local current_line = lines[current_line_idx] or ""
    local before_cursor = current_line:sub(1, cursor_col)
    local after_cursor = current_line:sub(cursor_col + 1)

    lines[current_line_idx] = before_cursor .. "<CURSOR>" .. after_cursor
  end

  local context = table.concat(lines, "\n")

  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local filename = vim.api.nvim_buf_get_name(bufnr)
  filename = filename ~= "" and vim.fn.fnamemodify(filename, ":t") or "untitled"

  return context, filetype, filename
end

--- Get context for completion with partial word removed
---@param word_boundary table Word boundary info {row: number, col: number}
---@return string context The clean code context with <CURSOR> marker
---@return string filetype The buffer filetype
---@return string filename The buffer filename
function M.get_context_for_completion(word_boundary)
  local cfg = config.get()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

  cursor_line = cursor_line - 1

  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  local start_line = math.max(0, cursor_line - cfg.max_lines_before)
  local end_line = math.min(total_lines - 1, cursor_line + cfg.max_lines_after)

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line + 1, false)

  local current_line_idx = cursor_line - start_line + 1
  if current_line_idx <= #lines then
    local current_line = lines[current_line_idx] or ""

    -- Keep the partial word visible to LLM but mark completion point with <CURSOR>
    -- If cursor is inside a word, remove the part after cursor
    local before_cursor = current_line:sub(1, cursor_col)
    local after_word = ""
    if word_boundary.end_col and word_boundary.end_col > cursor_col then
      -- Remove the rest of the current word after cursor
      after_word = current_line:sub(word_boundary.end_col + 1)
      lines[current_line_idx] = before_cursor .. "<CURSOR>" .. after_word
    else
      local after_cursor = current_line:sub(cursor_col + 1)
      lines[current_line_idx] = before_cursor .. "<CURSOR>" .. after_cursor
    end
  end

  local context = table.concat(lines, "\n")

  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local filename = vim.api.nvim_buf_get_name(bufnr)
  filename = filename ~= "" and vim.fn.fnamemodify(filename, ":t") or "untitled"

  return context, filetype, filename
end

--- Build prompt for LLM from context and metadata
---@param context string The code context
---@param filetype string The file type
---@param filename string The file name
---@param definitions? table[] Optional LSP definitions
---@return string The complete prompt text
function M.build_prompt(context, filetype, filename, definitions)
  local prompt_parts = {}

  if filetype ~= "" then
    table.insert(prompt_parts, "Language: " .. filetype)
  end

  if filename ~= "untitled" then
    table.insert(prompt_parts, "File: " .. filename)
  end

  if definitions then
    table.insert(prompt_parts, lsp.format_definitions_for_prompt(definitions))
  end

  table.insert(prompt_parts, "")
  table.insert(prompt_parts, "Complete only the function or statement at the <CURSOR> position. Do not complete other parts of the code:")
  table.insert(prompt_parts, "")
  table.insert(prompt_parts, context)

  return table.concat(prompt_parts, "\n")
end

--- Build prompt with LSP integration for regular completion
---@param context string The code context
---@param filetype string The file type
---@param filename string The file name
---@param callback function Callback called with (prompt_text: string)
---@return nil
function M.build_prompt_with_lsp(context, filetype, filename, callback)
  local cfg = config.get()

  if not cfg.lsp_integration.enabled then
    callback(M.build_prompt(context, filetype, filename))
    return
  end

  -- Get context lines for enhanced symbol detection
  local context_lines = vim.split(context, "\n")

  lsp.find_definitions(context_lines, function(definitions)
    local prompt = M.build_prompt(context, filetype, filename, definitions)
    callback(prompt)
  end)
end

--- Build prompt with LSP integration for word completion
---@param word_boundary table Word boundary info {row: number, col: number}
---@param filetype string The file type
---@param filename string The file name
---@param callback function Callback called with (prompt_text: string)
---@return nil
function M.build_prompt_with_lsp_for_completion(word_boundary, filetype, filename, callback)
  local cfg = config.get()

  -- Get context without the partial word
  local context, filetype, filename = M.get_context_for_completion(word_boundary)

  if not cfg.lsp_integration.enabled then
    callback(M.build_prompt(context, filetype, filename))
    return
  end

  -- Get context lines for enhanced symbol detection
  local context_lines = vim.split(context, "\n")

  lsp.find_definitions(context_lines, function(definitions)
    local prompt = M.build_prompt(context, filetype, filename, definitions)
    callback(prompt)
  end)
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

--- Filter completion text against prefix for relevance
---@param completion_text string The raw completion from LLM
---@param prefix string The typed prefix to match against
---@return string? The filtered completion text or nil if not relevant
function M.filter_completion(completion_text, prefix)
  if not completion_text or completion_text == "" then
    debug.log_completion("filter_empty", {
      completion_text = completion_text,
      prefix = prefix
    })
    return nil
  end

  -- Remove code fences if present
  completion_text = completion_text:gsub("^```[%w]*\n?", "")  -- Remove opening fence
  completion_text = completion_text:gsub("\n?```$", "")      -- Remove closing fence
  completion_text = completion_text:gsub("^```[%w]*\n?(.-)```$", "%1")  -- Remove both if on same text

  -- For multi-line completions, look for the most relevant line that matches the prefix
  local lines = vim.split(completion_text, "\n")
  local relevant_line = nil
  local relevant_start_idx = nil
  local best_match_score = -1

  -- Find the best line that matches our prefix
  for i, line in ipairs(lines) do
    local trimmed_line = line:gsub("^%s*", "")

    -- Check for direct word matches (word starts with prefix)
    for word in trimmed_line:gmatch("(%w+)") do
      if word:lower():sub(1, #prefix) == prefix:lower() then
        local match_score = (#word / #prefix) + (20 / i)  -- Direct match gets high score
        if match_score > best_match_score then
          relevant_line = trimmed_line
          relevant_start_idx = i
          best_match_score = match_score
        end
      end
    end

    -- Check for continuation completions (prefix + word = complete word)
    for word in trimmed_line:gmatch("(%w+)") do
      local combined_word = prefix:lower() .. word:lower()
      -- If combining makes a longer, valid-looking identifier
      if #combined_word > #prefix and combined_word:match("^%w+$") then
        local match_score = (#combined_word / #prefix) + (30 / i)  -- Continuation gets highest score
        if match_score > best_match_score then
          relevant_line = trimmed_line
          relevant_start_idx = i
          best_match_score = match_score
        end
      end
    end
  end

  -- If we found a relevant line, extract from that point
  if relevant_line and relevant_start_idx then
    local relevant_completion = {}
    for i = relevant_start_idx, #lines do
      table.insert(relevant_completion, lines[i])
    end
    completion_text = table.concat(relevant_completion, "\n")
    lines = relevant_completion
  end

  local first_line = lines[1] or ""
  first_line = first_line:gsub("^%s*", "")

  debug.log_completion("filter_processing", {
    completion_text = completion_text,
    first_line = first_line,
    prefix = prefix,
    prefix_empty = (not prefix or prefix == ""),
    found_relevant_line = relevant_line ~= nil
  })

  -- If no prefix, accept the completion
  if not prefix or prefix == "" then
    debug.log_completion("filter_no_prefix", { result = first_line })
    return first_line
  end

  -- For completion replacement, be very lenient with prefix matching
  local prefix_lower = prefix:lower()
  local first_line_lower = first_line:lower()

  debug.log_completion("filter_comparison", {
    prefix_lower = prefix_lower,
    first_line_lower = first_line_lower,
    prefix_length = #prefix_lower,
    first_line_length = #first_line_lower
  })

  -- Smart completion matching: handle cases where LLM generates continuation
  -- If the prefix + first_line forms a valid word, reconstruct the full completion
  local combined_word = prefix_lower .. first_line_lower
  local accepts_completion = false
  local reason = ""
  local final_result = first_line

  -- Try to find a complete word that starts with prefix in the completion
  local words_in_completion = {}
  for word in completion_text:gmatch("(%w+)") do
    table.insert(words_in_completion, word)
  end

  -- Look for a word in the completion that starts with our prefix
  local matching_word = nil
  for _, word in ipairs(words_in_completion) do
    if word:lower():sub(1, #prefix_lower) == prefix_lower then
      matching_word = word
      break
    end
  end

  if matching_word then
    -- Found a word that starts with our prefix, use the full completion
    accepts_completion = true
    reason = "word_in_completion_match"
    final_result = first_line
    debug.log_completion("filter_matched", {
      result = final_result,
      prefix = prefix,
      matching_word = matching_word,
      reason = reason
    })
  elseif combined_word:match("^%w+$") and #combined_word > #prefix_lower then
    -- The prefix + continuation forms a valid word
    accepts_completion = true
    reason = "continuation_combination"
    final_result = first_line
    debug.log_completion("filter_matched", {
      result = final_result,
      prefix = prefix,
      combined_word = combined_word,
      reason = reason
    })
  end

  if accepts_completion then
    return final_result
  end

  -- Fallback to original logic for edge cases
  -- For code completion, if the completion starts with a common keyword that matches the prefix start, accept it
  -- Or if prefix is very short (like "fu" for "func"), be very lenient
  local fallback_accepts = false
  local fallback_reason = ""

  if #prefix_lower <= 3 then
    fallback_accepts = true
    fallback_reason = "short_prefix"
  elseif first_line_lower:sub(1, #prefix_lower) == prefix_lower then
    fallback_accepts = true
    fallback_reason = "starts_with_prefix"
  elseif first_line_lower:find(prefix_lower, 1, true) then
    fallback_accepts = true
    fallback_reason = "contains_prefix"
  else
    -- For code completion, also accept if the completion is a common language keyword
    -- that makes sense given the prefix (e.g., "fu" -> "func", "cl" -> "class", etc.)
    local common_completions = {
      fu = {"func", "function"},
      cl = {"class"},
      st = {"struct", "string"},
      ["in"] = {"int", "interface", "import"},
      re = {"return"},
      ["if"] = {"if"},
      fo = {"for"},
      wh = {"while"}
    }

    if common_completions[prefix_lower] then
      for _, completion_start in ipairs(common_completions[prefix_lower]) do
        if first_line_lower:sub(1, #completion_start) == completion_start then
          fallback_accepts = true
          fallback_reason = "common_completion"
          break
        end
      end
    end
  end

  if fallback_accepts then
    debug.log_completion("filter_matched", {
      result = first_line,
      prefix = prefix,
      first_line = first_line,
      reason = fallback_reason
    })
    return first_line
  end

  debug.log_completion("filter_rejected", {
    completion_text = completion_text,
    first_line = first_line,
    prefix = prefix,
    reason = "no_prefix_match"
  })

  -- Even if no match, still return the completion for now (very lenient)
  debug.log_completion("filter_fallback", {
    result = first_line,
    prefix = prefix,
    first_line = first_line,
    reason = "fallback_accept"
  })
  return first_line
end

return M