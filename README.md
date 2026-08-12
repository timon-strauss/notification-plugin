# notification-plugin

Focus-aware macOS notifications for [Claude Code](https://docs.claude.com/en/docs/claude-code) — gives a notification to you whenever a Claude session runs in the background and needs your attention.

---

## Why not just use Claude Code's built-in notifications?

Claude Code ships a built-in notification hook, but it fires **every time** Claude wants attention, even if you're actively watching the terminal tab it's running in.
That gets noisy fast when you have multiple Claude sessions across tabs, windows, or apps.
The notification options for the terminal are also limited: You dont get a standard notification, only a sound cue!

This plugin adds two things the built-in system doesn't:

1. **Focus awareness.** It checks whether the exact terminal tab running this Claude session is frontmost. If you're already looking at it, no notification is sent. If you've tabbed away to another Terminal tab, another app or another window the notification fires.
2. **Click-to-focus.** Clicking the notification brings the correct terminal tab back to the front. This allows for very good control over many parallell sessions.
3. **Session-Identifier.** The notification also shows a short identifier for the sending sessions, so you know exactly in where to look.

---

## Requirements

- **macOS**
- **Claude Code** with plugin support
- **[terminal-notifier](https://github.com/julienXX/terminal-notifier)**: a small CLI that talks to macOS Notification Center
  ```sh
  brew install terminal-notifier
  ```
- **Terminal.app**: The standard terminal for macOS. Using other terminals like iTerm2, Kitty, VS Code terminal, etc also works, but tab identifying doesnt work then

---

## Installation

Install directly from this repository's marketplace:

```sh
/plugin marketplace add https://github.com/timon-strauss/notification-plugin.git
/plugin install notification-plugin@notification-marketplace
```

The hooks are wired up automatically via `hooks/hooks.json`. New Claude Code sessions will start using the plugin immediately.

### Verify

Start a Claude session in one terminal tab, switch to a different tab or app, and trigger any action that ends a turn (e.g. finish a prompt). You should see a macOS notification. Switch back to the tab and trigger another one: no notification should appear.

If nothing appears, check:
- `terminal-notifier` is installed and on your `PATH`.
- macOS Notification Center allows notifications from terminal-notifier (System Settings → Notifications → terminal-notifier).

---

## Updating

```sh
/plugin marketplace update notification-marketplace
/plugin update notification-plugin@notification-marketplace
```

Then restart your Claude Code session so it picks up the new hook scripts.

---

## Files

```
.
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # marketplace manifest (single-plugin marketplace)
└── hooks/
    ├── hooks.json           # hook registration (Notification + Stop)
    └── notification/
        ├── claude_notification_check.zsh   # focus check, gate the notification
        ├── claude_notification.zsh         # build + fire the notification
        └── claude_code_icon.png            # icon used in the toast
```

---