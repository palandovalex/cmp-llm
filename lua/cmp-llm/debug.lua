local config = require("cmp-llm.config")

local M = {}

--- Get current timestamp in YYYY-MM-DD HH:MM:SS format
---@return string Formatted timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

--- Log a message with category, level, and optional data
---@param category string Log category (api_request, api_response, prompt, completion, lsp, general)
---@param level string Log level (debug, info, warn, error)
---@param message string The log message
---@param data? any Optional data to include in the log (table will be pretty-printed)
---@return nil
function M.log(category, level, message, data)
  local cfg = config.get()

  if not cfg.debug.enabled then
    return
  end

  -- Check if this category is enabled
  local category_enabled = false
  if category == "api_request" and cfg.debug.log_api_requests then
    category_enabled = true
  elseif category == "api_response" and cfg.debug.log_api_responses then
    category_enabled = true
  elseif category == "prompt" and cfg.debug.log_prompts then
    category_enabled = true
  elseif category == "completion" and cfg.debug.log_completions then
    category_enabled = true
  elseif category == "lsp" and cfg.debug.log_lsp_requests then
    category_enabled = true
  elseif category == "general" then
    category_enabled = true
  end

  if not category_enabled then
    return
  end

  local log_line = string.format("[%s] [%s] [%s] %s",
    get_timestamp(), string.upper(category), string.upper(level), message)

  if data then
    if type(data) == "table" then
      log_line = log_line .. "\n" .. vim.inspect(data, { indent = "  ", depth = 3 })
    else
      log_line = log_line .. "\n" .. tostring(data)
    end
  end

  if cfg.debug.output_to_file then
    M.write_to_file(log_line)
  else
    M.notify_user(level, log_line)
  end
end

--- Write content to the debug log file
---@param content string Content to write to the debug file
---@return nil
function M.write_to_file(content)
  local cfg = config.get()
  local file = io.open(cfg.debug.debug_file, "a")
  if file then
    file:write(content .. "\n\n")
    file:close()
  else
    vim.notify("cmp-llm: Failed to write to debug file: " .. cfg.debug.debug_file, vim.log.levels.ERROR)
  end
end

--- Notify user with appropriate log level
---@param level string Log level (debug, info, warn, error)
---@param message string The message to display
---@return nil
function M.notify_user(level, message)
  local log_levels = {
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR
  }

  local vim_level = log_levels[level] or vim.log.levels.INFO
  vim.notify(message, vim_level)
end

--- Clear the debug log file
---@return nil
function M.clear_debug_file()
  local cfg = config.get()
  if cfg.debug.output_to_file then
    local file = io.open(cfg.debug.debug_file, "w")
    if file then
      file:write("")
      file:close()
      vim.notify("cmp-llm: Debug file cleared: " .. cfg.debug.debug_file, vim.log.levels.INFO)
    end
  end
end

-- Convenience functions for different categories
--- Log API request details
---@param url string The API URL being called
---@param headers table Request headers
---@param body string Request body (JSON string)
---@return nil
function M.log_api_request(url, headers, body)
  -- Create a copy of headers without sensitive information
  local safe_headers = {}
  for k, v in pairs(headers) do
    if k:lower() == "authorization" then
      safe_headers[k] = "<api-key>"
    else
      safe_headers[k] = v
    end
  end

  M.log("api_request", "info", "Making API request to: " .. url, {
    headers = safe_headers,
    body = vim.json.decode(body)
  })
end

--- Log API response details
---@param status number HTTP status code
---@param body? string Response body
---@param error_msg? string Error message if request failed
---@return nil
function M.log_api_response(status, body, error_msg)
  if error_msg then
    M.log("api_response", "error", "API request failed: " .. error_msg, {
      status = status,
      body = body
    })
  else
    local parsed_body = nil
    if body then
      local ok, parsed = pcall(vim.json.decode, body)
      parsed_body = ok and parsed or body
    end

    M.log("api_response", "info", "API response received", {
      status = status,
      body = parsed_body
    })
  end
end

--- Log the complete prompt sent to LLM
---@param prompt_text string The complete prompt text
---@return nil
function M.log_prompt(prompt_text)
  M.log("prompt", "info", "Complete prompt sent to LLM:", prompt_text)
end

--- Log completion processing details
---@param phase string The completion phase (e.g., "started", "filtered", "completed")
---@param details any Details about the completion phase
---@return nil
function M.log_completion(phase, details)
  M.log("completion", "info", "Completion " .. phase, details)
end

--- Log LSP operation details
---@param action string The LSP action (e.g., "request", "response", "timeout")
---@param details any Details about the LSP operation
---@return nil
function M.log_lsp(action, details)
  M.log("lsp", "info", "LSP " .. action, details)
end

-- Commands for users to control debugging
--- Setup debug commands for user control
---@return nil
function M.setup_commands()
  vim.api.nvim_create_user_command("CmpLlmDebugEnable", function()
    local cfg = config.get()
    cfg.debug.enabled = true
    cfg.debug.log_api_requests = true
    cfg.debug.log_api_responses = true
    cfg.debug.log_prompts = true
    cfg.debug.log_completions = true
    vim.notify("cmp-llm: Debug mode enabled", vim.log.levels.INFO)
  end, { desc = "Enable cmp-llm debug mode" })

  vim.api.nvim_create_user_command("CmpLlmDebugDisable", function()
    local cfg = config.get()
    cfg.debug.enabled = false
    vim.notify("cmp-llm: Debug mode disabled", vim.log.levels.INFO)
  end, { desc = "Disable cmp-llm debug mode" })

  vim.api.nvim_create_user_command("CmpLlmDebugClear", function()
    M.clear_debug_file()
  end, { desc = "Clear cmp-llm debug log file" })

  vim.api.nvim_create_user_command("CmpLlmDebugShow", function()
    local cfg = config.get()
    if cfg.debug.output_to_file then
      vim.cmd("edit " .. cfg.debug.debug_file)
    else
      vim.notify("cmp-llm: Debug output is set to notifications, not file", vim.log.levels.INFO)
    end
  end, { desc = "Show cmp-llm debug log file" })
end

return M