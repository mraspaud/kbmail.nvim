
local ui = {}
local ipc = require("kbmail.ipc")
local messages = require("kbmail.messages")

-- Creates a sidebar split with a channel tree.
function ui.make_channel_split()
  local NuiTree = require("nui.tree")
  local Split = require("nui.split")
  local NuiLine = require("nui.line")
  local NuiText = require("nui.text")

  local split = Split({
    relative = "win",
    position = "left",
    size = 50,
  })

  split:mount()

  -- Quit mapping.
  split:map("n", "q", function()
    split:unmount()
  end, { noremap = true })

  local channel_tree = require("kbmail.messages").channel_tree or NuiTree({
    winid = split.winid,
    bufnr = split.bufnr,
    nodes = { NuiTree.Node({ text = messages.error_channel.name, channel = messages.error_channel })},
    prepare_node = function(node)
      local line = NuiLine()
      line:append(string.rep("  ", node:get_depth() - 1))
      if node:has_children() then
        line:append(node:is_expanded() and " " or " ", "SpecialChar")
      else
        line:append("  ")
      end
      local chan_name = nil
      if node.channel then
        local content = node.text
        if node.channel.mentions and node.channel.mentions > 0 then
            content = content .." (" .. tostring(node.channel.mentions) .. ")"
        end
        chan_name = NuiText(content)
        if node.channel.unread then
          chan_name:set(content, "SpecialChar")
        end
        line:append(chan_name)
        node.chan_name = chan_name
      else
        line:append(node.text)
      end
      node.line = line
      return line
    end,
  })
  split:map("n", "<CR>", function()
    local node = channel_tree:get_node()
    if not node:has_children() then
      messages.debug("Switching to " .. node.channel.name)
      node.channel.unread = nil
      node.channel.mentions = 0
      channel_tree:render()
      messages.switch_to(node.channel)
    end
  end, { noremap = true, nowait = true })

  return channel_tree
end

return ui
