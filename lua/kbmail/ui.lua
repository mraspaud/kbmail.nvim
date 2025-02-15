
local ui = {}
local ipc = require("kbmail.ipc")
local messages = require("kbmail.messages")

-- Creates a sidebar split with a channel tree.
function ui.make_channel_split()
  local NuiTree = require("nui.tree")
  local Split = require("nui.split")
  local NuiLine = require("nui.line")

  local split = Split({
    relative = "win",
    position = "left",
    size = 40,
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
      line:append(node.text)
      return line
    end,
  })
  split:map("n", "<CR>", function()
    local node = channel_tree:get_node()
    if not node:has_children() then
      messages.debug("Switching to " .. node.channel.name)
      messages.switch_to(node.channel)
    end
  end, { noremap = true, nowait = true })

  return channel_tree
end

return ui
