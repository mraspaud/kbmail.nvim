require("mini.test").setup()
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local messages = require("kbmail.messages")
local test_buf = nil
local test_channel = { id = "test_channel",
                       name = "Test Channel",
                       service = { id = "test_service",
                                   name = "Test service" }}


local function reinitialise_buf()
  test_buf = messages.get_channel_buffer(test_channel)
  if test_buf then
    vim.api.nvim_buf_delete(test_buf, {})
  end
  test_buf = messages.create_channel_buffer(test_channel)
  messages.message_registry = {}
end


local T = new_set({
  hooks = {
    pre_once = function ()
        messages.create_channel_buffer(messages.error_channel)
    end,
    pre_case = reinitialise_buf,
    post_case = function ()
        vim.api.nvim_buf_delete(test_buf, {})
    end,
  },
})
-- Actual tests definitions will go here
T['works'] = function()
  local x = 1 + 1
  eq(x, 2)
end

T["test append message"] = function()
  local display_name = "good_old_me"
  local tstime = "11:11"
  local message = { author = { display_name = display_name, id = "me" },
                    id = "fake_id",
                    ts_time = tstime,
                    body = "Hello world" }
  messages.append_message(test_channel, message)
  local printed = vim.api.nvim_buf_get_lines(test_buf, -3, -1, true)
  eq(printed, { display_name .. " 11:11", message.body })
  local author_line = 3
  local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  local message_mark = extmarks[1]
  eq(message_mark[2], 3)  -- start line
  eq(message_mark[4]["end_row"], 5)  -- end line
  eq(message_mark[4]["virt_text"], nil)
  local author_mark = extmarks[2]
  eq(author_mark[3], 0)  -- start col
  eq(author_mark[4]["end_col"], string.len(display_name))  -- end line
  local time_mark = extmarks[3]
  eq(time_mark[3], string.len(display_name) + 1)  -- start col
  eq(time_mark[4]["end_col"], string.len(display_name) + string.len(tstime) + 1)  -- end col
  -- for _, mark in ipairs(extmarks) do
  --   print(vim.inspect(mark))
  -- end

  eq(#extmarks, 3)
end

T["Test appending replies" ] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "fake_id",
                    ts_time = "11:11",
                    body = "Hello world" }
  local reply = { author = { display_name = "good_old_me", id = "me" },
                  id = "fake_id_too",
                  thread_id = "fake_id",
                  ts_time = "11:13",
                  body = "Hello too" }
  local messag2 = { author = { display_name = "good_old_me", id = "me" },
                    id = "another_fake_id",
                    ts_time = "11:12",
                    body = "Hello again" }
  local printed = nil

  messages.append_message(test_channel, message)
  printed = vim.api.nvim_buf_get_lines(test_buf, -3, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
        })
  local author_line = 3
  local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  local message_mark = extmarks[1]
  eq(message_mark[4]["virt_text"], nil)
  eq(#extmarks, 3)

  messages.append_message(test_channel, messag2)
  printed = vim.api.nvim_buf_get_lines(test_buf, -5, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:12", messag2.body,
        })

  messages.append_message(test_channel, reply)
  printed = vim.api.nvim_buf_get_lines(test_buf, -7, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:13", reply.body,
                "good_old_me 11:12", messag2.body,
        })
  author_line = 3
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  message_mark = extmarks[1]
  eq(message_mark[4]["virt_text"][1][1], " 1 reply")
  eq(#extmarks, 4)  -- we should have a thread extmark now too

  local modified = { author = { display_name = "good_old_me", id = "me" },
                     id = "fake_id",
                     ts_time = "11:11",
                     edit_time = "11:15",
                     body = "Hello world from neovim!" }
  messages.append_message(test_channel, modified)

  printed = vim.api.nvim_buf_get_lines(test_buf, -7, -1, true)
  eq(printed, { "good_old_me 11:11", modified.body,
                "good_old_me 11:13", reply.body,
                "good_old_me 11:12", messag2.body,
        })
  author_line = 3
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  message_mark = extmarks[1]
  eq(message_mark[2], 3)  -- start line
  eq(message_mark[4]["end_row"], 5)  -- end line
  eq(message_mark[4]["virt_text"][1][1], "edited")
end

return T
