
-- local fidget = require("fidget")
local M = {}

M.error_channel = { id = "errors", name = "Error Log" }
M.channel_buffers = {}
M.message_registry = M.message_registry or {}
M.ordered_messages = M.ordered_messages or {}
M.author_colors = M.author_colors or {}
M.extra_line = true
M.ns_id = vim.api.nvim_create_namespace("chat_ui")

-- Define the sign used for editing indicators.
vim.fn.sign_define("ChatEditingIndicator", {
  text = "┃",
  texthl = "ChatEditingIndicator",
})

vim.api.nvim_set_hl(0, "ChatTimeHighlight", { fg = "gray50" })
vim.api.nvim_set_hl(0, "ChatMessageAnnotationHighlight", { fg = "gray50" })


local function get_author_highlight(author)
  if not M.author_colors[author.id] then
    local color = nil
    if author.color then
      color = author.color
    else
      color = "#00afff"
    end
    local group_name = "ChatAuthor_" .. author.id:gsub("%W", "_")
    -- Choose a color from a predefined palette or generate one dynamically.
    vim.api.nvim_set_hl(0, group_name, { fg = color, bold = true})
    M.author_colors[author.id] = group_name
  end
  return M.author_colors[author.id]
end


local function show_message_indicator(buf, line)
  vim.api.nvim_buf_set_extmark(buf, M.ns_id, line - 1, 0, {
    virt_text = { { "┃", "ChatEditingIndicator" } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
  })
end

local function start_draft(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if draft_start then return end
  local new_draft_start = vim.api.nvim_buf_line_count(buf) + 1
  vim.api.nvim_buf_set_var(buf, "draft_start", new_draft_start)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { new_draft_start, 0 })
  vim.api.nvim_buf_del_keymap(buf, "n", "i")
  vim.api.nvim_feedkeys("i", "n", false)
  show_message_indicator(buf, new_draft_start)
end

local function send_draft(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if not draft_start then return end

  vim.keymap.set("n", "i", function()
    start_draft(buf)
  end, { buffer = buf, silent = true })

  local lines = vim.api.nvim_buf_get_lines(buf, draft_start - 1, -1, false)
  if #lines > 0 and lines[1] ~= "" then
    local ipc = require("kbmail.ipc")
    local channel = vim.api.nvim_buf_get_var(buf, "channel")
    ipc.post_message(channel.service.id, channel.id, table.concat(lines, "\n"))
  end
  vim.api.nvim_buf_set_lines(buf, draft_start - 1, -1, false, {})
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)
end

local function cancel_draft(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if not draft_start then return end

  vim.keymap.set("n", "i", function()
    start_draft(buf)
  end, { buffer = buf, silent = true })
  vim.api.nvim_buf_set_lines(buf, draft_start - 1, -1, false, {})
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)
end

local function update_draft_signs(buf)
  local ok, draft_start = pcall(vim.api.nvim_buf_get_var, buf, "draft_start")
  if not ok or not draft_start then return end

  vim.fn.sign_unplace("ChatEditingGroup", { buffer = buf })
  local total_lines = vim.api.nvim_buf_line_count(buf)
  for l = draft_start, total_lines do
    vim.fn.sign_place(0, "ChatEditingGroup", "ChatEditingIndicator", buf, { lnum = l, priority = 10 })
  end
end

local function get_id(channel)
  local channel_id = channel.id
  if channel.service then
    channel_id = channel.service.id .. ":" .. channel.id
  end
  return channel_id
end


function M.create_channel_buffer(channel)
  local channel_id = get_id(channel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"
  if channel ~= M.error_channel then
    vim.bo[buf].filetype = "markdown"
  end
  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, { buffer = buf, silent = true })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "# This is the beginning of the conversation for " .. channel.name })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  M.channel_buffers[channel_id] = buf
  vim.api.nvim_buf_set_var(buf, "channel", channel)
  local buf_name = channel.name
  if channel.service then
    buf_name = channel.service.name .. ":" .. buf_name
  end
  vim.api.nvim_buf_set_name(buf, "[" .. buf_name .. "]")
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)
  vim.keymap.set("n", "i", function()
    start_draft(buf)
  end, { buffer = buf, silent = true, noremap = true })
  vim.keymap.set("n", "<Enter>", function()
    send_draft(buf)
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<leader>q", function()
    cancel_draft(buf)
  end, { buffer = buf, silent = true, noremap = true })

  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, bufnr, _, _, _, _)
      update_draft_signs(bufnr)
    end,
  })
  M.ordered_messages[buf] = {}
  return buf
end


function M.get_channel_buffer(channel)
  local channel_id = get_id(channel)
  if M.channel_buffers[channel_id] and vim.api.nvim_buf_is_valid(M.channel_buffers[channel_id]) then
    return M.channel_buffers[channel_id]
  end
end

local function split_lines(message)
  local lines = {}
  for line in message:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end
  return lines
end

local function last_line_is_visible(win, offset)
  if win < 0 then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local last_line = vim.api.nvim_buf_line_count(buf) - offset
  local last_visible_line = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w$")
  end)
  return last_visible_line >= last_line
end

local unread_marker_id = nil
local function show_unread_marker(buf)
  if unread_marker_id then return end
  local last_line = vim.api.nvim_buf_line_count(buf)
  unread_marker_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, last_line, 0, {
    virt_text = { { "  [New messages below]", "WarningMsg" } },
    virt_text_pos = "eol",
  })
end

local function scroll(buf, draft_start, message_size)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local should_scroll = last_line_is_visible(win, message_size)
    if not draft_start then
      if should_scroll then
        local cursor_pos = vim.api.nvim_win_get_cursor(win)
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
        vim.api.nvim_win_set_cursor(win, cursor_pos)
      else
        local channel = vim.api.nvim_buf_get_var(buf, "channel")
        -- if channel.id ~= M.error_channel.id then
        --   fidget.notify("New message in " .. channel.name)
        -- end
        show_unread_marker(buf)
      end
    end
  end
end

function M.append_text_message(channel, message_text)
  local buf = M.get_channel_buffer(channel)
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  local message_lines = split_lines(message_text)
  if draft_start then
    vim.api.nvim_buf_set_var(buf, "draft_start", draft_start + #message_lines)
  end

  local insert_pos = draft_start and draft_start - 1 or total_lines
  local end_insert = insert_pos
  vim.api.nvim_buf_set_lines(buf, insert_pos, end_insert, false, message_lines)

  scroll(buf, draft_start, #message_lines)
end

local function format_message(message)
  local formatted = message.author.display_name .. " " .. message.ts_time .. "\n" .. message.body
  if M.extra_line then
    formatted = formatted .. "\n "
  end
  return formatted
end

local function generate_annotations(message)
  local virt_content = nil
  if message.edit_time then
    virt_content = "edited"
  end
  if message.replies then
    local reply_word = "reply"
    if message.replies.count > 1 then
      reply_word = "replies"
    end
    virt_content = (virt_content or "") .. " " .. tostring(message.replies.count) .. " " .. reply_word
  end
  if message.reactions then
    for emoji, users in pairs(message.reactions) do
      virt_content = (virt_content or "") .. " " .. emoji .. tostring(#users)
    end
  end
  if virt_content then
    return { { virt_content, "ChatMessageAnnotationHighlight" } }
  end
end

function M.message_size(message)
  local message_lines = split_lines(format_message(message))
  return #message_lines  -- one for the author line
end

local function is_inside_thread(message)
  return message.thread_id and message.thread_id ~= message.id
end

local function apply_styling(buf, message, start_insert)
  -- take care of cosmetics
  -- first line
  local author_hl = get_author_highlight(message.author)
  vim.api.nvim_buf_add_highlight(buf, M.ns_id, author_hl, start_insert, 0, #message.author.display_name)
  vim.api.nvim_buf_add_highlight(buf, M.ns_id, "ChatTimeHighlight", start_insert, #message.author.display_name + 1, #message.author.display_name + #message.ts_time + 1)

  -- indent message body, and a bit more for thread replies
  local extra_indent = ""
  if is_inside_thread(message) then
    extra_indent = "|   "
  end
  if extra_indent ~= "" then
    vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert, 0, {
      virt_text = { { extra_indent, "ChatMessageIndent" } },
      virt_text_pos = "inline",
    })
  end

  for i = 1, (M.message_size(message) - 1) do
    M.debug(vim.inspect(start_insert+i))
    vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert + i, 0, {
      virt_text = { { extra_indent .. "    ", "ChatMessageIndent" } },
      virt_text_pos = "inline",
    })
  end
end


-- Returns the index where new_message should be inserted in the sorted array `arr`,
-- searching backwards since most messages are inserted near the end.
local function reverse_search(arr, new_message)
  for i = #arr, 1, -1 do
    -- A lower id means an earlier message.
    if tonumber(arr[i].id) <= tonumber(new_message.id) then
      return i + 1
    end
  end
  return 1  -- Insert at the beginning if new_message is earlier than all others.
end

-- Use this function to insert new_message into the sorted array.
local function insert_into_ordered(arr, new_message)
  local idx = reverse_search(arr, new_message)
  table.insert(arr, idx, new_message)
end

local function find_new_conversation_position(buf, draft_start, message)
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local start_insert = nil
  local end_insert = nil
  local message_position = reverse_search(M.ordered_messages[buf], message)
  local next_message = M.ordered_messages[buf][message_position]
  if next_message then
    start_insert = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, next_message.thread_mark_id, {})[1]
  else
    start_insert = draft_start and draft_start - 1 or total_lines
  end
  end_insert = start_insert
  return start_insert, end_insert
end


local function insert_message(buf, draft_start, message)
  local old_message = M.message_registry[message.id]
  local mark_id = nil
  local old_mark_id = nil
  local start_thread = nil
  local last_message_in_thread = nil

  -- updating, we already have a mark
  if  old_message then
    old_mark_id = old_message.mark_id
  end


  -- find insert positions
  local start_insert = nil
  local end_insert = nil

  if not old_message then -- for a new message
    if not is_inside_thread(message) then
      start_insert, end_insert = find_new_conversation_position(buf, draft_start, message)
    else
      last_message_in_thread = true  -- this is not necessarily true, eg when history for thread is fetched
      local base_message = M.message_registry[message.thread_id]
      if base_message then
        local positions = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, base_message.thread_mark_id, { details = true })
        start_thread = positions[1]
        start_insert = positions[3]["end_row"]
        end_insert = start_insert
      else
        return  -- ignore replies to threads we don't show
      end
    end
  else  -- for an old message
    local old_positions = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, old_message.mark_id, { details = true })
    start_insert = old_positions[1]
    local details = old_positions[3]
    end_insert = details["end_row"]
    if is_inside_thread(message) then
      local base_message = M.message_registry[message.thread_id]
      if base_message then
        if base_message.thread_mark_id then
          local positions = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, base_message.thread_mark_id, { details = true })
          start_thread = positions[1]
          local end_row = positions[3]["end_row"]
          if end_insert == end_row then
            last_message_in_thread = true
          end
        end
      end
    end
  end

  -- insert lines
  local body = format_message(message)
  local message_lines = split_lines(body)
  vim.api.nvim_buf_set_lines(buf, start_insert, end_insert, false, message_lines)

  -- create/update message mark
  -- add annotations
  local virt_lines = generate_annotations(message)
  mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert, 0, {
    id = old_mark_id,
    end_row = start_insert + #message_lines,
    virt_text = virt_lines,
    virt_text_pos = "right_align",
    hl_mode = "combine",
  })
  message.mark_id = mark_id


  -- create/update thread mark
  if old_message and old_message.thread_mark_id then
    message.thread_mark_id = old_message.thread_mark_id
  end


  if is_inside_thread(message) then
    local base_message = M.message_registry[message.thread_id]
    if last_message_in_thread then
      local thread_mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_thread, 0, {
        id = base_message.thread_mark_id,
        end_row = start_insert + #message_lines,
        hl_mode = "combine",
      })
      insert_message(buf, draft_start, base_message)
    end
  else  -- new or old message that is not inside a thread, so potential thread start
    local message_position = reverse_search(M.ordered_messages[buf], message)
    local prev_message = M.ordered_messages[buf][message_position - 1]
    local virt_lines = nil
    if not prev_message or prev_message.ts_date ~= message.ts_date then
      virt_lines = { { { message.ts_date, "ChatTimeHighlight" } } }
    end

    local thread_mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert, 0, {
      id = message.thread_mark_id,
      end_row = start_insert + #message_lines,
      virt_lines = virt_lines,
      virt_lines_above = true,
      hl_mode = "combine",
    })
    message.thread_mark_id = thread_mark_id
    local next_message =  M.ordered_messages[buf][message_position]
    if next_message and next_message.ts_date == message.ts_date then
      insert_message(buf, draft_start, next_message)
    end
    if not old_message then
      insert_into_ordered(M.ordered_messages[buf], message)
    end

  end

  -- add message to registry
  M.message_registry[message.id] = message
  apply_styling(buf, message, start_insert)

end

function M.append_message(channel, message)
  local buf = M.get_channel_buffer(channel)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if draft_start then
    vim.api.nvim_buf_set_var(buf, "draft_start", draft_start + M.message_size(message))
  end

  insert_message(buf, draft_start, message)

  scroll(buf, draft_start, M.message_size(message))
end

function M.debug(message)
  M.append_text_message(M.error_channel, message)
end

function M.switch_to(channel)
  if channel.service then
    local ipc = require("kbmail.ipc")
    ipc.switch_channel(channel.service.id, channel.id)
  end
  local buf = M.get_channel_buffer(channel)
  local prior_win = vim.fn.win_getid(vim.fn.winnr("#"))
  vim.api.nvim_win_set_buf(prior_win, buf)
  vim.api.nvim_set_current_win(prior_win)
end

function M.add_channels(service, channels)
  M.debug("adding service: " .. service.name)
  for _, chan in ipairs(channels) do
    chan.service = service
    M.debug("channel: " .. chan.name)
    M.create_channel_buffer(chan)
  end
  local NuiTree = require("nui.tree")
  local snode = NuiTree.Node({ text = service.name, service_id = service.id })
  M.channel_tree:add_node(snode)
  for _, chan in ipairs(channels) do
    M.channel_tree:add_node(NuiTree.Node({ text = chan.name, channel = chan }), snode:get_id())
  end
  for _, node in pairs(M.channel_tree.nodes.by_id) do
    node:expand()
  end
  M.channel_tree:render(1)
end

return M
