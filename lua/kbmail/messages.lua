
-- local fidget = require("fidget")

local M = {}

M.error_channel = { id = "errors", name = "Error Log" }
M.channel_buffers = {}
M.message_registry = M.message_registry or {}
M.ordered_messages = M.ordered_messages or {}
M.ordered_replies = M.ordered_replies or {}
M.author_colors = M.author_colors or {}
M.message_stylings = M.message_stylings or {}
M.extra_line = true
M.message_marks = M.message_marks or {}
M.ns_id = vim.api.nvim_create_namespace("chat_ui")

-- vim.wo.foldexpr = "v:lua.foldlevel_from_mark()"
vim.wo.foldmethod = 'indent'
vim.wo.breakindent = true
-- vim.wo.foldcolumn = "auto"
-- vim.wo.foldtext = "v:lua.foldtext_from_mark()"

-- Define the sign used for editing indicators.
vim.fn.sign_define("ChatEditingIndicator", {
  text = "┃",
  texthl = "ChatEditingIndicator",
})

vim.api.nvim_set_hl(0, "ChatTimeHighlight", { fg = "gray50" })
vim.api.nvim_set_hl(0, "ChatMessageAnnotationHighlight", { fg = "gray50" })

M.indent = "  ▏ "

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

function M.get_message_under_cursor(buf)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row = cursor_pos[1]
  local marks = vim.api.nvim_buf_get_extmarks(buf, M.ns_id, {row, 0}, {row, -1}, {overlap=true})
  for _, mark in ipairs(marks) do
    local mark_id = mark[1]
    local level = M.message_marks[buf][mark_id]
    if level then
      return level["message"]
    end
  end
end

local function fetch_thread(buf)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row = cursor_pos[1]
  local marks = vim.api.nvim_buf_get_extmarks(buf, M.ns_id, {row, 0}, {row, -1}, {overlap=true})
  for _, mark in ipairs(marks) do
    local mark_id = mark[1]
    local level = M.message_marks[buf][mark_id]
    if level and level["level"] == 0 then
      local thread_id = level["message"].thread_id
      local ipc = require("kbmail.ipc")
      local channel = vim.api.nvim_buf_get_var(buf, "channel")
      ipc.fetch_thread(channel.service.id, channel.id, thread_id)
    end
  end
end

function M.create_channel_buffer(channel)
  local channel_id = get_id(channel)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"

  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, { buffer = buf, silent = true })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "# This is the beginning of the conversation for " .. channel.name })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  M.channel_buffers[channel_id] = { buf = buf, channel = channel }
  vim.api.nvim_buf_set_var(buf, "channel", channel)
  local buf_name = channel.name
  if channel.service then
    buf_name = channel.service.name .. ":" .. buf_name
  end
  vim.api.nvim_buf_set_name(buf, "[" .. buf_name .. "]")
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)

  M.ordered_messages[buf] = {}
  M.ordered_replies[buf] = {}
  M.message_stylings[buf] = {}
  M.message_registry[buf] = {}
  M.message_marks[buf] = {}

  vim.keymap.set("n", "<leader><leader>", function()
    local channel_picker = require("kbmail.channel_picker")
    channel_picker.pick_channel()
  end, { buffer = buf, silent = true, noremap = true })
  if channel ~= M.error_channel then
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("n", "i", function()
      start_draft(buf)
    end, { buffer = buf, silent = true, noremap = true })
    -- vim.keymap.set("n", "o", function()
    --   start_draft_reply(buf)
    -- end, { buffer = buf, silent = true, noremap = true })
    vim.keymap.set("n", "<Enter>", function()
      send_draft(buf)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<leader>q", function()
      cancel_draft(buf)
    end, { buffer = buf, silent = true, noremap = true })
    vim.keymap.set("n", "<leader>a", function()
      fetch_thread(buf)
    end, { buffer = buf, silent = true, noremap = true })

    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, bufnr, _, _, _, _)
        update_draft_signs(bufnr)
      end,
    })
  end
  return buf
end


function M.get_channel_buffer(channel)
  local channel_id = get_id(channel)
  if M.channel_buffers[channel_id] and vim.api.nvim_buf_is_valid(M.channel_buffers[channel_id]["buf"]) then
    return M.channel_buffers[channel_id]["buf"]
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

function M.on_win_scrolled(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local channel = vim.api.nvim_buf_get_var(buf, "channel")
  if last_line_is_visible(win, 0) then
    M.mark_channel_read(channel)
  end
end

function M.mark_channel_unread(channel)
  channel.unread = true
  if not M.channel_tree then
    return
  end
  for _, node in pairs(M.channel_tree.nodes.by_id) do
    if node.channel and node.channel.id == channel.id then
      node.channel.unread = true
    end
  end
  M.channel_tree:render(1)
end

function M.mark_channel_read(channel)
  channel.unread = false
  if not M.channel_tree then
    return
  end
  for _, node in pairs(M.channel_tree.nodes.by_id) do
    if node.channel and node.channel.id == channel.id then
      node.channel.unread = false
    end
  end
  M.channel_tree:render(1)
end

local function scroll(buf, draft_start, message_size)
  local mark_as_unread = true
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local should_scroll = last_line_is_visible(win, message_size)
    if not draft_start then
      if should_scroll then
        local cursor_pos = vim.api.nvim_win_get_cursor(win)
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
        vim.api.nvim_win_set_cursor(win, cursor_pos)
        mark_as_unread = false
      else
        mark_as_unread = true
      end
    else
      mark_as_unread = false
    end
  end
  local channel = vim.api.nvim_buf_get_var(buf, "channel")
  if mark_as_unread then
        -- if channel.id ~= M.error_channel.id then
        --   fidget.notify("New message in " .. channel.name)
        -- end
    M.mark_channel_unread(channel)
  else
    M.mark_channel_read(channel)
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
  local author_mark_id = nil
  local time_mark_id = nil
  if M.message_stylings[buf][message.id] then
    author_mark_id = M.message_stylings[buf][message.id]["author"]
    time_mark_id = M.message_stylings[buf][message.id]["time"]
  end
  local offset = 0
  if is_inside_thread(message) then
    offset = string.len(M.indent)
  end
  author_mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert, 0 + offset,
    { id = author_mark_id, end_col = #message.author.display_name + offset, hl_group = author_hl })
  time_mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert, #message.author.display_name + 1 + offset,
    { id = time_mark_id, end_col = #message.author.display_name + #message.ts_time + 1 + offset, hl_group = "ChatTimeHighlight" } )
  M.message_stylings[buf][message.id] = { author = author_mark_id, time = time_mark_id }

  -- indent message body, and a bit more for thread replies
  -- local extra_indent = ""
  -- if is_inside_thread(message) then
  --   extra_indent = "|   "
  -- end
  -- if extra_indent ~= "" then
  --   vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert, 0, {
  --     virt_text = { { extra_indent, "ChatMessageIndent" } },
  --     virt_text_pos = "inline",
  --   })
  -- end
  --
  -- for i = 1, (M.message_size(message) - 1) do
  --   M.debug(vim.inspect(start_insert+i))
  --   vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_insert + i, 0, {
  --     virt_text = { { extra_indent .. "    ", "ChatMessageIndent" } },
  --     virt_text_pos = "inline",
  --     virt_text_repeat_linebreak = true,
  --   })
  -- end
end

local function insert_formatted_message(buf, message, start_line, end_line)
  local old_message = M.message_registry[buf][message.id]
  local old_mark_id = nil
  if old_message then
    old_mark_id = old_message.mark_id
  end
  local body = format_message(message)
  local message_lines = split_lines(body)

  local number_of_lines = #message_lines
  local mark_id = nil

  if is_inside_thread(message) then
    for i, line in ipairs(message_lines) do
      message_lines[i] = M.indent .. line
    end
  end

  vim.api.nvim_buf_set_lines(buf, start_line, end_line, false, message_lines)
  apply_styling(buf, message, start_line)


  local virt_lines = generate_annotations(message)
  mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, start_line, 0, {
    id = old_mark_id,
    end_row = start_line + number_of_lines,
    virt_text = virt_lines,
    virt_text_pos = "right_align",
    hl_mode = "combine",
  })
  message.mark_id = mark_id
  if is_inside_thread(message) then
    M.message_marks[buf][mark_id] = { level=1 , message=message}
  else
    M.message_marks[buf][mark_id] = { level=0 , message=message}
  end

  -- add message to registry
  M.message_registry[buf][message.id] = message
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

-- Insert new_message into the sorted array if not already present, replaces the message with the same id otherwise. Returns the index of new_message in the array
local function insert_into_ordered(arr, new_message)
  local idx = reverse_search(arr, new_message)
  local prev = arr[idx - 1]
  if prev and prev.id == new_message.id then
    table.remove(arr, idx - 1)
    table.insert(arr, idx - 1, new_message)
    return idx - 1
  end

  table.insert(arr, idx, new_message)
  return idx
end

local function find_new_conversation_position(buf, draft_start, message)
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local start_insert = nil
  local message_position = reverse_search(M.ordered_messages[buf], message)
  local next_message = M.ordered_messages[buf][message_position]
  if next_message then
    start_insert = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, next_message.thread_mark_id, {})[1]
  else
    start_insert = draft_start and draft_start - 1 or total_lines
  end
  return start_insert, start_insert
end

local function find_new_reply_position(buf, message)
  local base_message = M.message_registry[buf][message.thread_id]
  if not base_message then
    error("No thread found for reply")  -- ignore replies to threads we don't show
  end
  if not M.ordered_replies[buf][message.thread_id] then
    M.ordered_replies[buf][message.thread_id] = {}
  end
  local reply_position = reverse_search(M.ordered_replies[buf][message.thread_id], message)

  local next_reply = M.ordered_replies[buf][message.thread_id][reply_position]
  local start_insert = nil
  if next_reply then
    start_insert = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, next_reply.mark_id, {})[1]
  else
    local positions = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, base_message.thread_mark_id, { details = true })
    start_insert = positions[3]["end_row"]
  end
  return start_insert, start_insert
end

local function get_thread_positions(buf, thread_id)
  local base_message = M.message_registry[buf][thread_id]
  local thread_positions = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, base_message.thread_mark_id, { })
  local start_line = thread_positions[1]
  local last_message = M.ordered_replies[buf][thread_id][#M.ordered_replies[buf][thread_id]]
  local last_line = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, last_message.mark_id, { details = true })[3]["end_row"]

  return start_line, last_line
end

local function get_message_positions(buf, message)
  local message_positions = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns_id, message.mark_id, { details = true })
  local start_line = message_positions[1]
  local last_line = message_positions[3]["end_row"]

  return start_line, last_line
end

local function insert_message(buf, draft_start, message)
  local old_message = M.message_registry[buf][message.id]

  -- find insert positions
  local start_insert = nil
  local end_insert = nil

  if not old_message then -- for a new message
    if not is_inside_thread(message) then
      start_insert, end_insert = find_new_conversation_position(buf, draft_start, message)
    else
      local success = false
      success, start_insert, end_insert = pcall(find_new_reply_position, buf, message)
      if not success then
        return  -- ignore replies to threads we don't show
      else
        insert_into_ordered(M.ordered_replies[buf][message.thread_id], message)
      end
    end
  else  -- for an old message
    start_insert, end_insert = get_message_positions(buf, old_message)
  end

  insert_formatted_message(buf, message, start_insert, end_insert)

  -- create/update thread mark
  if old_message and old_message.thread_mark_id then
    message.thread_mark_id = old_message.thread_mark_id
  end

  local thread_start = nil
  local thread_end = nil

  if is_inside_thread(message) then
    local base_message = M.message_registry[buf][message.thread_id]
    thread_start, thread_end = get_thread_positions(buf, message.thread_id)

    local thread_mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, thread_start, 0, {
      id = base_message.thread_mark_id,
      end_row = thread_end,
      hl_mode = "combine",
    })
  else  -- new or old message that is not inside a thread, so potential thread start
    local message_position = insert_into_ordered(M.ordered_messages[buf], message)
    local prev_message = M.ordered_messages[buf][message_position - 1]
    local virt_lines = nil
    if not prev_message or prev_message.ts_date ~= message.ts_date then
      virt_lines = { { { message.ts_date, "ChatTimeHighlight" } } }
    end

    if M.ordered_replies[buf][message.thread_id] then
      thread_start, thread_end = get_thread_positions(buf, message.thread_id)
    else
      thread_start, thread_end = get_message_positions(buf, message)
    end
    local thread_mark_id = vim.api.nvim_buf_set_extmark(buf, M.ns_id, thread_start, 0, {
      id = message.thread_mark_id,
      end_row = thread_end,
      virt_lines = virt_lines,
      virt_lines_above = true,
      hl_mode = "combine",
    })
    message.thread_mark_id = thread_mark_id
    local next_message =  M.ordered_messages[buf][message_position + 1]
    -- if not old_message then
    --   insert_into_ordered(M.ordered_messages[buf], message)
    -- end
    if next_message and next_message.ts_date == message.ts_date then
      insert_message(buf, draft_start, next_message)
    end

  end


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

-- function M.foldlevel(linenum)
--   local level = 0
--   local buf = vim.api.nvim_get_current_buf()
--   local marks = vim.api.nvim_buf_get_extmarks(buf, M.ns_id, { linenum, 0 }, { linenum, -1 }, { overlap = true })
--   for _, mark in ipairs(marks) do
--     local mark_id = mark[1]
--     local found_level = M.mark_levels[buf][mark_id]["level"]
--     if found_level then
--       return found_level
--     end
--   end
--   return level
--
-- end
--
-- function _G.foldlevel_from_mark()
--   local linenum = vim.v.lnum
--   return M.foldlevel(linenum)
-- end
--
-- _G.foldtext_from_mark = function()
--   local fs = vim.v.foldstart
--   local fe = vim.v.foldend
--   local buf = vim.api.nvim_get_current_buf()
--   local marks = vim.api.nvim_buf_get_extmarks(buf, M.ns_id, { fs, 0 }, { fe - 1, -1 }, { overlap = true })
--   local count = 0
--   local folded_lines = fe - fs + 1
--   for _, mark in ipairs(marks) do
--     local mark_id = mark[1]
--     local found_level = M.mark_levels[buf][mark_id]["level"]
--     if found_level then
--       count = count + 1
--     end
--   end
--   return "[" .. count .. " replies]"
-- end

return M
