local M = {}

-- Global variable to hold the live message job ID.
M.live_chat_job = nil
M.channel_buffers = M.channel_buffers or {}

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

-- Function to get or create a message buffer for a given channel id.
local function get_channel_buffer(channel_id)
  if M.channel_buffers[channel_id] and vim.api.nvim_buf_is_valid(M.channel_buffers[channel_id]) then
    return M.channel_buffers[channel_id]
  end
  -- Create a new scratch buffer.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  -- vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  -- Optionally, set keymaps for closing the buffer.
  vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(buf, { force = true }) end, { buffer = buf, silent = true })
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "This is the conversation for " .. channel_id })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { vim.inspect(buf) })
  vim.bo[buf].modifiable = false
  M.channel_buffers[channel_id] = buf
  return buf
end

-- Function to update a message buffer with a new message.
local function append_message(channel_id, message_text)
  local buf = get_channel_buffer(channel_id)
  vim.bo[buf].modifiable = true
  print(channel_id)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { message_text })
  vim.bo[buf].modifiable = false
  -- print(message_text)
  -- print(channel_id)
  -- print(vim.inspect(buf))
  -- Optionally, if this buffer is active in a window, scroll to the bottom.
  -- local wins = vim.fn.win_findbuf(buf)
  -- for _, win in ipairs(wins) do
  --   local total_lines = vim.api.nvim_buf_line_count(buf)
  --   vim.api.nvim_win_set_cursor(win, { total_lines, 0 })
  -- end
end

function M.switch_to(channel_id)
  vim.api.nvim_win_set_buf(M.msg_win, get_channel_buffer(channel_id))
end

function M.chat()
  -- Create a vertical split for the sidebar.
  vim.cmd("vsplit")
  vim.cmd("wincmd h")
  -- In the left window, create the channel sidebar.
  local chan_win = vim.api.nvim_get_current_win()
  M.chan_buf = vim.api.nvim_create_buf(false, true) -- not listed, scratch
  vim.api.nvim_win_set_buf(chan_win, M.chan_buf)
  local channels = {
    { id = "dummy_channel1", name = "Dummy Channel 1"},
    { id = "dummy_channel2", name = "Dummy Channel 2"}
  }
  local channel_display = {}
  local channel_mapping = {}  -- maps line numbers (1-indexed) to channel ids

  for i, chan in ipairs(channels) do
    table.insert(channel_display, chan.name)
    channel_mapping[i] = chan.id
  end

  vim.api.nvim_buf_set_lines(M.chan_buf, 0, -1, false, channel_display)
  M.channel_mappings = M.channel_mappings or {}
  M.channel_mappings[M.chan_buf] = channel_mapping
  vim.bo[M.chan_buf].buftype   = "nofile"
  vim.bo[M.chan_buf].bufhidden = "wipe"
  vim.bo[M.chan_buf].modifiable = false
  vim.api.nvim_buf_set_keymap(M.chan_buf, "n", "q", "", {})  -- set below after creating msg_buf
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

  -- Open (or move to) the right window for the live messages.
  vim.cmd("wincmd l")
  M.msg_win = vim.api.nvim_get_current_win()
  M.switch_to(channels[1].id)
  -- local msg_buf = vim.api.nvim_create_buf(false, true)
  -- vim.api.nvim_win_set_buf(M.msg_win, msg_buf)
  -- vim.bo[msg_buf].buftype   = "nofile"
  -- vim.bo[msg_buf].bufhidden = "wipe"
  -- vim.bo[msg_buf].modifiable = false
  -- vim.api.nvim_buf_set_keymap(msg_buf, "n", "q", "", {})  -- set below after creating msg_buf

  -- Define a function that will close both buffers.
  local close_both = function()
    M.CloseLiveChat(M.chan_buf, msg_buf)
  end

  -- Set key mappings for "q" in both buffers to call the close function.
  vim.keymap.set("n", "q", close_both, { buffer = M.chan_buf, silent = true })
  vim.keymap.set("n", "q", close_both, { buffer = msg_buf, silent = true })

  -- Start the asynchronous job for live messages.
  -- Adjust the path and flag as needed. Here we assume that running the binary with '--live'
  -- will continuously print new messages to stdout.
  local cmd = "~/src/kbcom/target/release/kbcom --live"
  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            local ok, msg_obj = pcall(vim.fn.json_decode, line)
            if ok and type(msg_obj) == "table" then
              local channel_id = msg_obj.channel_id or "general"
              local body = msg_obj.body or line
              append_message(channel_id, body)
            else
              -- If JSON decoding fails, fallback to a default channel.
              append_message("general", line)
            end
            -- Temporarily make the buffer modifiable to append the new line.
            -- vim.bo.modifiable = true
            -- vim.api.nvim_buf_set_lines(msg_buf, -1, -1, false, { line })
            -- vim.bo.modifiable = false
            -- local total_lines = vim.api.nvim_buf_line_count(msg_buf)
            -- vim.api.nvim_win_set_cursor(msg_win, { total_lines, 0 })
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            -- vim.bo.modifiable = true
            -- vim.api.nvim_buf_set_lines(msg_buf, -1, -1, false, { "stderr: " .. line })
            -- vim.bo.modifiable = false
            append_message("general", "stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      print("Live messages job exited with code " .. exit_code)
    end,
  })

  M.live_chat_job = job_id

  -- Create autocmds to ensure that if either buffer is wiped out, we close both.
  -- vim.api.nvim_create_autocmd("BufWipeout", {
  --   buffer = msg_buf,
  --   callback = function()
  --     M.CloseLiveChat(M.chan_buf, msg_buf)
  --   end,
  -- })
  -- vim.api.nvim_create_autocmd("BufWipeout", {
  --   buffer = M.chan_buf,
  --   callback = function()
  --     M.CloseLiveChat(M.chan_buf, msg_buf)
  --   end,
  -- })
end

function M.setup()
  vim.api.nvim_create_user_command("LiveChat", M.chat, {})
end

return M
