local curl = require("plenary.curl")
local config = require("cmp-llm.config")
local debug = require("cmp-llm.debug")

local M = {}

--- Internal logging function with level filtering
---@param level string Log level (debug, info, warn, error)
---@param message string The message to log
---@return nil
local function log(level, message)
  local log_levels = {
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR
  }

  local cfg = config.get()
  local current_level = log_levels[cfg.log_level] or vim.log.levels.WARN
  local msg_level = log_levels[level] or vim.log.levels.INFO

  if msg_level >= current_level then
    vim.notify("cmp-llm: " .. message, msg_level)
  end
end

--- Generate code completions using OpenAI API
---@param prompt string The complete prompt text to send to the LLM
---@param callback function Callback function called with (completions: string[]?, error_msg: string?)
---@return nil
function M.complete(prompt, callback)
  local cfg = config.get()

  if not cfg.enabled then
    debug.log_completion("skipped", "Plugin disabled")
    callback(nil, "Plugin disabled")
    return
  end

  if cfg.api_key == "" then
    debug.log_completion("failed", "No API key configured")
    callback(nil, "No API key configured")
    return
  end

  local body = {
    model = cfg.model,
    messages = {
      {
        role = "system",
        content = "You are a code completion assistant. Complete the given code context with the most appropriate continuation. Respond only with the completion code, no explanations or markdown formatting. Provide diverse completion options when multiple candidates are requested."
      },
      {
        role = "user",
        content = prompt
      }
    },
    max_tokens = cfg.max_tokens,
    temperature = cfg.temperature,
    n = cfg.num_candidates,
    stream = false
  }

  local body_json = vim.json.encode(body)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. cfg.api_key,
  }

  debug.log_prompt(prompt)
  debug.log_api_request(cfg.base_url, headers, body_json)
  debug.log_completion("started", {
    model = cfg.model,
    max_tokens = cfg.max_tokens,
    temperature = cfg.temperature,
    prompt_length = #prompt
  })

  log("debug", "Making API request to " .. cfg.base_url)

  curl.post(cfg.base_url, {
    headers = headers,
    body = body_json,
    timeout = cfg.timeout,
    callback = function(response)
      debug.log_api_response(response.status, response.body, nil)

      if response.status ~= 200 then
        local error_msg = "API request failed with status: " .. response.status
        if response.body then
          local ok, parsed = pcall(vim.json.decode, response.body)
          if ok and parsed.error then
            error_msg = error_msg .. " - " .. (parsed.error.message or "Unknown error")
          end
        end
        log("error", error_msg)
        debug.log_completion("failed", {
          status = response.status,
          error = error_msg,
          body = response.body
        })
        callback(nil, error_msg)
        return
      end

      local ok, parsed = pcall(vim.json.decode, response.body)
      if not ok then
        local error_msg = "Failed to parse API response"
        log("error", error_msg)
        debug.log_completion("failed", {
          error = error_msg,
          body = response.body
        })
        callback(nil, error_msg)
        return
      end

      debug.log_completion("parsed", {
        choices_count = parsed.choices and #parsed.choices or 0,
        usage = parsed.usage
      })

      if not parsed.choices or #parsed.choices == 0 then
        local error_msg = "No completions returned from API"
        log("warn", error_msg)
        debug.log_completion("empty", parsed)
        callback({}, nil)
        return
      end

      local completions = {}
      for i, choice in ipairs(parsed.choices) do
        if choice.message and choice.message.content then
          local content = choice.message.content:gsub("^%s*", ""):gsub("%s*$", "")
          if content ~= "" then
            table.insert(completions, content)
          end
        end
      end

      log("debug", "Received " .. #completions .. " completions")
      debug.log_completion("success", {
        completions_count = #completions,
        completions = completions,
        raw_choices = parsed.choices
      })
      callback(completions, nil)
    end
  })
end

return M