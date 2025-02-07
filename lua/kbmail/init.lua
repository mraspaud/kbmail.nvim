local M = {}

-- Global variable to hold the live message job ID.
M.live_chat_job = nil
M.channel_buffers = M.channel_buffers or {}
M.error_channel = "errors"
M.active_channel = nil

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
  print("posting \"" .. message_body .. "\" to " .. channel_id)
  local uv = vim.loop
  local function send_command(cmd_table)
    local socket = uv.new_pipe(false)
    socket:connect("/tmp/chat_commands.sock", function(err)
      if err then
        print("IPC connect error: " .. err)
        return
      end
      local json_cmd = vim.json.encode(cmd_table) .. "\n"
      socket:write(json_cmd, function()
        socket:shutdown()
        socket:close()
      end)
    end)
  end

  send_command({
    command = "post_message",
    channel_id = channel_id,
    body = message_body
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

-- Function to get or create a message buffer for a given channel id.
local function get_channel_buffer(channel_id)
  if M.channel_buffers[channel_id] and vim.api.nvim_buf_is_valid(M.channel_buffers[channel_id]) then
    return M.channel_buffers[channel_id]
  end
  -- Create a new scratch buffer.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  -- Optionally, set keymaps for closing the buffer.
  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, { buffer = buf, silent = true })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "This is the conversation for " .. channel_id .. " id: " .. vim.inspect(buf) })
  vim.bo[buf].modifiable = false
  M.channel_buffers[channel_id] = buf
  vim.api.nvim_buf_set_var(buf, "channel_id", channel_id)
  vim.keymap.set("n", "c", function()
    -- Retrieve the channel id from the current buffer.
    -- local channel_id = vim.api.nvim_buf_get_var(0, "channel_id")
    M.open_send_message_window(channel_id)
  end, { buffer = buf, silent = true })
  return buf
end

-- Function to update a message buffer with a new message.
local function append_message(channel_id, message_text)
  local buf = get_channel_buffer(channel_id)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { message_text })
  vim.bo[buf].modifiable = false
  -- Optionally, if this buffer is active in a window, scroll to the bottom.
  local wins = vim.fn.win_findbuf(buf)
  for _, win in ipairs(wins) do
    local total_lines = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
  end
end



function M.switch_to(channel_id)
  vim.api.nvim_win_set_buf(M.msg_win, get_channel_buffer(channel_id))
  M.active_channel = channel_id
end

local function create_channel_list_buffer()
  local chan_win = vim.api.nvim_get_current_win()
  M.chan_buf = vim.api.nvim_create_buf(false, true) -- not listed, scratch
  vim.api.nvim_buf_set_keymap(M.chan_buf, "n", "q", "", {})  -- set below after creating msg_buf
  vim.api.nvim_win_set_buf(chan_win, M.chan_buf)
  vim.keymap.set("n", "<CR>", function ()
    local line = vim.fn.line(".")
    local mapping = M.channel_mappings[M.chan_buf] or {}
    local channel_id = mapping[line]
    if channel_id then
      M.switch_to(channel_id)
    else
      print("No channel id found for this line")
    end
  end, { buffer = M.chan_buf, silent = true })  -- set below after creating msg_buf

  vim.bo[M.chan_buf].buftype   = "nofile"
  vim.bo[M.chan_buf].bufhidden = "wipe"
  vim.bo[M.chan_buf].modifiable = false
end

local function add_channels(channels)
  local channel_display = {}
  local channel_mapping = {}  -- maps line numbers (1-indexed) to channel ids

  for i, chan in ipairs(channels) do
    table.insert(channel_display, chan.name)
    channel_mapping[i] = chan.id
  end

  vim.bo[M.chan_buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.chan_buf, 0, -1, false, channel_display)
  vim.bo[M.chan_buf].modifiable = false
  M.channel_mappings = M.channel_mappings or {}
  M.channel_mappings[M.chan_buf] = channel_mapping
  M.switch_to(M.active_channel or channels[1].id)
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
      append_message(M.error_channel, json_event)
    end
  else
    -- If JSON decoding fails, fallback to a default channel.
    append_message(M.error_channel, json_event)
  end
end

function M.chat()
  -- Create a vertical split for the sidebar.
  vim.cmd("vsplit")
  vim.cmd("wincmd h")
  create_channel_list_buffer()
  -- add_channels(channels)
  -- Open (or move to) the right window for the live messages.
  vim.cmd("wincmd l")
  M.msg_win = vim.api.nvim_get_current_win()

  -- Define a function that will close both buffers.
  local close_both = function()
    M.CloseLiveChat(M.chan_buf, msg_buf)
  end

  -- Set key mappings for "q" in both buffers to call the close function.
  vim.keymap.set("n", "q", close_both, { buffer = M.chan_buf, silent = true })

  -- Start the asynchronous job for live messages.
  -- Adjust the path and flag as needed. Here we assume that running the binary with '--live'
  -- will continuously print new messages to stdout.
  local cmd = "~/usr/src/kbunified/target/release/kbunified"
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
