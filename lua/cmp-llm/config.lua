---@class CmpLlmConfig
---@field api_key string OpenAI API key
---@field model string OpenAI model name
---@field max_tokens number Maximum tokens to generate
---@field temperature number Temperature for generation (0-1)
---@field max_lines_before number Context lines before cursor
---@field max_lines_after number Context lines after cursor
---@field max_completion_items number Maximum completion items to show
---@field enabled boolean Whether the plugin is enabled
---@field num_candidates number Number of completion candidates to generate
---@field timeout number Request timeout in milliseconds
---@field base_url string OpenAI API base URL
---@field debounce_ms number Debounce time in milliseconds
---@field log_level string Log level (debug, info, warn, error)
---@field lsp_integration table LSP integration configuration
---@field debug table Debug configuration

local M = {}

--- Default configuration values
---@type CmpLlmConfig
M.defaults = {
  api_key = vim.env.OPENAI_API_KEY or "",
  model = "gpt-3.5-turbo",
  max_tokens = 100,
  temperature = 0.1,
  max_lines_before = 20,
  max_lines_after = 2,
  max_completion_items = 10,
  num_candidates = 3,                 -- Number of completion candidates to generate
  timeout = 5000,
  base_url = "https://api.openai.com/v1/chat/completions",
  debounce_ms = 300,
  enabled = true,
  log_level = "warn",
  debug = {
    enabled = false,                -- Enable debug mode
    log_api_requests = false,       -- Log full API requests
    log_api_responses = false,      -- Log full API responses (success and failure)
    log_prompts = false,            -- Log the complete prompt sent to LLM
    log_completions = false,        -- Log completion processing details
    log_lsp_requests = false,       -- Log LSP definition requests
    output_to_file = false,         -- Output debug info to file instead of notifications
    debug_file = "/tmp/cmp-llm-debug.log", -- Debug log file path
  },
  lsp_integration = {
    enabled = true,
    timeout = 2000,
    max_definitions = 3,
    context_lines_before = 5,
    context_lines_after = 5,
    -- Enhanced context features (off by default)
    multiple_symbols = false,          -- Detect and lookup multiple symbols in context
    smart_selection = false,           -- Prioritize symbols by usage/importance
    enhanced_extraction = false,       -- Include imports, classes, type info
    contextual_relevance = false,      -- Include related functions/classes
    structured_prompt = false,         -- Organize context by relevance
  }
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