local M = {}

-- Global variable to hold the live message job ID.
M.live_chat_job = nil
M.channel_buffers = M.channel_buffers or {}
M.error_channel = "errors"
M.active_channel = nil
M.channel_tree = nil


-- Function to close both buffers and stop the job.
function M.CloseLiveChat(chan_buf, msg_buf)
  if M.live_chat_job then
    vim.fn.jobstop(M.live_chat_job)
    M.live_chat_job = nil
  end
  if chan_buf and vim.api.nvim_buf_is_valid(chan_buf) then
    vim.api.nvim_buf_delete(chan_buf, { force = true })
  end
  if msg_buf and vim.api.nvim_buf_is_valid(msg_buf) then
    vim.api.nvim_buf_delete(msg_buf, { force = true })
  end
end

-- Function to send a message to the backend.
-- This function uses the IPC system you implemented earlier.
function M.post_message(channel_id, message_body)
  local uv = vim.loop
  local function send_command(cmd_table)
    local socket = uv.new_pipe(false)
    socket:connect("/tmp/chat_commands.sock", function(err)
      if err then
        print("IPC connect error: " .. err)
        return
      end
      local json_cmd = vim.json.encode(cmd_table) .. "\n"
      print("posting \"" .. json_cmd .. "\" to " .. channel_id)
      socket:write(json_cmd, function()
        socket:shutdown()
        socket:close()
      end)
    end)
  end

  send_command({
    command = "post_message",
    channel_id = channel_id,
    body = message_body,
    service = "my_dummy_service"
  })
end

function M.open_send_message_window(channel_id)
  -- Calculate dimensions for the floating window.
  local width = math.floor(vim.o.columns * 0.5)
  local height = 3
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create a scratch buffer for the floating window.
  local buf = vim.api.nvim_create_buf(false, true)
  local opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
  }
  local win = vim.api.nvim_open_win(buf, true, opts)

  vim.bo[buf].modifiable = true

  -- Map <CR> in the floating window to send the message.
  vim.keymap.set("n", "<CR>", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local message = table.concat(lines, "\n")
    vim.api.nvim_win_close(win, true)
    -- Use the passed channel id instead of a global variable.
    if channel_id then
      M.post_message(channel_id, message)
    else
      print("No active channel!")
    end
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
end

local function start_draft(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if draft_start then return end  -- do not start a draft when there is already one.
  -- remove blank line
  vim.api.nvim_buf_set_lines(buf, -2, -1, false, {})

  vim.api.nvim_buf_set_var(buf, "draft_start", vim.api.nvim_buf_line_count(buf) + 1)

  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_get_var(buf, "draft_start"), 0 })
  vim.api.nvim_buf_del_keymap(buf, "n", "i")
  -- vim.api.nvim_feedkeys("i", "n", false)
end

local function send_draft(buf, channel_id)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if not draft_start then return end

  vim.keymap.set("n", "i", function()
    start_draft(buf)
  end, { buffer = buf, silent = true })

  local lines = vim.api.nvim_buf_get_lines(buf, draft_start - 1, -1, false)
  if #lines > 0 and lines[1] ~= "" then
    M.post_message(channel_id, table.concat(lines, "\n"))
  end
  vim.api.nvim_buf_set_lines(buf, draft_start - 1, -1, false, {})

  -- vim.api.nvim_buf_set_lines(buf, draft_start - 1, -1, false, { "" })
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)
end

local function cancel_draft(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if not draft_start then return end

  vim.keymap.set("n", "i", function()
    start_draft(buf)
  end, { buffer = buf, silent = true })
  -- Remove the draft lines
  vim.api.nvim_buf_set_lines(buf, draft_start - 1, -1, false, {})

  -- Reset draft state
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)

  -- vim.api.nvim_echo({ { "Draft cancelled", "WarningMsg" } }, false, {})
end

local function adjust_viewport(buf)
    local total_lines = vim.api.nvim_buf_line_count(buf)
    local win_height = vim.api.nvim_win_get_height(M.msg_win)

    -- If there are fewer messages than window height, add padding at the top
    if total_lines < win_height then
        local padding_needed = win_height - total_lines
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, vim.fn["repeat"]({ "" }, padding_needed))
    end
end

-- Function to get or create a message buffer for a given channel id.
local function get_channel_buffer(channel_id)
  if M.channel_buffers[channel_id] and vim.api.nvim_buf_is_valid(M.channel_buffers[channel_id]) then
    return M.channel_buffers[channel_id]
  end
  -- Create a new scratch buffer.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.api.nvim_buf_set_name(buf, "[" .. channel_id .. "]")
  -- vim.bo[buf].modifiable = false
  -- Optionally, set keymaps for closing the buffer.
  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, { buffer = buf, silent = true })
  -- vim.bo[buf].modifiable = true
  adjust_viewport(buf)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "This is the begining of the conversation for " .. channel_id .. " id: " .. vim.inspect(buf) })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
  -- vim.bo[buf].modifiable = false
  M.channel_buffers[channel_id] = buf
  vim.api.nvim_buf_set_var(buf, "channel_id", channel_id)
  vim.api.nvim_buf_set_var(buf, "draft_start", nil)
  vim.keymap.set("n", "c", function()
    -- Retrieve the channel id from the current buffer.
    -- local channel_id = vim.api.nvim_buf_get_var(0, "channel_id")
    M.open_send_message_window(channel_id)
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "i", function()
    start_draft(buf)
  end, { buffer = buf, silent = true, noremap = true })
  vim.keymap.set("n", "<Enter>", function ()
    send_draft(buf, channel_id)
  end,{ buffer = buf, silent = true })
  vim.keymap.set("n", "<leader>q", function ()
    cancel_draft(buf)
  end, { buffer = buf, silent = true, noremap = true })
  -- vim.api.nvim_buf_set_keymap(buf, "n", "<leader>q", ":lua cancel_draft()<CR>", { noremap = true, silent = true })
  return buf
end

local function maintain_draft_position(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  if not draft_start then return end  -- no draft to take care of.
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local draft_height = #vim.api.nvim_buf_get_lines(buf, draft_start - 1, -1, false)

  if draft_start and draft_start < total_lines then
    draft_start = total_lines - draft_height + 1
  end
  vim.api.nvim_buf_set_var(buf, "draft_start", draft_start)
end

local function split_message(message)
    local lines = {}
    for line in message:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end



local function is_at_bottom(buf)
  local last_line = vim.api.nvim_buf_line_count(buf)
  print("last line " .. last_line)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  print("cursor line " .. cursor_line)
  return cursor_line >= last_line - 2
end

local function last_line_is_visible(buf)
  local is_active = vim.api.nvim_win_get_buf(M.msg_win) == buf
  if not is_active then
    return false
  end
  local last_line = vim.api.nvim_buf_line_count(buf)
  local last_visible_line = vim.api.nvim_win_call(M.msg_win, function ()
    return vim.fn.line("w$")
  end)
  return last_visible_line >= last_line
end


-- Function to update a message buffer with a new message.
local function append_message(channel_id, message_text)
  local buf = get_channel_buffer(channel_id)
  -- adjust_viewport(buf)
  -- vim.bo[buf].modifiable = true
  local total_lines = vim.api.nvim_buf_line_count(buf)
  local draft_start = vim.api.nvim_buf_get_var(buf, "draft_start")
  local insert_pos = draft_start and draft_start - 1 or total_lines
  local message_lines = split_message(message_text)
  local should_scroll = last_line_is_visible(buf)
  vim.api.nvim_buf_set_lines(buf, insert_pos, insert_pos, false, message_lines)
  if not draft_start then
    if should_scroll then
      local cursor_pos = vim.api.nvim_win_get_cursor(0)  -- Save cursor position
      vim.api.nvim_win_set_cursor(M.msg_win, { vim.api.nvim_buf_line_count(buf), 0 })
      vim.api.nvim_win_set_cursor(M.msg_win, cursor_pos)
    end
    return
  end
  vim.api.nvim_buf_set_var(buf, "draft_start", draft_start + #message_lines)

  maintain_draft_position(buf)
  -- vim.bo[buf].modifiable = false
  -- Optionally, if this buffer is active in a window, scroll to the bottom.
  -- local wins = vim.fn.win_findbuf(buf)
  -- for _, win in ipairs(wins) do
  --   local total_lines = vim.api.nvim_buf_line_count(buf)
  --   vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
  -- end
end

local function debug(message)
  append_message(M.error_channel, message)
end


function M.switch_to(channel_id)
  local buf = get_channel_buffer(channel_id)
  vim.api.nvim_win_set_buf(M.msg_win, buf)
  vim.api.nvim_set_current_win(M.msg_win)
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
  M.active_channel = channel_id
end

local function add_channels(channels)
  local NT = require("nui.tree")
  for _, chan in ipairs(channels) do
    M.channel_tree:add_node(NT.Node({ text = chan.name, channel_id = chan.id }))
  end
  M.channel_tree:render(1)
end

local function make_channel_split()
  -- Create a vertical split for the sidebar.
  local NuiTree = require("nui.tree")
  local Split = require("nui.split")
  local NuiLine = require("nui.line")

  local split = Split({
    relative = "win",
    position = "left",
    size = 40,
  })

  split:mount()

  -- quit
  split:map("n", "q", function()
    split:unmount()
  end, { noremap = true })
  M.channel_tree = NuiTree({ winid = split.winid,
    bufnr = split.bufnr,
    nodes = { NuiTree.Node( { text = "Error log", channel_id = M.error_channel })},
    prepare_node = function(node)
      local line = NuiLine()

      line:append(string.rep("  ", node:get_depth() - 1))

      if node:has_children() then
        line:append(node:is_expanded() and " " or " ", "SpecialChar")
      else
        line:append("  ")
      end

      line:append(node.text)

      return line
    end,

  })

  local map_options = { noremap = true, nowait = true }

  -- print current node
  split:map("n", "<CR>", function()
    local node = M.channel_tree:get_node()
    debug("Switching to " .. node.channel_id)
    M.switch_to(node.channel_id)
  end, map_options)
end

local function handle_event(json_event)
  local ok, msg_obj = pcall(vim.fn.json_decode, json_event)
  if ok and type(msg_obj) == "table" then
    if msg_obj.event == "message" then
      local channel_id = msg_obj.channel_id or M.error_channel
      local body = msg_obj.author .. ": " .. msg_obj.body
      append_message(channel_id, body)
    elseif msg_obj.event == "channel_list" then
      local channels = msg_obj.channels
      add_channels(channels)
    else
      print(json_event)
      append_message(M.error_channel, json_event)
    end
  else
    -- If JSON decoding fails, fallback to a default channel.
    print(json_event)
    append_message(M.error_channel, json_event)
  end
end

function M.chat()
  -- make_channel_list()
  -- add_channels(channels)
  -- Open (or move to) the right window for the live messages.
  -- vim.cmd("wincmd l")
  M.msg_win = vim.api.nvim_get_current_win()
  make_channel_split()
  M.switch_to(M.error_channel)
  -- Define a function that will close both buffers.
  local close_both = function()
    M.CloseLiveChat(M.chan_buf, msg_buf)
  end

  -- Set key mappings for "q" in both buffers to call the close function.
  vim.keymap.set("n", "q", close_both, { buffer = M.chan_buf, silent = true })

  -- Start the asynchronous job for live messages.
  -- Adjust the path and flag as needed. Here we assume that running the binary with '--live'
  -- will continuously print new messages to stdout.
  local cmd = "~/usr/src/kbunified/target/release/kbunified ~/usr/src/kbunified/config.toml"
  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            handle_event(line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            append_message(M.error_channel, "stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      print("Live messages job exited with code " .. exit_code)
    end,
  })

  M.live_chat_job = job_id
end

function M.setup()
  vim.api.nvim_create_user_command("KBChat", M.chat, {})
end

return M
