require("mini.test").setup()
local new_set = MiniTest.new_set
local expect, eq = MiniTest.expect, MiniTest.expect.equality
local messages = require("kbmail.messages")
local test_buf = nil
local test_channel = { id = "test_channel",
                       name = "Test Channel",
                       service = { id = "test_service",
                                   name = "Test service" }}
local header_size = 3


local function reinitialise_buf()
  test_buf = messages.get_channel_buffer(test_channel)
  if test_buf then
    vim.api.nvim_buf_delete(test_buf, {})
  end
  test_buf = messages.create_channel_buffer(test_channel)
end


local T = new_set({
  hooks = {
    pre_once = function ()
        messages.extra_line = false
        messages.create_channel_buffer(messages.error_channel)
        messages.indent = ""
    end,
    pre_case = reinitialise_buf,
    post_case = function ()
        vim.api.nvim_buf_clear_namespace(test_buf, messages.ns_id, 0, -1)
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
                    id = "1",
                    ts_date = "2025-02-21",
                    ts_time = tstime,
                    body = "Hello world" }
  messages.append_message(test_channel, message)
  local printed = vim.api.nvim_buf_get_lines(test_buf, -3, -1, true)
  eq(printed, { display_name .. " 11:11", message.body })
  local author_line = header_size
  local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  eq(#extmarks, 4)

  local message_mark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 3, { details = true })
  eq(message_mark[1], header_size)  -- start line
  eq(message_mark[3]["end_row"], header_size + messages.message_size(message) )  -- end line
  eq(message_mark[3]["virt_text"], nil)

  local author_mark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 1, { details = true })
  eq(author_mark[2], 0)  -- start col
  eq(author_mark[3]["end_col"], string.len(display_name))  -- end line

  local time_mark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 2, { details = true })
  eq(time_mark[2], string.len(display_name) + 1)  -- start col
  eq(time_mark[3]["end_col"], string.len(display_name) + string.len(tstime) + 1)  -- end col

  local thread_mark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true })
  eq(thread_mark[1], header_size)  -- start line
  eq(thread_mark[3]["end_row"], header_size + messages.message_size(message))  -- end line
end

T["Test appending replies" ] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    body = "Hello world" }
  local message_replied = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    replies = { count = 1 },
                    thread_id = "1",
                    body = "Hello world" }
  local reply = { author = { display_name = "good_old_me", id = "me" },
                  id = "3",
                  thread_id = "1",
                  ts_date = "2025-02-21",
                  ts_time = "11:13",
                  body = "Hello too" }
  local messag2 = { author = { display_name = "good_old_me", id = "me" },
                    id = "2",
                    ts_time = "11:12",
                    ts_date = "2025-02-21",
                    body = "Hello again" }
  local printed = nil

  messages.append_message(test_channel, message)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
        })
  local author_line = header_size
  local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  local message_mark = extmarks[3]
  eq(message_mark[4]["virt_text"], nil)
  eq(#extmarks, 4)

  messages.append_message(test_channel, messag2)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:12", messag2.body,
        })

  messages.append_message(test_channel, message_replied)
  messages.append_message(test_channel, reply)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:13", reply.body,
                "good_old_me 11:12", messag2.body,
        })
  author_line = 3
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  message_mark = extmarks[3]
  eq(message_mark[4]["virt_text"][1][1], " 1 reply")

  local modified = { author = { display_name = "good_old_me", id = "me" },
                     id = "1",
                     ts_date = "2025-02-21",
                     ts_time = "11:11",
                     edit_time = "11:15",
                     body = "Hello world from neovim!" }
  messages.append_message(test_channel, modified)

  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", modified.body,
                "good_old_me 11:13", reply.body,
                "good_old_me 11:12", messag2.body,
        })
  author_line = 3
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  message_mark = extmarks[3]
  eq(message_mark[2], 3)  -- start line
  eq(message_mark[4]["end_row"], 5)  -- end line
  eq(message_mark[4]["virt_text"][1][1], "edited")
end

T["Test appending in wrong order" ] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "2",
                    ts_date = "2025-02-21",
                    ts_time = "11:15",
                    body = "Hello world" }
  local messag2 = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_date = "2025-02-21",
                    ts_time = "11:12",
                    body = "Hello again" }
  local printed = nil

  messages.append_message(test_channel, message)
  printed = vim.api.nvim_buf_get_lines(test_buf, -3, -1, true)
  eq(printed, { "good_old_me 11:15", message.body,
        })
  local author_line = header_size
  local extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { author_line, 0 }, { author_line, -1 }, { details = true } )
  local message_mark = extmarks[1]
  eq(message_mark[4]["virt_text"], nil)
  eq(#extmarks, 4)

  messages.append_message(test_channel, messag2)
  printed = vim.api.nvim_buf_get_lines(test_buf, -5, -1, true)
  eq(printed, { "good_old_me 11:12", messag2.body,
                "good_old_me 11:15", message.body,
        })
end


T["Test dateline"] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_date = "2025-02-20",
                    ts_time = "11:15",
                    body = "Hello world" }
  local messag3 = { author = { display_name = "good_old_me", id = "me" },
                    id = "3",
                    ts_date = "2025-02-21",
                    ts_time = "11:12",
                    body = "Hello again" }
  local messag4 = { author = { display_name = "good_old_me", id = "me" },
                    id = "4",
                    ts_date = "2025-02-21",
                    ts_time = "11:13",
                    body = "Hello again again" }
  local messag2 = { author = { display_name = "good_old_me", id = "me" },
                    id = "2",
                    ts_date = "2025-02-21",
                    ts_time = "11:11",
                    body = "Hello thrice" }

  local thread_extmark = nil
  messages.append_message(test_channel, message)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["virt_lines"][1][1][1], "2025-02-20")

  messages.append_message(test_channel, messag3)

  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 8, { details = true } )
  eq(thread_extmark[3]["virt_lines"][1][1][1], "2025-02-21")

  messages.append_message(test_channel, messag4)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 12, { details = true } )
  eq(thread_extmark[3]["virt_lines"], nil)

  messages.append_message(test_channel, messag2)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 16, { details = true } )
  eq(thread_extmark[3]["virt_lines"][1][1][1], "2025-02-21")
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 8, { details = true } )
  eq(thread_extmark[3]["virt_lines"], nil)
end


T["Test changing replies"] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    body = "Hello world" }
  local message_replied = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    replies = { count = 1 },
                    thread_id = "1",
                    body = "Hello world" }
  local reply1 = { author = { display_name = "good_old_me", id = "me" },
                   id = "3",
                   thread_id = "1",
                   ts_date = "2025-02-21",
                   ts_time = "11:13",
                   body = "Hello too" }
  local message_replied2 = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    replies = { count = 2 },
                    thread_id = "1",
                    body = "Hello world" }
  local reply2 = { author = { display_name = "good_old_me", id = "me" },
                   id = "4",
                   thread_id = "1",
                   ts_time = "11:14",
                   ts_date = "2025-02-21",
                   body = "Hello again" }
  local message_replied3 = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    replies = { count = 3 },
                    thread_id = "1",
                    body = "Hello world" }
  local reply0 = { author = { display_name = "good_old_me", id = "me" },
                   id = "2",
                   thread_id = "1",
                   ts_time = "11:12",
                   ts_date = "2025-02-21",
                   body = "Hello before" }
  local reply2_changed = { author = { display_name = "good_old_me", id = "me" },
                           id = "4",
                           thread_id = "1",
                           ts_time = "11:14",
                           ts_date = "2025-02-21",
                           body = "Hello again\nNow with an extra line" }
  local reply1_changed = { author = { display_name = "good_old_me", id = "me" },
                           id = "3",
                           thread_id = "1",
                           ts_date = "2025-02-21",
                           ts_time = "11:13",
                           body = "Hello too\nNow with extra content" }
  local printed = nil
  local thread_extmark = nil
  local extmarks = nil

  messages.append_message(test_channel, message)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
        })
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 2)
  eq(thread_extmark[3]["virt_lines"][1][1][1], "2025-02-21")

  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 4)

  messages.append_message(test_channel, message_replied)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
        })
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 2)
  eq(thread_extmark[3]["virt_lines"][1][1][1], "2025-02-21")
  local message_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 3, { details = true } )
  eq(message_extmark[3]["virt_text"][1][1], " 1 reply")

  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 4)

  messages.append_message(test_channel, reply1)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:13", reply1.body,
        })
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 7)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 4)

  messages.append_message(test_channel, message_replied2)
  messages.append_message(test_channel, reply2)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:13", reply1.body,
                "good_old_me 11:14", reply2.body,
        })
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 10)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 6)

  messages.append_message(test_channel, message_replied3)
  messages.append_message(test_channel, reply0)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:12", reply0.body,
                "good_old_me 11:13", reply1.body,
                "good_old_me 11:14", reply2.body,
        })
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 13)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 8)

  messages.append_message(test_channel, reply2_changed)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:12", reply0.body,
                "good_old_me 11:13", reply1.body,
                "good_old_me 11:14", "Hello again", "Now with an extra line",
        })
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 13)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 9)

  messages.append_message(test_channel, reply1_changed)
  printed = vim.api.nvim_buf_get_lines(test_buf, header_size, -1, true)
  eq(printed, { "good_old_me 11:11", message.body,
                "good_old_me 11:12", reply0.body,
                "good_old_me 11:13", "Hello too", "Now with extra content",
                "good_old_me 11:14", "Hello again", "Now with an extra line",
        })
  extmarks = vim.api.nvim_buf_get_extmarks(test_buf, messages.ns_id, { header_size, 0 }, { -1, -1 }, { details = true } )
  eq(#extmarks, 13)
  thread_extmark = vim.api.nvim_buf_get_extmark_by_id(test_buf, messages.ns_id, 4, { details = true } )
  eq(thread_extmark[3]["end_row"], header_size + 10)

end

-- T["Test foldexpr"] = function()
--   local message = { author = { display_name = "good_old_me", id = "me" },
--                     id = "1",
--                     ts_time = "11:11",
--                     ts_date = "2025-02-21",
--                     body = "Hello world" }
--   local message_replied = { author = { display_name = "good_old_me", id = "me" },
--                     id = "1",
--                     ts_time = "11:11",
--                     ts_date = "2025-02-21",
--                     replies = { count = 1 },
--                     thread_id = "1",
--                     body = "Hello world" }
--   local reply1 = { author = { display_name = "good_old_me", id = "me" },
--                    id = "3",
--                    thread_id = "1",
--                    ts_date = "2025-02-21",
--                    ts_time = "11:13",
--                    body = "Hello too" }
--   messages.append_message(test_channel, message)
--   messages.append_message(test_channel, message_replied)
--   messages.append_message(test_channel, reply1)
--   vim.api.nvim_set_current_buf(test_buf)
--   eq(messages.foldlevel(2), 0)
--   eq(messages.foldlevel(4), 0)
--   eq(messages.foldlevel(6), 1)
-- end

T["Test message under cursor"] = function()
  local message = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    body = "Hello world" }
  local message_replied = { author = { display_name = "good_old_me", id = "me" },
                    id = "1",
                    ts_time = "11:11",
                    ts_date = "2025-02-21",
                    replies = { count = 1 },
                    thread_id = "1",
                    body = "Hello world" }
  local reply1 = { author = { display_name = "good_old_me", id = "me" },
                   id = "3",
                   thread_id = "1",
                   ts_date = "2025-02-21",
                   ts_time = "11:13",
                   body = "Hello too" }
  messages.append_message(test_channel, message)
  messages.append_message(test_channel, message_replied)
  messages.append_message(test_channel, reply1)
  vim.api.nvim_win_set_buf(0, test_buf)
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  local msg = messages.get_message_under_cursor(test_buf)
  eq(msg.id, "1")
  vim.api.nvim_win_set_cursor(0, { 6, 0 })
  msg = messages.get_message_under_cursor(test_buf)
  eq(msg.id, "3")

end

return T
