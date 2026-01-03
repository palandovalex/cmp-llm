# cmp-llm

A Neovim completion source for [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) that provides AI-powered code completions using OpenAI's language models.

## Features

- **AI-powered code completions** using OpenAI API
- **Movement-based context**: Use any vim movement (like `2{`, `10k`, `5j`) to define context boundaries
- **Visual processing indicators**: Robot emoji (🤖) shows when LLM is processing
- **Built-in debouncing** to prevent excessive API calls
- **Comprehensive debugging** with detailed logging and commands

## Requirements

- Neovim >= 0.7.0
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- OpenAI API key

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "zzhirong/cmp-llm",
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

## Configuration

### Basic Setup

```lua
-- Setup cmp-llm with movement-based context
require("cmp-llm").setup({
  api_key = vim.env.OPENAI_API_KEY, -- or set directly
  model = "gpt-3.5-turbo",          -- or "gpt-4", "gpt-4-turbo", etc.
  base_url = "https://api.openai.com/v1/chat/completions",
})
```

### Include the `llm` source in your `cmp.setup`

```lua
require("cmp").setup({
  sources = {
    -- ...
    { name = "llm" },
    -- ...
  },
})
```

### Advanced Configuration

```lua
require("cmp-llm").setup({
  -- Completion behavior
  max_tokens = 100,                 -- Maximum tokens in completion
  temperature = 0.1,                -- Lower = more deterministic
  num_candidates = 3,               -- Number of completion candidates to generate
  max_completion_items = 10,        -- Max items to show in completion menu

  -- Context gathering using vim movements
  context_before = "2{",            -- Vim movement for backward context
  context_after = "2}",             -- Vim movement for forward context

  -- Performance
  timeout = 5000,                   -- Request timeout in milliseconds
  debounce_ms = 1000,               -- Debounce time for requests
})
```

## Usage

Once configured, the plugin will automatically provide AI completions in your nvim-cmp completion menu.

### Context Gathering

The plugin uses **vim movements** to intelligently gather code context around your cursor position. This approach is both flexible and vim-native, allowing you to use any movement command you're familiar with.

#### Configuration

```lua
require("cmp-llm").setup({
  context_before = "2{",    -- Move 2 paragraphs backward
  context_after = "2}",     -- Move 2 paragraphs forward
})
```

#### Popular Movement Examples

- **Paragraph movements**: `"2{"`, `"3}"` - Structure-aware context based on code blocks
- **Line movements**: `"10k"`, `"5j"` - Traditional line-based context
- **Word movements**: `"20b"`, `"10w"` - Word-boundary context
- **Screen movements**: `"H"`, `"L"` - Context based on screen position
- **Search movements**: `"/function"`, `"?class"` - Context based on code patterns
- **Custom combinations**: `"5j3w"`, `"2{10k"` - Complex movement sequences

#### Advanced Movement Examples

**For different coding scenarios:**

```lua
-- For functions and classes (recommended for most code)
context_before = "2{",  -- 2 code blocks backward
context_after = "1}",   -- 1 code block forward

-- For quick, focused context
context_before = "10k", -- 10 lines up
context_after = "3j",   -- 3 lines down

-- For method-level context in classes
context_before = "[[",  -- Start of current section
context_after = "]]",   -- End of current section

-- For comprehensive context
context_before = "gg",  -- Beginning of file
context_after = "G",    -- End of file (use with caution - high token usage!)

-- Advanced vim movements work too!
context_before = "/function",  -- Search backward for "function"
context_after = "?class",      -- Search forward for "class"
context_before = "5w",          -- 5 words backward
context_after = "3e",           -- 3 word-ends forward
```

**How it works under the hood:**
The plugin uses vim's `operatorfunc` mechanism with `g@` to evaluate movements without any visual feedback. The movement-based approach gives you the full power of vim's text navigation, making context gathering as flexible and intuitive as vim itself!

### Visual Processing Indicators

The plugin provides visual feedback during LLM processing with a **robot sign column indicator** (🤖) that appears at the line where you triggered completion. The indicator automatically disappears when processing is complete.

If you ever need to manually clear indicators (e.g., after errors), use:
```vim
:CmpLlmClearIndicators
```

## Performance Considerations

- **Debouncing**: Requests are debounced to prevent excessive API calls
- **Timeout Handling**: Requests timeout after 5 seconds by default
- **Smart Context**: Movement-based context gathering ensures optimal token usage

## Troubleshooting

### No completions appearing

1. Ensure your OpenAI API key is set correctly
2. Check that nvim-cmp is configured with the "llm" source
3. Enable debug logging.

### API key issues

```lua
-- Check if API key is loaded
:lua print(require("cmp-llm.config").get().api_key)
```

### Enable debug logging

```lua
require("cmp-llm").setup({
  debug = {
    enabled = true,                    -- Enable debug mode
  }
})
```

### Common issues

- **Rate limits**: OpenAI API has rate limits; reduce `max_completion_items` if needed
- **Large files**: Use more targeted movements for better performance
- **Network issues**: Increase `timeout` if you have slow internet connection

## Debugging logging

When the plugin isn't working as expected, you can enable comprehensive debugging to see exactly what's happening with API requests, responses, and processing details.

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
3. **Prompts**: The exact prompt sent to the LLM (including context)
4. **Completion Processing**: How responses are parsed and filtered
5. **Performance**: Request timing and token usage
6. **Context Gathering**: Movement-based context extraction details

### Example Debug Output

```
[2024-01-15 10:30:45] [PROMPT] [INFO] Complete prompt sent to LLM:
Language: lua
File: test.lua

Complete only the function or statement at the <CURSOR> position. Do not complete other parts of the code:

local function my_function(param)
  return param * 2
end

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
- What context is being sent to the LLM
- How the LLM is responding
- Any errors in the process
- Performance metrics

## Testing

You can test the plugin functionality with the built-in test command:

```vim
:CmpLlmTest
```

This will test the LLM source availability and trigger a sample completion request to verify your setup is working correctly.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details.

## Acknowledgments

- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) for the completion framework
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for async HTTP requests
