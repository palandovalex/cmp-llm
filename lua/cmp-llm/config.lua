---@class CmpLlmConfig
---@field api_key string OpenAI API key
---@field model string OpenAI model name
---@field max_tokens number Maximum tokens to generate
---@field temperature number Temperature for generation (0-1)
---@field context_before string Vim movement command for backward context
---@field context_after string Vim movement command for forward context
---@field max_completion_items number Maximum completion items to show
---@field enabled boolean Whether the plugin is enabled
---@field num_candidates number Number of completion candidates to generate
---@field timeout number Request timeout in milliseconds
---@field base_url string OpenAI API base URL
---@field debounce_ms number Debounce time in milliseconds
---@field debug table Debug configuration

local M = {}

--- Default configuration values
---@type CmpLlmConfig
M.defaults = {
  api_key = vim.env.OPENAI_API_KEY or "",
  model = "gpt-3.5-turbo",
  max_tokens = 100,
  temperature = 0.1,
  -- Context gathering using vim movements
  context_before = "2{",               -- Move 2 paragraphs backward
  context_after = "2}",                -- Move 2 paragraphs forward
  max_completion_items = 10,
  num_candidates = 3,                 -- Number of completion candidates to generate
  timeout = 5000,
  base_url = "https://api.openai.com/v1/chat/completions",
  debounce_ms = 1000,
  enabled = true,
  debug = {
    enabled = false,                -- Enable debug mode
    log_api_requests = false,       -- Log full API requests
    log_api_responses = false,      -- Log full API responses (success and failure)
    log_prompts = false,            -- Log the complete prompt sent to LLM
    log_completions = false,        -- Log completion processing details
    output_to_file = false,         -- Output debug info to file instead of notifications
    debug_file = "/tmp/cmp-llm-debug.log", -- Debug log file path
  },
}

--- Current configuration state
---@type CmpLlmConfig
M.config = {}

--- Setup the configuration with user options
---@param opts? CmpLlmConfig User configuration options to override defaults
---@return nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})

  if M.config.api_key == "" then
    vim.notify("cmp-llm: No OpenAI API key found. Please set OPENAI_API_KEY environment variable or pass api_key in setup()", vim.log.levels.WARN)
  end
end

--- Get the current configuration
---@return CmpLlmConfig The current configuration table
function M.get()
  return M.config
end

return M
