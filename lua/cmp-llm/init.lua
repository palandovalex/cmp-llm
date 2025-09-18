local config = require("cmp-llm.config")
local debug = require("cmp-llm.debug")

local M = {}

--- Setup the cmp-llm plugin
---@param opts? CmpLlmConfig User configuration options
---@return nil
function M.setup(opts)
  config.setup(opts)

  local cmp = require("cmp")
  if not cmp then
    vim.notify("cmp-llm: nvim-cmp not found", vim.log.levels.ERROR)
    return
  end

  local source = require("cmp-llm.source")
  cmp.register_source("llm", source.new())

  -- Setup debug commands
  debug.setup_commands()

  -- Add test command
  vim.api.nvim_create_user_command('CmpLlmTest', function()
    local test_source = source.new()
    local test_request = {
      context = {
        cursor_before_line = "fu",
        cursor_after_line = "",
        cursor = {
          row = 1,
          col = 2
        }
      },
      option = {}
    }

    vim.notify("Testing LLM source availability: " .. tostring(test_source:is_available()))
    vim.notify("Testing LLM source complete...")

    test_source:complete(test_request, function(result)
      vim.notify("LLM test result: " .. vim.inspect(result))
    end)
  end, {})
end

return M