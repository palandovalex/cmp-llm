local curl = require("plenary.curl")
local config = require("cmp-llm.config")
local debug = require("cmp-llm.debug")

local M = {}

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
        content = "You are a code completion assistant. Complete the given code context with the most appropriate continuation. Respond only with the completion code, no explanations, no markdown formatting, and no markdown code fences. Provide diverse completion options when multiple candidates are requested."
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
        debug.log_completion("failed", {
          error = error_msg,
          body = response.body
        })
        callback(nil, error_msg)
        return
      end

      debug.log_completion("parsed", {
        choices_count = parsed.choices and #parsed.choices or 0,
        usage = parsed.usage,
        parsed = vim.inspect(parsed.choices),
      })

      if not parsed.choices or #parsed.choices == 0 then
        debug.log_completion("empty", parsed)
        callback({}, nil)
        return
      end

      local completions = {}
      for _, choice in ipairs(parsed.choices) do
        if choice.message and choice.message.content then
          local content = choice.message.content
          if content ~= "" then
            table.insert(completions, content)
          end
        end
      end

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
