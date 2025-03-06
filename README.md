# kbmail.nvim

## Overview

**kbmail.nvim** is a Neovim plugin that serves as a frontend for unified communication via the kbunified backend. It provides a real-time, event-driven chat interface inside Neovim, allowing you to view messages from multiple channels (or mailboxes) and interact with them seamlessly. The plugin uses a JSON-based IPC protocol to communicate with the kbunified backend, enabling features like channel switching, live message updates, and interactive message composition using floating windows.

## Objectives

- **Unified Communication Frontend:**
  Provide a single, integrated Neovim interface to display messages from multiple chat protocols and email services handled by kbunified.

- **Event-Driven Interface:**
  Receive JSON events (such as new messages, channel updates, and notifications) from the backend and route them to the appropriate message buffers.

- **Interactive Message Composition:**
  Allow users to compose and send messages via a floating window. Commands (e.g., posting a message or leaving a channel) are sent back to the backend using JSON-formatted IPC messages.

- **Dynamic Channel Management:**
  Support multiple channels with independent message histories. A sidebar displays the list of channels (or mailboxes), and users can switch between them without losing any context.

## Features

- **Real-Time Message Streaming:**
  Live updates as messages arrive from kbunified, with automatic scrolling to display the latest messages.

- **Floating Window Composer:**
  Press "c" from the message buffer to open a floating window where you can type your message. Pressing Enter sends the message to the active channel.

- **Channel Sidebar and Switching:**
  The plugin maintains separate message buffers per channel and provides an interface to switch between channels. Unread messages or mentions in inactive channels can be highlighted or indicated via the sidebar.

- **Two-Way JSON IPC Communication:**
  Uses a consistent JSON protocol to receive events from the backend and send commands (such as `post_message` or `leave_channel`) back to it.

## Installation

To install **kbmail.nvim** using [lazy.nvim](https://github.com/folke/lazy.nvim), add the following to your Lazy setup in your Neovim configuration (typically in `lua/plugins.lua` or a similar file):

```lua
return {
  {
    "mraspaud/kbmail.nvim",
    dependencies = { "nvim-lua/plenary.nvim",
                     "j-hui/fidget.nvim",
    },
    config = function()
      require("kbmail").setup({})
    end,
  },
}
```
After saving your configuration, run :Lazy sync within Neovim to install the plugin.

in order to input emojis easily, a plugin like [emoji.nvim](https://github.com/Allaman/emoji.nvim) is recommended.

## Requirements

### kbunified Backend:

The plugin requires that the kbunified backend is running (see [kbunified](https://github.com/mraspaud/kbunified)) and accessible via the designated IPC socket (for example, /tmp/chat_commands.sock).

### Neovim 0.9+ or later:
The plugin uses Neovim’s Lua API and requires a recent version.

## Usage

## Start the Backend:

In Neovim, run the command defined by the plugin (for example, :KBChat) to open the chat interface. This will open a sidebar with channels and a main window for messages.

### Switch Channels:
Use the sidebar to select a channel. The plugin maps <CR> in the sidebar to switch the active message buffer.

### Compose Messages:
Press "c" in the active message buffer to open a floating window. Type your message and press Enter (in normal mode) to send it. The message is sent to the active channel via IPC.

## Contributing
Contributions, bug reports, and feature requests are welcome. Please open an issue or submit a pull request on GitHub.

## License
This project is licensed under the MIT License.
