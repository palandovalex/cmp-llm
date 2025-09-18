local api = require("cmp-llm.api")
local prompt = require("cmp-llm.prompt")
local config = require("cmp-llm.config")
local debug = require("cmp-llm.debug")

local M = {}

--- nvim-cmp source implementation
---@class CmpLlmSource
local source = {}

--- Pending request tracking
local pending_requests = {}
local last_request_time = 0
local debounce_timer = nil

--- Create a new source instance
---@return CmpLlmSource New source instance
function source:new()
  return setmetatable({}, { __index = source })
end

--- Get debug name for this source
---@return string The debug name "llm"
function source:get_debug_name()
  return "llm"
end

--- Check if the source is available
---@return boolean True if enabled and has API key
function source:is_available()
  local cfg = config.get()
  local available = cfg.enabled and cfg.api_key ~= ""
  return available
end

--- Get keyword pattern for triggering completion
---@return string Vim regex pattern for keywords
function source:get_keyword_pattern()
  return [[\k\+]]
end

--- Get trigger characters for completion
---@return string[] Array of trigger characters
function source:get_trigger_characters()
  return { ".", ":", "(", "[", " ", "\t", "\n" }
end

--- Main completion function called by nvim-cmp
---@param request table nvim-cmp request object
---@param callback function Callback called with completion result
---@return nil
function source:complete(request, callback)
  local cfg = config.get()

  debug.log_completion("complete_called", {
    available = self:is_available(),
    request = {
      context = request.context,
      option = request.option
    }
  })

  if not self:is_available() then
    callback({ items = {}, isIncomplete = false })
    return
  end

  local current_time = vim.loop.now()

  -- Cancel previous debounce timer if it exists
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer:close()
    debounce_timer = nil
  end

  -- Mark previous pending requests as superseded
  local superseded_count = 0
  for old_request_id, old_request in pairs(pending_requests) do
    if old_request and type(old_request) == "table" then
      old_request.superseded = true
      superseded_count = superseded_count + 1
    end
  end

  if superseded_count > 0 then
    debug.log_completion("superseded_previous_requests", {
      superseded_count = superseded_count,
      new_request_id = "pending"
    })
  end

  -- Store the current request context for later processing
  local request_context = {
    request = request,
    callback = callback,
    timestamp = current_time
  }

  -- Set up debounce timer - wait for user to stop typing
  debounce_timer = vim.loop.new_timer()
  debounce_timer:start(cfg.debounce_ms, 0, function()
    vim.schedule(function()
      -- Process the request after the debounce delay
      debounce_timer:stop()
      debounce_timer:close()
      debounce_timer = nil

      M.process_completion_request(request_context)
    end)
  end)

  debug.log_completion("debounce_scheduled", {
    debounce_ms = cfg.debounce_ms,
    timestamp = current_time
  })
end

--- Process the actual completion request
---@param request_context table The stored request context
function M.process_completion_request(request_context)
  local request = request_context.request
  local callback = request_context.callback
  local cfg = config.get()

  local current_time = vim.loop.now()
  last_request_time = current_time

  local request_id = tostring(current_time)

  -- Get buffer info first
  local bufnr = vim.api.nvim_get_current_buf()

  local word_boundary = prompt.get_word_boundary()
  -- Extract only the part of the word before the cursor as prefix
  local prefix = request.context.cursor_before_line:sub(word_boundary.col)

  debug.log_completion("prefix_extraction_debug", {
    cursor_before_line = request.context.cursor_before_line,
    word_boundary_col = word_boundary.col,
    word_boundary_end_col = word_boundary.end_col,
    extracted_prefix = prefix,
    full_line = vim.api.nvim_get_current_line()
  })

  local request_context_stored = {
    cursor_line = request.context.cursor.row,
    cursor_col = request.context.cursor.col,
    cursor_before_line = request.context.cursor_before_line,
    prefix = prefix,
    bufnr = bufnr,
    timestamp = current_time
  }
  pending_requests[request_id] = request_context_stored
  last_request_time = current_time

  -- Clean up old superseded requests (older than 10 seconds)
  local cleanup_threshold = current_time - 10000  -- 10 seconds ago
  local cleaned_count = 0
  for old_id, old_request in pairs(pending_requests) do
    if old_request.superseded and old_request.timestamp < cleanup_threshold then
      pending_requests[old_id] = nil
      cleaned_count = cleaned_count + 1
    end
  end

  if cleaned_count > 0 then
    debug.log_completion("cleaned_old_requests", {
      cleaned_count = cleaned_count,
      cleanup_threshold = cleanup_threshold
    })
  end

  -- Get filetype and filename
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  local filename = vim.api.nvim_buf_get_name(bufnr)
  filename = filename ~= "" and vim.fn.fnamemodify(filename, ":t") or "untitled"

  debug.log_completion("request_started", {
    request_id = request_id,
    prefix = prefix,
    cursor_before_line = request.context.cursor_before_line,
    word_boundary = word_boundary
  })

  prompt.build_prompt_with_lsp_for_completion(word_boundary, filetype, filename, function(prompt_text)
    api.complete(prompt_text, function(completions, error_msg)
      vim.schedule(function()
        local stored_request = pending_requests[request_id]
        if not stored_request then
          debug.log_completion("request_cancelled", {
            request_id = request_id,
            reason = "no_pending_request"
          })
          return
        end

        -- Check if this request was superseded by a newer one
        if stored_request.superseded then
          debug.log_completion("request_superseded", {
            request_id = request_id,
            reason = "superseded_by_newer_request"
          })
          pending_requests[request_id] = nil
          return
        end

        -- Validate stored request has required fields
        if not stored_request.prefix then
          debug.log_completion("request_invalid", {
            request_id = request_id,
            reason = "missing_prefix",
            stored_request = stored_request
          })
          pending_requests[request_id] = nil
          return
        end

        -- Validate request is still relevant
        local current_bufnr = vim.api.nvim_get_current_buf()
        local current_cursor = vim.api.nvim_win_get_cursor(0)
        local current_line = vim.api.nvim_get_current_line()

        -- Check if context has changed significantly
        local context_valid = true
        local invalidation_reason = ""

        -- Skip buffer validation for now - focus on cursor position and content
        -- Buffer numbers can change in some editors/setups without changing the actual file

        if math.abs(current_cursor[1] - stored_request.cursor_line) > 2 then
          context_valid = false
          invalidation_reason = "cursor_line_moved_significantly"
        elseif math.abs(current_cursor[2] - stored_request.cursor_col) > 10 then
          context_valid = false
          invalidation_reason = "cursor_col_moved_significantly"
        elseif not stored_request.prefix or stored_request.prefix == "" or not current_line:find(vim.pesc(stored_request.prefix), 1, true) then
          context_valid = false
          invalidation_reason = "prefix_no_longer_present"
        end

        pending_requests[request_id] = nil

        if not context_valid then
          debug.log_completion("request_invalidated", {
            request_id = request_id,
            reason = invalidation_reason,
            stored_context = {
              bufnr = stored_request.bufnr,
              cursor = { stored_request.cursor_line, stored_request.cursor_col },
              prefix = stored_request.prefix,
              cursor_before_line = stored_request.cursor_before_line
            },
            current_context = {
              bufnr = current_bufnr,
              cursor = current_cursor,
              line = current_line,
              current_filename = vim.api.nvim_buf_get_name(current_bufnr),
              stored_filename = vim.api.nvim_buf_get_name(stored_request.bufnr)
            }
          })
          return
        end

        if error_msg then
          debug.log_completion("request_failed", {
            request_id = request_id,
            error = error_msg
          })
          callback({ items = {}, isIncomplete = false })
          return
        end

        debug.log_completion("processing_completions", {
          request_id = request_id,
          raw_completions = completions,
          completions_count = completions and #completions or 0
        })

        local items = {}
        for i, completion in ipairs(completions or {}) do
          if i > cfg.max_completion_items then
            break
          end

          local filtered = prompt.filter_completion(completion, prefix)
          debug.log_completion("filtering", {
            request_id = request_id,
            candidate = i,
            original = completion,
            filtered = filtered,
            prefix = prefix
          })

          if filtered then
            local detail = "AI completion"
            if cfg.num_candidates > 1 then
              detail = "AI completion #" .. i
            end

            -- For continuation completions, construct proper filterText
            local filter_text = filtered
            local insert_text = completion

            -- Check if this is a continuation completion (prefix + completion = word)
            local first_word = filtered:match("^(%w+)")

            if first_word and first_word:lower():sub(1, #prefix) ~= prefix:lower() then
              -- This is a continuation, reconstruct the full word
              local full_word = prefix .. first_word
              filter_text = full_word
              -- Replace the first word in completion with the full word (prefix + continuation)
              insert_text = full_word .. completion:sub(#first_word + 1)
            end

            -- Create a simple, standard nvim-cmp completion item
            local item = {
              label = filter_text,
              kind = require("cmp").lsp.CompletionItemKind.Text,
              insertText = insert_text,
              detail = detail,
              documentation = {
                kind = require("cmp").lsp.MarkupKind.PlainText,
                value = completion
              },
              sortText = "zzz" .. string.format("%04d", i),  -- Lower priority
              filterText = filter_text,
              menu = "[llm]"
            }

            table.insert(items, item)
            debug.log_completion("item_added", {
              request_id = request_id,
              candidate = i,
              item_label = item.label,
              item_insertText = item.insertText,
              item_kind = item.kind,
              item_sortText = item.sortText,
              item_filterText = item.filterText
            })
          else
            debug.log_completion("item_filtered_out", {
              request_id = request_id,
              candidate = i,
              completion = completion,
              prefix = prefix
            })
          end
        end

        debug.log_completion("final_result", {
          request_id = request_id,
          items_count = #items,
          isIncomplete = #items == cfg.max_completion_items,
          items = items  -- Include the actual items for debugging
        })

        debug.log_completion("calling_callback", {
          request_id = request_id,
          items_count = #items,
          first_item_label = items[1] and items[1].label or "none",
          callback_type = type(callback)
        })

        callback({
          items = items,
          isIncomplete = #items == cfg.max_completion_items
        })
      end)
    end)
  end)
end

--- Create a new source instance
---@return CmpLlmSource New source instance
function M.new()
  return source:new()
end

return M