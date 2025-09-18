# cmp-llm

A Neovim completion source for [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) that provides AI-powered code completions using OpenAI's language models.

## Features

- 🤖 AI-powered code completions using OpenAI API
- ⚡ Asynchronous, non-blocking requests
- 🎯 Intelligent context gathering around cursor position
- 🔍 LSP integration for symbol definition lookup
- 🔧 Highly configurable
- 📝 Support for all file types
- 🚫 Built-in debouncing to prevent excessive API calls
- 🔍 Contextual completions based on surrounding code

## Requirements

- Neovim >= 0.7.0
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- OpenAI API key
- (Optional) LSP server for enhanced context via symbol definitions

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/cmp-llm",
  dependencies = {
    "hrsh7th/nvim-cmp",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("cmp-llm").setup({
      -- your configuration here
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/cmp-llm",
  requires = {
    "hrsh7th/nvim-cmp",
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("cmp-llm").setup({
      -- your configuration here
    })
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'hrsh7th/nvim-cmp'
Plug 'nvim-lua/plenary.nvim'
Plug 'your-username/cmp-llm'
```

## Configuration

### API Key Setup

Set your OpenAI API key as an environment variable:

```bash
export OPENAI_API_KEY="your-api-key-here"
```

Or pass it directly in the setup configuration:

```lua
require("cmp-llm").setup({
  api_key = "your-api-key-here",
})
```

### Basic Setup

```lua
-- Setup cmp-llm
require("cmp-llm").setup({
  -- Optional: Override default settings
})

-- Setup nvim-cmp with the llm source
local cmp = require("cmp")
cmp.setup({
  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "llm" }, -- Add the llm source
    { name = "buffer" },
  }),
  -- Your other cmp configuration...
})
```

### Advanced Configuration

```lua
require("cmp-llm").setup({
  -- OpenAI API configuration
  api_key = vim.env.OPENAI_API_KEY, -- or set directly
  model = "gpt-3.5-turbo",          -- or "gpt-4", "gpt-4-turbo", etc.
  base_url = "https://api.openai.com/v1/chat/completions",

  -- Completion behavior
  max_tokens = 100,                 -- Maximum tokens in completion
  temperature = 0.1,                -- Lower = more deterministic
  num_candidates = 3,               -- Number of completion candidates to generate
  max_completion_items = 10,        -- Max items to show in completion menu

  -- Context gathering
  max_lines_before = 20,            -- Lines of context before cursor
  max_lines_after = 5,              -- Lines of context after cursor

  -- LSP Integration
  lsp_integration = {
    enabled = true,                 -- Enable LSP integration
    timeout = 2000,                 -- LSP request timeout in milliseconds
    max_definitions = 3,            -- Maximum number of definitions to include
    context_lines_before = 5,       -- Lines of context before definition
    context_lines_after = 5,        -- Lines of context after definition

    -- Enhanced context features (off by default)
    multiple_symbols = false,        -- Detect multiple symbols in context (vs just cursor)
    smart_selection = false,         -- Prioritize symbols by usage/importance
    enhanced_extraction = false,     -- Include imports, classes, type info
    contextual_relevance = false,    -- Include related functions/classes
    structured_prompt = false,       -- Organize context by relevance
  },

  -- Performance
  timeout = 5000,                   -- Request timeout in milliseconds
  debounce_ms = 300,                -- Debounce time for requests

  -- Other options
  enabled = true,                   -- Enable/disable the plugin
  log_level = "warn",               -- "debug", "info", "warn", "error"
})
```

## Usage

Once configured, the plugin will automatically provide AI completions in your nvim-cmp completion menu. The completions will appear with labels like "AI completion #1", "AI completion #2", etc., and will show the full completion content when focused.

### Multiple Completion Candidates

By default, the plugin generates **3 completion candidates** for each request, giving you multiple options to choose from. You can adjust this with the `num_candidates` setting:

```lua
require("cmp-llm").setup({
  num_candidates = 5,  -- Generate 5 different completion options
})
```

Each candidate will be shown as a separate item in the completion menu:
- **Label**: Shows the first line of the completion
- **Detail**: "AI completion #1", "AI completion #2", etc.
- **Source/Type**: "llm" (clearly identifies LLM completions)
- **Documentation**: Shows the full completion content when focused

This allows you to:
- **Distinguish LLM completions** from other sources (LSP, buffer, etc.)
- Compare different completion approaches
- Choose the most appropriate option for your context
- Get diverse suggestions for the same prompt

### Trigger Completions

Completions are triggered automatically when:
- Typing after certain characters (`.`, `:`, `(`, `[`, spaces, tabs)
- Using your configured nvim-cmp trigger keys
- The plugin intelligently gathers context around your cursor and sends it to the OpenAI API

### Context Gathering

The plugin automatically gathers intelligent context by:
- Including lines before and after your cursor position
- Preserving proper indentation and code structure
- Adding file type and filename information
- Marking the exact cursor position in the prompt

### LSP Integration

When LSP integration is enabled (default), the plugin enhances completions by:
- **Symbol Definition Lookup**: Automatically finds definitions of symbols near the cursor
- **Enhanced Context**: Includes relevant function/class definitions in the prompt
- **Multi-file Awareness**: Pulls context from imported modules and dependencies
- **Configurable Scope**: Control how many definitions and context lines to include

The LSP integration works with any LSP server supported by Neovim and provides much more accurate completions by giving the AI model access to relevant symbol definitions and their implementations.

### Enhanced Context Features

The plugin includes 5 advanced context features that are **disabled by default** for performance. Enable them individually based on your needs:

#### 1. Multiple Symbol Detection (`multiple_symbols = true`)
- **Default**: Only looks up symbol at cursor
- **Enhanced**: Detects and looks up multiple symbols in the current context
- **Benefit**: More comprehensive context for complex code
- **Cost**: More LSP requests, higher token usage

#### 2. Smart Symbol Selection (`smart_selection = true`)
- **Default**: Processes symbols in discovery order
- **Enhanced**: Prioritizes symbols by length and relevance, excludes common keywords
- **Benefit**: More relevant definitions included
- **Cost**: Additional processing time

#### 3. Enhanced Context Extraction (`enhanced_extraction = true`)
- **Default**: Only includes basic symbol definition
- **Enhanced**: Includes imports, class context, and type information
- **Benefit**: Much richer context with dependencies and type info
- **Cost**: Higher token usage, more file I/O

#### 4. Contextual Relevance (`contextual_relevance = true`)
- **Default**: All definitions treated equally
- **Enhanced**: Groups definitions by relevance (same file, class context, etc.)
- **Benefit**: More important context prioritized
- **Cost**: Additional analysis overhead

#### 5. Structured Prompt Organization (`structured_prompt = true`)
- **Default**: Simple definition list
- **Enhanced**: Organized sections (imports, primary definitions, related context)
- **Benefit**: Better organized context for AI model
- **Cost**: More complex prompt structure

### Usage Examples

**Basic LSP Integration:**
```lua
require("cmp-llm").setup({
  lsp_integration = {
    enabled = true,  -- Just basic symbol lookup
  }
})
```

**Full Enhanced Context:**
```lua
require("cmp-llm").setup({
  lsp_integration = {
    enabled = true,
    multiple_symbols = true,
    smart_selection = true,
    enhanced_extraction = true,
    contextual_relevance = true,
    structured_prompt = true,
  }
})
```

Example: When completing inside a function that calls `myFunction()`, the plugin will automatically look up the definition of `myFunction` and include it in the context sent to the AI model.

## Performance Considerations

- **Debouncing**: Requests are debounced to prevent excessive API calls
- **Asynchronous**: All API requests are non-blocking
- **Context Limits**: Configurable limits on context size to manage token usage
- **Timeout Handling**: Requests timeout after 5 seconds by default
- **Error Handling**: Graceful handling of API errors and network issues

## Troubleshooting

### No completions appearing

1. Ensure your OpenAI API key is set correctly
2. Check that nvim-cmp is configured with the "llm" source
3. Verify plenary.nvim is installed
4. Check `:messages` for any error messages

### API key issues

```lua
-- Check if API key is loaded
:lua print(require("cmp-llm.config").get().api_key)
```

### Enable debug logging

```lua
require("cmp-llm").setup({
  log_level = "debug",
})
```

### Common issues

- **Rate limits**: OpenAI API has rate limits; reduce `max_completion_items` if needed
- **Large files**: Reduce `max_lines_before` and `max_lines_after` for better performance
- **Network issues**: Increase `timeout` if you have slow internet connection

## Debugging

When the plugin isn't working as expected, you can enable comprehensive debugging to see exactly what's happening with API requests, responses, and LSP integration.

### Quick Debug Setup

Enable all debugging with notifications:
```vim
:CmpLlmDebugEnable
```

Disable debugging:
```vim
:CmpLlmDebugDisable
```

### Advanced Debug Configuration

For detailed debugging, configure in your setup:

```lua
require("cmp-llm").setup({
  -- Your normal config...
  debug = {
    enabled = true,                    -- Enable debug mode
    log_api_requests = true,           -- Log full API requests (including prompts)
    log_api_responses = true,          -- Log full API responses (success and failures)
    log_prompts = true,                -- Log the complete prompt sent to LLM
    log_completions = true,            -- Log completion processing details
    log_lsp_requests = true,           -- Log LSP definition requests
    output_to_file = true,             -- Output to file instead of notifications
    debug_file = "/tmp/cmp-llm-debug.log", -- Debug log file path
  }
})
```

### Debug Commands

- `:CmpLlmDebugEnable` - Enable debug mode with notifications
- `:CmpLlmDebugDisable` - Disable debug mode
- `:CmpLlmDebugShow` - Open debug log file (when `output_to_file = true`)
- `:CmpLlmDebugClear` - Clear debug log file

### What Debug Mode Shows

When debugging is enabled, you'll see detailed information about:

1. **API Requests**: Full request body, headers, and URL
2. **API Responses**: Complete response including error details
3. **Prompts**: The exact prompt sent to the LLM (including LSP context)
4. **LSP Integration**: Symbol detection, definition lookup results
5. **Completion Processing**: How responses are parsed and filtered
6. **Performance**: Request timing and token usage

### Example Debug Output

```
[2024-01-15 10:30:45] [PROMPT] [INFO] Complete prompt sent to LLM:
Language: lua
File: test.lua

--- Enhanced Context ---
## Primary Definitions:
**Function 'my_function'** (line 15):
```
function my_function(param)
  return param * 2
end
```

Complete the code at the <CURSOR> position:
local result = my_function(<CURSOR>

[2024-01-15 10:30:46] [API_RESPONSE] [INFO] API response received
{
  "choices": [
    {
      "message": {
        "content": "42)"
      }
    }
  ],
  "usage": {
    "prompt_tokens": 150,
    "completion_tokens": 2
  }
}
```

This debugging information helps you understand:
- Whether LSP definitions are being found
- What context is being sent to the LLM
- How the LLM is responding
- Any errors in the process

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) for the completion framework
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for async HTTP requests
- OpenAI for providing the language models