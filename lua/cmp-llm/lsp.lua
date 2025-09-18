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

--- Get the symbol at the cursor position
---@return string|nil The symbol at cursor, or nil if none found
function M.get_symbol_at_cursor()
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()

  local start_col = cursor_col
  local end_col = cursor_col

  while start_col > 1 do
    local char = line:sub(start_col - 1, start_col - 1)
    if not char:match("[%w_]") then
      break
    end
    start_col = start_col - 1
  end

  while end_col <= #line do
    local char = line:sub(end_col, end_col)
    if not char:match("[%w_]") then
      break
    end
    end_col = end_col + 1
  end

  if start_col <= end_col then
    return line:sub(start_col, end_col - 1)
  end

  return nil
end

--- Extract symbols from context lines
---@param context_lines string[] Array of context lines to search
---@return string[] Array of unique symbols found in context
function M.get_symbols_in_context(context_lines)
  local cfg = config.get()
  local symbols = {}
  local seen = {}

  if not cfg.lsp_integration.multiple_symbols then
    local symbol = M.get_symbol_at_cursor()
    return symbol and { symbol } or {}
  end

  for _, line in ipairs(context_lines) do
    local line_symbols = M.extract_symbols_from_line(line)
    for _, symbol in ipairs(line_symbols) do
      if not seen[symbol] and #symbol > 2 then  -- Ignore very short symbols
        seen[symbol] = true
        table.insert(symbols, symbol)
      end
    end
  end

  return symbols
end

--- Extract symbols from a single line using pattern matching
---@param line string The line to extract symbols from
---@return string[] Array of symbols found in the line
function M.extract_symbols_from_line(line)
  local symbols = {}
  -- Match function calls, variable references, etc.
  for symbol in line:gmatch("([%a_][%w_]*)[%(%.%s:]?") do
    table.insert(symbols, symbol)
  end
  return symbols
end

--- Prioritize symbols by relevance and specificity
---@param symbols string[] Array of symbols to prioritize
---@return string[] Array of symbols sorted by priority
function M.prioritize_symbols(symbols)
  local cfg = config.get()

  if not cfg.lsp_integration.smart_selection then
    return symbols
  end

  -- Simple prioritization: longer symbols first, common keywords last
  local keywords = { "if", "else", "for", "while", "return", "function", "local", "end" }
  local keyword_set = {}
  for _, kw in ipairs(keywords) do
    keyword_set[kw] = true
  end

  local prioritized = {}
  local low_priority = {}

  for _, symbol in ipairs(symbols) do
    if keyword_set[symbol] or #symbol < 3 then
      table.insert(low_priority, symbol)
    else
      table.insert(prioritized, symbol)
    end
  end

  -- Sort by length (longer symbols likely more specific)
  table.sort(prioritized, function(a, b) return #a > #b end)

  -- Combine prioritized + low priority
  for _, symbol in ipairs(low_priority) do
    table.insert(prioritized, symbol)
  end

  return prioritized
end

--- Find definitions for symbols in context lines
---@param context_lines string[]? Array of context lines to analyze
---@param callback function Callback called with (definitions: table[]?)
---@return nil
function M.find_definitions(context_lines, callback)
  local cfg = config.get()

  if not cfg.lsp_integration.enabled then
    debug.log_lsp("skipped", "LSP integration disabled")
    callback(nil)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_active_clients({ bufnr = bufnr })

  if #clients == 0 then
    log("debug", "No LSP clients active for current buffer")
    debug.log_lsp("no_clients", "No LSP clients active for current buffer")
    callback(nil)
    return
  end

  local symbols = M.get_symbols_in_context(context_lines or {})
  symbols = M.prioritize_symbols(symbols)

  debug.log_lsp("symbols_detected", {
    context_lines_count = context_lines and #context_lines or 0,
    symbols_found = symbols,
    symbols_count = #symbols
  })

  if #symbols == 0 then
    log("debug", "No symbols found in context")
    debug.log_lsp("no_symbols", "No symbols found in context")
    callback(nil)
    return
  end

  -- Limit symbols to process
  local max_symbols = math.min(#symbols, cfg.lsp_integration.max_definitions)
  local all_definitions = {}
  local completed_requests = 0
  local total_requests = max_symbols

  debug.log_lsp("starting_requests", {
    total_symbols = #symbols,
    max_symbols = max_symbols,
    symbols_to_process = vim.list_slice(symbols, 1, max_symbols)
  })

  local function check_completion()
    completed_requests = completed_requests + 1
    debug.log_lsp("request_completed", {
      completed = completed_requests,
      total = total_requests,
      definitions_so_far = #all_definitions
    })

    if completed_requests >= total_requests then
      debug.log_lsp("all_completed", {
        total_definitions = #all_definitions,
        definitions = all_definitions
      })
      callback(#all_definitions > 0 and all_definitions or nil)
    end
  end

  for i = 1, max_symbols do
    local symbol = symbols[i]
    M.find_single_definition(symbol, function(definition_info)
      if definition_info then
        vim.list_extend(all_definitions, definition_info)
        debug.log_lsp("definition_found", {
          symbol = symbol,
          definitions_count = #definition_info
        })
      else
        debug.log_lsp("definition_not_found", {
          symbol = symbol
        })
      end
      check_completion()
    end)
  end
end

--- Find definition for a single symbol
---@param symbol string The symbol to find definition for
---@param callback function Callback called with (definition_info: table[]?)
---@return nil
function M.find_single_definition(symbol, callback)
  local cfg = config.get()
  local bufnr = vim.api.nvim_get_current_buf()

  log("debug", "Looking up definition for symbol: " .. symbol)

  -- Try to find the symbol in the current buffer and get its position
  local symbol_pos = M.find_symbol_position(symbol)
  if not symbol_pos then
    callback(nil)
    return
  end

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(),
    position = symbol_pos
  }

  local timeout_timer = vim.loop.new_timer()
  local completed = false

  timeout_timer:start(cfg.lsp_integration.timeout, 0, function()
    if not completed then
      completed = true
      timeout_timer:stop()
      timeout_timer:close()
      log("debug", "LSP definition request timed out for symbol: " .. symbol)
      vim.schedule(function()
        callback(nil)
      end)
    end
  end)

  vim.lsp.buf_request(bufnr, 'textDocument/definition', params, function(err, result, ctx, config_)
    if completed then
      return
    end
    completed = true
    timeout_timer:stop()
    timeout_timer:close()

    if err then
      log("debug", "LSP definition request error for " .. symbol .. ": " .. tostring(err))
      callback(nil)
      return
    end

    if not result or vim.tbl_isempty(result) then
      log("debug", "No definition found for symbol: " .. symbol)
      callback(nil)
      return
    end

    local definition_info = M.extract_definition_info(result, symbol)
    callback(definition_info)
  end)
end

--- Find the position of a symbol in the buffer
---@param symbol string The symbol to find
---@return table|nil Position table with {line: number, character: number} or nil
function M.find_symbol_position(symbol)
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Search around cursor first
  local search_range = 10
  local start_line = math.max(1, cursor_line - search_range)
  local end_line = math.min(#lines, cursor_line + search_range)

  for i = start_line, end_line do
    local line = lines[i]
    local col = line:find(symbol, 1, true)
    if col then
      return { line = i - 1, character = col - 1 }
    end
  end

  -- Fallback to cursor position
  return { line = cursor_line - 1, character = cursor_col }
end

-- Backward compatibility
--- Backward compatibility function for single definition lookup
---@param callback function Callback called with (definitions: table[]?)
---@return nil
function M.find_definition(callback)
  local context_lines = { vim.api.nvim_get_current_line() }
  M.find_definitions(context_lines, callback)
end

--- Extract definition information from LSP result
---@param lsp_result table LSP definition result
---@param symbol string The symbol that was looked up
---@return table[]? Array of definition info tables or nil
function M.extract_definition_info(lsp_result, symbol)
  local cfg = config.get()
  local definitions = {}

  local result_list = vim.tbl_islist(lsp_result) and lsp_result or { lsp_result }

  for _, location in ipairs(result_list) do
    if #definitions >= cfg.lsp_integration.max_definitions then
      break
    end

    local uri = location.uri or (location.targetUri)
    local range = location.range or (location.targetRange)

    if uri and range then
      local filepath = vim.uri_to_fname(uri)
      local filename = vim.fn.fnamemodify(filepath, ":t")

      local ok, lines = pcall(vim.fn.readfile, filepath)
      if ok and lines then
        local def_info = M.extract_enhanced_context(lines, range, symbol, filepath, filename)
        if def_info then
          table.insert(definitions, def_info)
        end
      end
    end
  end

  return #definitions > 0 and definitions or nil
end

--- Extract enhanced context from definition location
---@param lines string[] Lines from the definition file
---@param range table LSP range object
---@param symbol string The symbol name
---@param filepath string Full path to the file
---@param filename string Base filename
---@return table? Definition info table or nil
function M.extract_enhanced_context(lines, range, symbol, filepath, filename)
  local cfg = config.get()
  local start_line = range.start.line
  local end_line = range["end"].line

  local context_start = math.max(0, start_line - cfg.lsp_integration.context_lines_before)
  local context_end = math.min(#lines - 1, end_line + cfg.lsp_integration.context_lines_after)

  local context_lines = {}
  for i = context_start + 1, context_end + 1 do
    if lines[i] then
      table.insert(context_lines, lines[i])
    end
  end

  if #context_lines == 0 then
    return nil
  end

  local def_info = {
    symbol = symbol,
    filename = filename,
    filepath = filepath,
    start_line = start_line + 1,
    end_line = end_line + 1,
    context = table.concat(context_lines, "\n")
  }

  -- Enhanced extraction features
  if cfg.lsp_integration.enhanced_extraction then
    def_info.imports = M.extract_imports(lines)
    def_info.class_context = M.extract_class_context(lines, start_line)
    def_info.type_info = M.extract_type_info(context_lines, symbol)
  end

  return def_info
end

--- Extract import statements from file lines
---@param lines string[] Array of file lines to search
---@return string[] Array of import statements found
function M.extract_imports(lines)
  local imports = {}
  local patterns = {
    "^import%s+(.+)$",           -- Python/JS: import module
    "^from%s+(.-)%s+import",     -- Python: from module import
    "^#include%s+[<\"'](.+)[>\"']", -- C/C++
    "^require%s*%(?['\"]([^'\"]+)", -- Lua/JS require
    "^local%s+%w+%s*=%s*require%s*%(?['\"]([^'\"]+)", -- Lua local require
  }

  for i = 1, math.min(50, #lines) do  -- Check first 50 lines
    local line = lines[i]:gsub("^%s+", "")  -- Remove leading whitespace
    for _, pattern in ipairs(patterns) do
      local match = line:match(pattern)
      if match then
        table.insert(imports, match)
      end
    end
  end

  return imports
end

--- Extract class context for a definition
---@param lines string[] Array of file lines
---@param definition_line number Line number of the definition
---@return table Class context info {type: string, name: string, line: number}
function M.extract_class_context(lines, definition_line)
  local class_info = {}

  -- Look backwards from definition to find class/interface/struct
  for i = definition_line, math.max(1, definition_line - 20), -1 do
    local line = lines[i]
    if line then
      -- Match class/interface/struct declarations
      local class_match = line:match("^%s*class%s+(%w+)")
      local interface_match = line:match("^%s*interface%s+(%w+)")
      local struct_match = line:match("^%s*struct%s+(%w+)")

      if class_match then
        class_info.type = "class"
        class_info.name = class_match
        class_info.line = i
        break
      elseif interface_match then
        class_info.type = "interface"
        class_info.name = interface_match
        class_info.line = i
        break
      elseif struct_match then
        class_info.type = "struct"
        class_info.name = struct_match
        class_info.line = i
        break
      end
    end
  end

  return class_info
end

--- Extract type information for a symbol
---@param context_lines string[] Array of context lines
---@param symbol string The symbol to extract type info for
---@return string[] Array of type information found
function M.extract_type_info(context_lines, symbol)
  local type_info = {}

  for _, line in ipairs(context_lines) do
    -- Match type annotations/declarations
    local type_patterns = {
      symbol .. "%s*:%s*(%w+)",      -- TypeScript/Python: symbol: type
      "(%w+)%s+" .. symbol,          -- C/C++/Java: type symbol
      "function%s+" .. symbol .. "%s*%((.-)%)", -- Function signature
    }

    for _, pattern in ipairs(type_patterns) do
      local match = line:match(pattern)
      if match then
        table.insert(type_info, match)
      end
    end
  end

  return type_info
end

--- Format definitions for inclusion in LLM prompt
---@param definitions table[]? Array of definition info tables
---@return string Formatted string for prompt inclusion
function M.format_definitions_for_prompt(definitions)
  if not definitions or #definitions == 0 then
    return ""
  end

  local cfg = config.get()

  if cfg.lsp_integration.structured_prompt then
    return M.format_structured_prompt(definitions)
  else
    return M.format_basic_prompt(definitions)
  end
end

--- Format definitions using basic prompt structure
---@param definitions table[] Array of definition info tables
---@return string Basic formatted definitions
function M.format_basic_prompt(definitions)
  local formatted = { "", "--- Symbol Definitions ---" }

  for _, def in ipairs(definitions) do
    table.insert(formatted, "")
    table.insert(formatted, string.format("Definition of '%s' in %s (line %d):",
      def.symbol, def.filename, def.start_line))
    table.insert(formatted, "```")
    table.insert(formatted, def.context)
    table.insert(formatted, "```")
  end

  table.insert(formatted, "--- End Definitions ---")
  table.insert(formatted, "")

  return table.concat(formatted, "\n")
end

--- Format definitions using structured prompt with relevance grouping
---@param definitions table[] Array of definition info tables
---@return string Enhanced formatted definitions
function M.format_structured_prompt(definitions)
  local formatted = { "", "--- Enhanced Context ---" }

  -- Group definitions by relevance
  local by_relevance = M.group_definitions_by_relevance(definitions)

  -- Add imports if any
  local all_imports = {}
  for _, def in ipairs(definitions) do
    if def.imports and #def.imports > 0 then
      for _, import in ipairs(def.imports) do
        if not vim.tbl_contains(all_imports, import) then
          table.insert(all_imports, import)
        end
      end
    end
  end

  if #all_imports > 0 then
    table.insert(formatted, "")
    table.insert(formatted, "## Imports & Dependencies:")
    for _, import in ipairs(all_imports) do
      table.insert(formatted, "- " .. import)
    end
  end

  -- Add high relevance definitions
  if #by_relevance.high > 0 then
    table.insert(formatted, "")
    table.insert(formatted, "## Primary Definitions:")
    for _, def in ipairs(by_relevance.high) do
      M.add_enhanced_definition(formatted, def)
    end
  end

  -- Add medium relevance definitions
  if #by_relevance.medium > 0 then
    table.insert(formatted, "")
    table.insert(formatted, "## Related Definitions:")
    for _, def in ipairs(by_relevance.medium) do
      M.add_enhanced_definition(formatted, def)
    end
  end

  -- Add low relevance definitions
  if #by_relevance.low > 0 then
    table.insert(formatted, "")
    table.insert(formatted, "## Additional Context:")
    for _, def in ipairs(by_relevance.low) do
      M.add_basic_definition(formatted, def)
    end
  end

  table.insert(formatted, "--- End Enhanced Context ---")
  table.insert(formatted, "")

  return table.concat(formatted, "\n")
end

--- Add enhanced definition to formatted output
---@param formatted string[] Array to append formatted content to
---@param def table Definition info table
---@return nil
function M.add_enhanced_definition(formatted, def)
  table.insert(formatted, "")

  -- Add class context if available
  if def.class_context and def.class_context.name then
    table.insert(formatted, string.format("**%s '%s'** in %s:",
      def.class_context.type, def.class_context.name, def.filename))
  end

  table.insert(formatted, string.format("**Function '%s'** (line %d):",
    def.symbol, def.start_line))

  -- Add type info if available
  if def.type_info and #def.type_info > 0 then
    table.insert(formatted, "Type: " .. table.concat(def.type_info, ", "))
  end

  table.insert(formatted, "```")
  table.insert(formatted, def.context)
  table.insert(formatted, "```")
end

--- Add basic definition to formatted output
---@param formatted string[] Array to append formatted content to
---@param def table Definition info table
---@return nil
function M.add_basic_definition(formatted, def)
  table.insert(formatted, "")
  table.insert(formatted, string.format("- %s (%s:%d)", def.symbol, def.filename, def.start_line))
end

--- Group definitions by relevance level
---@param definitions table[] Array of definition info tables
---@return table Table with {high: table[], medium: table[], low: table[]}
function M.group_definitions_by_relevance(definitions)
  local cfg = config.get()
  local grouped = { high = {}, medium = {}, low = {} }

  if not cfg.lsp_integration.contextual_relevance then
    -- All definitions are high relevance if contextual relevance is disabled
    grouped.high = definitions
    return grouped
  end

  local cursor_file = vim.api.nvim_buf_get_name(0)
  cursor_file = vim.fn.fnamemodify(cursor_file, ":t")

  for _, def in ipairs(definitions) do
    local relevance = M.calculate_relevance(def, cursor_file)

    if relevance >= 0.7 then
      table.insert(grouped.high, def)
    elseif relevance >= 0.3 then
      table.insert(grouped.medium, def)
    else
      table.insert(grouped.low, def)
    end
  end

  return grouped
end

--- Calculate relevance score for a definition
---@param def table Definition info table
---@param cursor_file string Current file name
---@return number Relevance score between 0 and 1
function M.calculate_relevance(def, cursor_file)
  local score = 0

  -- Same file = higher relevance
  if def.filename == cursor_file then
    score = score + 0.4
  end

  -- Has class context = higher relevance
  if def.class_context and def.class_context.name then
    score = score + 0.3
  end

  -- Has type info = higher relevance
  if def.type_info and #def.type_info > 0 then
    score = score + 0.2
  end

  -- Longer symbol name = potentially more specific
  if #def.symbol > 5 then
    score = score + 0.1
  end

  return math.min(score, 1.0)
end

return M