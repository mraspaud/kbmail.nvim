
local M = {}
local uv = vim.loop
local messages = require("kbmail.messages")
local ui = require("kbmail.ui")
M.cmd = nil

local function handle_event(json_event)
  local ok, msg_obj = pcall(vim.fn.json_decode, json_event)
  if ok and type(msg_obj) == "table" then
    if msg_obj.event == "message" then
      local channel = { id = msg_obj.channel_id, service = { id = msg_obj.service.id }}
      local body = msg_obj.message.author .. ":\n" .. msg_obj.message.body
      messages.append_message(channel, body)
    elseif msg_obj.event == "channel_list" then
      local channels = msg_obj.channels
      messages.add_channels(msg_obj.service, channels)
    else
      print("unknown event")
      messages.append_message(messages.error_channel, json_event)
    end
  else
    print("unknown type")
    messages.append_message(messages.error_channel, json_event)
  end
end

function M.chat()
  -- Set up the main message window.
  M.msg_win = vim.api.nvim_get_current_win()
  messages.msg_win = M.msg_win
  messages.channel_tree = ui.make_channel_split()
  messages.create_channel_buffer(messages.error_channel)
  messages.switch_to(messages.error_channel)

  -- Start the asynchronous job for live messages.
  -- Adjust the path and flag as needed. Here we assume that running the binary with '--live'
  -- will continuously print new messages to stdout.
  local job_id = vim.fn.jobstart(M.cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            messages.debug("stdout: " .. line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            messages.debug("stderr: " .. line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      messages.debug("Backend exited with code " .. exit_code)
    end,
  })

  M.chat_job = job_id

  local close_both = function()
    if M.chat_job then
      vim.fn.jobstop(M.chat_job)
      M.chat_job = nil
    end
    if messages.chan_buf and vim.api.nvim_buf_is_valid(messages.chan_buf) then
      vim.api.nvim_buf_delete(messages.chan_buf, { force = true })
    end
    if M.msg_buf and vim.api.nvim_buf_is_valid(M.msg_buf) then
      vim.api.nvim_buf_delete(M.msg_buf, { force = true })
    end
  end

  vim.keymap.set("n", "q", close_both, { buffer = messages.chan_buf, silent = true })

  local socket_path = "/tmp/kb_events.sock"
  local timer = uv.new_timer()
  timer:start(0, 100, function()
    if uv.fs_stat(socket_path) then
      timer:stop()
      timer:close()
      local client = uv.new_pipe(false)
      client:connect(socket_path, function(err)
        if err then
          vim.schedule(function()
            messages.debug("IPC connect error for events: " .. err)
          end)
          return
        end
        client:read_start(function(err, chunk)
          if err then
            vim.schedule(function()
              messages.debug("Read error: " .. err)
            end)
            return
          end
          if chunk then
            for line in chunk:gmatch("[^\r\n]+") do
              if line ~= "" then
                vim.schedule(function()
                  handle_event(line)
                end)
              end
            end
          end
        end)
      end)
      M.live_chat_client = client
    end
  end)
end

function M.setup(parameters)
  M.cmd = parameters.command or "kbunified"
  vim.api.nvim_create_user_command("KBChat", M.chat, {})
end

return M

