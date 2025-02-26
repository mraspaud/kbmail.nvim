local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"

local M = {}

function M.pick_channel(opts)
  opts = opts or {}
  local messages = require("kbmail.messages")
  local results = {}
  for key, channel_entry in pairs(messages.channel_buffers) do
    table.insert(results, channel_entry["channel"])
  end
  pickers.new(opts, {
    prompt_title = "service/channel",
    finder = finders.new_table {
      results = results,
      entry_maker = function (entry)
        local display = entry["name"]
        if entry["service"] then
          display = entry["service"]["name"] .. "/" .. entry["name"]
        end
        return {
          value = entry,
          display = display,
          ordinal = display,
        }
      end
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        print(vim.inspect(selection))
        local channel = selection["value"]
        messages.switch_to(channel)
      end)
      return true
    end,
  }):find()
end

return M
