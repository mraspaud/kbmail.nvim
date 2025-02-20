local ipc = {}

local messages = require("kbmail.messages")

function ipc.post_message(service_id, channel_id, message_body)
  local uv = vim.loop
  local function send_command(cmd_table)
    local socket = uv.new_pipe(false)
    socket:connect("/tmp/kb_commands.sock", function(err)
      if err then
        messages.debug("IPC connect error for commands: " .. err)
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
    service_id = service_id,
    body = message_body,
  })
end

function ipc.switch_channel(service_id, channel_id)
  local uv = vim.loop
  local function send_command(cmd_table)
    local socket = uv.new_pipe(false)
    socket:connect("/tmp/kb_commands.sock", function(err)
      if err then
        messages.debug("IPC connect error for commands: " .. err)
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
    command = "switch_channel",
    channel_id = channel_id,
    service_id = service_id,
  })
end

return ipc
