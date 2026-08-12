#!/bin/zsh
#
# Build the notification (title from event, message from the user's last
# prompt in the transcript) and fire it via terminal-notifier.
#
# Usage: claude_notification.zsh <event>
#   <event> = "notification" | "stop" | "menu"
#
# Reads the hook JSON payload from stdin to locate the transcript.

script_dir="${0:A:h}"

# ---------------------------------------------------------------------------
# 0) Load user config from config.json next to this hook. The only default
#    lives in config.json itself — no inline fallback here. Missing file,
#    missing key, "none", or an unrecognized sound name all resolve to
#    "no sound" downstream (the -sound flag is simply omitted).
# ---------------------------------------------------------------------------
config_file="$script_dir/config.json"

sound=""
if [[ -r "$config_file" ]]; then
  sound=$(jq -r '.sound // empty' "$config_file" 2>/dev/null)
fi

# ---------------------------------------------------------------------------
# 1) Event -> title. Message is filled from the transcript below.
# ---------------------------------------------------------------------------
event="${1:-notification}"

case "$event" in
  stop)
    title="Claude Session Done!"
    ;;
  menu)
    title="Claude Session needs Approval!"
    ;;
  *)
    title="Claude Session needs Attention!"
    ;;
esac

# ---------------------------------------------------------------------------
# 2) Parse the hook JSON from stdin and pull the user's last prompt
#    out of the transcript. That becomes the notification body.
# ---------------------------------------------------------------------------
hook_json=$(cat)

# `// empty` makes jq print nothing (instead of "null") when the key is absent.
transcript_path=$(printf '%s' "$hook_json" | jq -r '.transcript_path // empty' 2>/dev/null)

message="Your Session"
if [[ -n "$transcript_path" && -r "$transcript_path" ]]; then
  # Preference order:
  #   1. `custom-title` — name the user set explicitly via `/rename`.
  #   2. `ai-title`      — Claude Code's own short summary shown in /resume.
  #   3. `last-prompt`   — the user's last prompt (dedicated event).
  #   4. plain-string user messages (fallback for sessions missing `last-prompt`).
  body=$(jq -r 'select(.type=="custom-title") | .customTitle' "$transcript_path" 2>/dev/null | tail -n1)
  if [[ -z "$body" ]]; then
    body=$(jq -r 'select(.type=="ai-title") | .aiTitle' "$transcript_path" 2>/dev/null | tail -n1)
  fi
  if [[ -z "$body" ]]; then
    body=$(jq -r 'select(.type=="last-prompt") | .lastPrompt' "$transcript_path" 2>/dev/null | tail -n1)
  fi
  if [[ -z "$body" ]]; then
    body=$(jq -r 'select(.type=="user" and (.message.content|type=="string")) | .message.content' "$transcript_path" 2>/dev/null | tail -n1)
  fi

  # Flatten newlines so the notification stays on one line.
  body="${body//$'\n'/ }"

  # Truncate to 120 chars with an ellipsis to keep the toast tidy.
  if (( ${#body} > 120 )); then
    body="${body:0:120}…"
  fi

  if [[ -n "$body" ]]; then
    message="$body"
  fi
fi

# ---------------------------------------------------------------------------
# 3) Build a click action: when the user clicks the notification, bring
#    the app that fired it back to the front. CLAUDE_BUNDLE_ID and
#    CLAUDE_TTY are set by claude_notification_check.zsh.
#    - Terminal.app: activate + select the exact tab by TTY.
#    - Any other GUI app (VS Code, Cursor, iTerm2, Warp, …): just
#      activate the app via its bundle id.
# ---------------------------------------------------------------------------
bundle_id="${CLAUDE_BUNDLE_ID}"
my_tty="${CLAUDE_TTY}"

if [[ "$bundle_id" == "com.apple.Terminal" && -n "$my_tty" ]]; then
  # macOS Terminal reports tty as e.g. "/dev/ttys001"; $my_tty is "ttys001".
  # One `-e` per statement — avoids all the quoting pain of a multi-line script.
  click_cmd="osascript"
  click_cmd+=" -e 'tell application \"Terminal\"'"
  click_cmd+=" -e 'activate'"
  click_cmd+=" -e 'repeat with w in windows'"
  click_cmd+=" -e 'repeat with t in tabs of w'"
  click_cmd+=" -e 'if tty of t is \"/dev/${my_tty}\" then'"
  click_cmd+=" -e 'set selected of t to true'"
  click_cmd+=" -e 'set index of w to 1'"
  click_cmd+=" -e 'return'"
  click_cmd+=" -e 'end if'"
  click_cmd+=" -e 'end repeat'"
  click_cmd+=" -e 'end repeat'"
  click_cmd+=" -e 'end tell'"
elif [[ -n "$bundle_id" ]]; then
  # `open -b` activates any macOS app by bundle id, including out of the Dock.
  click_cmd="open -b '${bundle_id}'"
else
  # Couldn't resolve a GUI owner — no click action.
  click_cmd=""
fi

# ---------------------------------------------------------------------------
# 4) Fire the notification.
#    terminal-notifier is a small Homebrew tool that talks to the macOS
#    Notification Center from the shell. `-execute` runs a shell command
#    when the user clicks the toast.
# ---------------------------------------------------------------------------
notifier_args=(
  -title "$title"
  -message "$message"
  -contentImage "$script_dir/claude_code_icon.png"
)
# Only pass -sound if the config value is a valid macOS system sound.
# Empty, "none", or unrecognized names => notification without sound.
valid_sounds=(Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr Sosumi Submarine Tink default)
if [[ -n "$sound" && "${sound:l}" != "none" && ${valid_sounds[(Ie)$sound]} -ne 0 ]]; then
  notifier_args+=(-sound "$sound")
fi
if [[ -n "$click_cmd" ]]; then
  notifier_args+=(-execute "$click_cmd")
fi

terminal-notifier "${notifier_args[@]}"
