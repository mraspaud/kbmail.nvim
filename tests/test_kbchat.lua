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

T["test create channel buffer"] = function()
  local ch_name = "Test Channel 3"
  local channel = { id = "test_channel_3",
                       name = ch_name }
  local buf = messages.create_channel_buffer(channel)
  local printed = vim.api.nvim_buf_get_lines(buf, 1, 2, true)
  vim.api.nvim_buf_delete(buf, {})

  eq(printed[1], "# This is the beginning of the conversation for " .. ch_name)
end

T["test hook"] = function()
  local printed = vim.api.nvim_buf_get_lines(test_buf, 1, 2, true)
  eq(printed[1], "# This is the beginning of the conversation for Test Channel")
end


T["test append message"] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "fake_id",
                    ts_time = "11:11",
                    body = "Hello world" }
  messages.append_message(test_channel, message)
  local printed = vim.api.nvim_buf_get_lines(test_buf, -3, -1, true)
  eq(printed, { "good_old_me 11:11", message.body })
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

  local modified = { author = { display_name = "good_old_me", id = "me" },
                     id = "fake_id",
                     ts_time = "11:11",
                     body = "Hello world from neovim!" }
  messages.append_message(test_channel, modified)

  printed = vim.api.nvim_buf_get_lines(test_buf, -7, -1, true)
  eq(printed, { "good_old_me 11:11", modified.body,
                "good_old_me 11:13", reply.body,
                "good_old_me 11:12", messag2.body,
        })
end

return T
