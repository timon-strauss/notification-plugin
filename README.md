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
3. **Session-Identifier.** The notification also shows a short identifier for the sending sessions, so you know exactly in where to look. If you have set a custom name for the session via Claude Code's `/rename` command, that name is used; otherwise the plugin falls back to Claude's auto-generated session title, then the last user prompt.

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

## Configuration

Configure the plugin from inside any Claude session that uses the plugin.

### Option 1 — Direct: `/notifications-config <key>=<value>`

Pass one or more `key=value` pairs to apply changes immediately. Fastest when you know exactly what you want to change.

```sh
# Change the sound played when a turn ends
/notifications-config stop.sound=Glass

# Silence just the permission-request notifications
/notifications-config permission.enabled=false

# Multiple changes in one call
/notifications-config stop.enabled=true stop.sound=Ping defaultSound=Hero
```

**Valid keys:**

| Key | Values | What it controls |
|---|---|---|
| `defaultSound` | any sound name (see below) | Fallback sound when a hook has no `sound` of its own |
| `stop.enabled` | `true` / `false` | Notification when a turn finishes normally |
| `stop.sound` | any sound name | Sound for `stop` notifications |
| `stopFailure.enabled` | `true` / `false` | Notification when a turn ends via API error |
| `stopFailure.sound` | any sound name | Sound for `stopFailure` notifications |
| `permission.enabled` | `true` / `false` | Notification when Claude asks for tool permission |
| `permission.sound` | any sound name | Sound for `permission` notifications |

**Valid sound names:** `Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`, `Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`, `default`, or `none` for a silent notification (toast still appears).

Invalid keys, unknown sound names, or non-boolean values for `enabled` are rejected before anything is written.

### Option 2 — Interactive: `/notifications-config`

Run the command with no arguments to see the current settings and describe your changes in plain language. Claude figures out the right keys and applies them.

```sh
/notifications-config
```

Then reply with something like:

- *"turn off stop notifications"*
- *"change the sound for stopFailure to Basso and set the default sound to Glass"*
- *"make permission prompts silent but keep the toast"*
- *"nothing"* or *"cancel"* to leave everything as-is

Best when you don't remember the exact key names or want to change several things at once.

### Notes

- Changes take effect on the next hook fire — no restart needed.
- **Sound fallback chain:** hook `sound` → `defaultSound` → macOS `default` sound.
- The config lives at `hooks/notification/config.json` if you'd rather edit it directly. Missing keys or an unreadable file fall back to all hooks enabled with the `default` sound.

---

## Files

```
.
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # marketplace manifest (single-plugin marketplace)
├── commands/
│   └── notifications-config.md  # /notifications-config slash command
└── hooks/
    ├── hooks.json           # hook registration (Notification + Stop + StopFailure)
    └── notification/
        ├── config.json                     # user configuration (sound, …)
        ├── config_edit.zsh                 # /config helper: read/write/validate
        ├── claude_notification_check.zsh   # focus check, gate the notification
        ├── claude_notification.zsh         # build + fire the notification
        └── claude_code_icon.png            # icon used in the toast
```

---
