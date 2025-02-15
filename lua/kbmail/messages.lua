
local M = {}

M.error_channel = { id = "errors", name = "Error Log" }
M.channel_buffers = {}

local ns_id = vim.api.nvim_create_namespace("chat_ui")

-- Define the sign used for editing indicators.
vim.fn.sign_define("ChatEditingIndicator", {
  text = "┃",
  texthl = "ChatEditingIndicator",
})

local function show_message_indicator(buf, line)
  vim.api.nvim_buf_set_extmark(buf, ns_id, line - 1, 0, {
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
  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, { buffer = buf, silent = true })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "This is the beginning of the conversation for " .. channel.name })
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

  return buf
end


function M.get_channel_buffer(channel)
  local channel_id = get_id(channel)
  if M.channel_buffers[channel_id] and vim.api.nvim_buf_is_valid(M.channel_buffers[channel_id]) then
    return M.channel_buffers[channel_id]
  end
end

local function split_message(message)
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
  unread_marker_id = vim.api.nvim_buf_set_extmark(buf, ns_id, last_line, 0, {
    virt_text = { { "  [New messages below]", "WarningMsg" } },
    virt_text_pos = "eol",
  })
end

function M.append_message(channel, message_text)
  local buf = M.get_channel_buffer(channel)
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  local insert_pos = draft_start and draft_start - 1 or total_lines
  local message_lines = split_message(message_text)
  if draft_start then
    vim.api.nvim_buf_set_var(buf, "draft_start", draft_start + #message_lines)
  end

  vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false, message_lines)

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local should_scroll = last_line_is_visible(win, #message_lines)
    if not draft_start then
      if should_scroll then
        local cursor_pos = vim.api.nvim_win_get_cursor(win)
        vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
        vim.api.nvim_win_set_cursor(win, cursor_pos)
      else
        show_unread_marker(buf)
      end
    end
  end
end

function M.debug(message)
  M.append_message(M.error_channel, message)
end

function M.switch_to(channel)
  local buf = M.get_channel_buffer(channel)
  local prior_win = vim.fn.win_getid(vim.fn.winnr("#"))
  vim.api.nvim_win_set_buf(prior_win, buf)
  vim.api.nvim_set_current_win(prior_win)
  vim.api.nvim_win_set_cursor(prior_win, { vim.api.nvim_buf_line_count(buf), 0 })
end

function M.add_channels(service, channels)
  M.debug("adding " .. service.name)
  for _, chan in ipairs(channels) do
    chan.service = service
    M.debug("and " .. chan.name)
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
