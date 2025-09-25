local _debug = debug
local api = require("cmp-llm.api")
local prompt = require("cmp-llm.prompt")
local config = require("cmp-llm.config")
local debug = require("cmp-llm.debug")

local indicators = require("cmp-llm.indicators")

local M = {
    request_context = nil,
    debounce_timer = nil,
}

--- nvim-cmp source implementation
---@class CmpLlmSource
local source = {}

--- Helper function to clean up request and indicator
---@param request_context table The request context
---@return nil
local function cleanup_request(request_context)
    -- Clean up the indicator if it exists
    if request_context and request_context.indicator_info then
        indicators.hide_processing(request_context.indicator_info)
        request_context.indicator_info = nil
    end
end

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
    return require('cmp').get_config().completion.keyword_pattern
    -- return [[\k\+(]]
end

--- Get trigger characters for completion
---@return string[] Array of trigger characters
function source:get_trigger_characters()
    return {"."}
end

--- Main completion function called by nvim-cmp
---@param request table nvim-cmp request object
---@param callback function Callback called with completion result
---@return nil
function source:complete(request, callback)
    local cfg = config.get()

    debug.log_completion("complete_called", {
        stack = _debug.traceback("complete_called"),
        available = self:is_available(),
        full_line = vim.api.nvim_get_current_line(),
        request = {
            context = request.context,
            option = request.option
        }
    })

    if not self:is_available() then
        debug.log_completion("is_available", {
            available = self:is_available(),
            full_line = vim.api.nvim_get_current_line(),
            request = {
                context = request.context,
                option = request.option
            }
        })
        callback({ items = {}, isIncomplete = false })
        return
    end

    M:cancel_current_request()

    local word_boundary = prompt.get_word_boundary()
    -- Extract only the part of the word before the cursor as prefix
    local prefix = request.context.cursor_before_line:sub(word_boundary.col)
    local bufnr = vim.api.nvim_get_current_buf()
    local current_time = vim.loop.now()

    local request_context_stored = {
        cursor_line = request.context.cursor.row,
        cursor_col = request.context.cursor.col,
        cursor_before_line = request.context.cursor_before_line,
        prefix = prefix,
        bufnr = bufnr,
        timestamp = current_time,
        request = request,
        callback = callback,
        request_id = current_time,
    }
    M.request_context = request_context_stored

    -- Set up debounce timer - wait for user to stop typing
    M.debounce_timer = vim.loop.new_timer()
    M.debounce_timer:start(cfg.debounce_ms, 0, function()
        vim.schedule(function()
            -- Process the request after the debounce delay
            M:stop_timer()
            M:process_completion_request(request_context_stored)
        end)
    end)

    debug.log_completion("debounce_scheduled", {
        debounce_ms = cfg.debounce_ms,
        timestamp = current_time
    })
    callback({ items = {}, isIncomplete = true })
end

function M:cancel_current_request()
    self:stop_timer()
    if self.request_context then
        self.request_context.superseded = true
    end
end

function M:stop_timer()
    if M.debounce_timer then
        M.debounce_timer:stop()
        M.debounce_timer:close()
        M.debounce_timer = nil
    end
end

--- Checks if a completion request context is still valid for processing.
-- This function validates whether a completion request should still be processed by checking multiple criteria:
-- 1. Current editor mode (must be insert mode)
-- 2. Whether the request has been superseded by a newer request
-- 3. Required fields in the request context
-- 4. Context relevance (cursor position and content)
--
-- @param self The module table (when using colon syntax)
-- @param request_context table The completion request context to validate. Must contain:
--        @field request_id string|number Unique identifier for the request
--        @field superseded boolean|nil Whether this request was replaced by a newer one
--        @field prefix string|nil The completion prefix that triggered the request
--        @field cursor_line number The line number where completion was requested (1-indexed)
--        @field cursor_col number The column number where completion was requested (1-indexed)
--        @field bufnr number The buffer number where completion was requested
--        @field cursor_before_line string|nil The line content before the cursor at request time
--
-- @return boolean Returns true if the context is still valid for processing, false otherwise.
--         When returning false, the request is automatically cleaned up and appropriate
--         debug logging is performed.
--
-- @note This function performs automatic cleanup of invalid requests via `cleanup_request()`
-- @note Extensive debug logging is performed for all invalidation scenarios
-- @note Buffer number validation is intentionally skipped as buffer numbers can change
--       in some editor setups without changing the actual file content
--
-- @see cleanup_request
-- @see debug.log_completion
--
-- @usage
-- if M:context_is_still_valid(request_ctx) then
--     -- Process completion
-- else
--     -- Request is no longer valid
-- end
function M:context_is_still_valid(request_context)
    local request_id = request_context.request_id
    -- check the neovim is stll on the insert mode
    if vim.api.nvim_get_mode().mode ~= "i" then
        debug.log_completion("request_cancelled", {
            request_id = request_id,
            reason = "not_in_insert_mode"
        })
        cleanup_request(request_context)
        return false
    end

    -- Check if this request was superseded by a newer one
    if request_context.superseded then
        debug.log_completion("request_superseded", {
            request_id = request_id,
            reason = "superseded_by_newer_request"
        })
        cleanup_request(request_context)
        return false
    end

    -- Validate stored request has required fields
    if not request_context.prefix then
        debug.log_completion("request_invalid", {
            request_id = request_id,
            reason = "missing_prefix",
            stored_request = request_context
        })
        cleanup_request(request_context)
        return false
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

    if (current_cursor[1] ~= request_context.cursor_line) or
        (current_cursor[2] ~= (request_context.cursor_col- 1)) then
        context_valid = false
        invalidation_reason = "cursor_have_changed"
    end

    -- Clean up the request and indicator first, but only if context is invalid
    if not context_valid then
        cleanup_request(request_context)
        debug.log_completion("request_invalidated", {
            request_id = request_id,
            reason = invalidation_reason,
            stored_context = {
                bufnr = request_context.bufnr,
                cursor = { request_context.cursor_line, request_context.cursor_col },
                prefix = request_context.prefix,
                cursor_before_line = request_context.cursor_before_line
            },
            current_context = {
                bufnr = current_bufnr,
                cursor = current_cursor,
                line = current_line,
                current_filename = vim.api.nvim_buf_get_name(current_bufnr),
                stored_filename = vim.api.nvim_buf_get_name(request_context.bufnr)
            }
        })
        return false
    end
    return true
end

--- Process the actual completion request
---@param request_context table The stored request context
function M:process_completion_request(request_context)
    local request = request_context.request
    local callback = request_context.callback
    local cfg = config.get()
    local request_id = request_context.request_id
    local prefix = request_context.prefix

    if not self:context_is_still_valid(request_context) then
        return
    end

    debug.log_completion("prefix_extraction_debug", {
        cursor_before_line = request.context.cursor_before_line,
        extracted_prefix = prefix,
        full_line = vim.api.nvim_get_current_line()
    })


    debug.log_completion("request_started", {
        request_id = request_id,
        prefix = prefix,
        cursor_before_line = request.context.cursor_before_line,
    })

    prompt.build_prompt_for_completion(function(prompt_text)
        request_context.indicator_info = indicators.show_processing()
        api.complete(prompt_text, function(completions, error_msg)
            vim.schedule(function()
                if not self:context_is_still_valid(request_context) then
                    return
                end

                if error_msg then
                    cleanup_request(request_context)
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

                    local filter_text = prefix
                    local insert_text = prefix .. completion
                    local label = prefix

                    -- Create a simple, standard nvim-cmp completion item
                    local item = {
                        label = label,
                        cmp = {
                            kind_text = "llm",
                        },

                        insertText = insert_text,
                        documentation = {
                            kind = require("cmp").lsp.MarkupKind.PlainText,
                            value = insert_text
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
                end

                -- Clean up the request and hide the processing indicator before showing completions
                cleanup_request(request_context)

                callback({
                    items = items,
                    isIncomplete = false,
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
