#!/bin/zsh
#
# Claude Code notification focus check.
#
# Usage: claude_notification_check.zsh <event>
#   <event> = "notification" | "stop" | "stop_failure" | "menu"
#
# Only decides whether to notify: if the terminal tab running this Claude
# session is NOT currently focused, forward the event + hook JSON (from
# stdin) to claude_notification.zsh, which builds and fires the toast.

script_dir="${0:A:h}"

event="${1:-notification}"

# Per-hook enable/disable. Missing/unreadable config or missing key defaults
# to enabled, so existing installs keep working.
config_file="$script_dir/config.json"
case "$event" in
  stop)         hook_key="stop" ;;
  stop_failure) hook_key="stopFailure" ;;
  menu)         hook_key="permission" ;;
  *)            hook_key="" ;;
esac
if [[ -n "$hook_key" && -r "$config_file" ]]; then
  # Only literal `false` disables. Missing key -> jq emits "null"; anything
  # else (true, null, malformed) keeps the hook enabled.
  enabled=$(jq -r ".${hook_key}.enabled" "$config_file" 2>/dev/null)
  [[ "$enabled" == "false" ]] && exit 0
fi

# Buffer stdin so we can forward it to the notifier script later.
hook_json=$(cat)

# ---------------------------------------------------------------------------
# Focus detection.
#    We want to know: is the terminal tab running THIS Claude session
#    currently frontmost on screen? If yes, suppress the notification.
# ---------------------------------------------------------------------------

# Walk up the process tree from $pid until we find a process that has a
# controlling TTY attached. That TTY identifies the terminal tab this
# script is running in.
find_tty() {
  local pid=$1
  while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
    local tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -n "$tty" && "$tty" != "??" ]]; then
      echo "$tty"
      return
    fi
    # Not attached to a TTY (or "??") — climb one level up.
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
}

# PID of whichever GUI app is currently frontmost, via AppleScript / System Events.
frontmost_pid=$(osascript -e 'tell application "System Events" to get unix id of first application process whose frontmost is true' 2>/dev/null)

# TTY of the terminal tab that invoked this hook. $PPID is the parent
# process (the Claude Code process); from there we walk up until we hit
# a TTY.
my_tty=$(find_tty $PPID)

# Is the frontmost app in the same process ancestry as our TTY?
# Any process on our TTY (Claude, its shell, the terminal emulator itself)
# should eventually reach the frontmost app's PID if that app owns us.
terminal_focused=false
if [[ -n "$frontmost_pid" && -n "$my_tty" ]]; then
  for pid in $(ps -t "$my_tty" -o pid= 2>/dev/null); do
    while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
      if [[ "$pid" == "$frontmost_pid" ]]; then
        terminal_focused=true
        break 2
      fi
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
  done
fi

# Even if the terminal *app* is focused, the user might be on a DIFFERENT
# tab. Drill one level deeper for Apple's Terminal.app and compare the
# selected tab's TTY against ours. For iTerm / other terminals we can't
# reliably introspect tabs, so we treat "app focused" as good enough.
tab_focused=false
if $terminal_focused; then
  frontmost_app=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
  if [[ "$frontmost_app" == "Terminal" ]]; then
    # AppleScript returns something like "/dev/ttys001" — strip the path.
    active_tty=$(osascript -e 'tell application "Terminal" to get tty of selected tab of front window' 2>/dev/null)
    active_tty="${active_tty##*/}"
    if [[ -n "$active_tty" && "$active_tty" == "$my_tty" ]]; then
      tab_focused=true
    fi
  else
    # Non-Terminal.app (iTerm2 etc.) — trust the app-level focus check.
    tab_focused=true
  fi
fi

# ---------------------------------------------------------------------------
# Only notify if the user is NOT already looking at this tab.
# Hand off to the notifier with the event + original hook JSON.
# Pass the terminal app name and TTY so the notifier can wire a click
# action that brings THIS tab back to the front.
# ---------------------------------------------------------------------------
if ! $tab_focused; then
  # Walk up the process ancestry from $PPID until we find a process
  # owned by a GUI application. `lsappinfo` returns the bundle ID for
  # GUI-app processes and NULL for shell/helper processes — we take the
  # first non-NULL hit. This works generically for Terminal.app,
  # iTerm2, VS Code, Cursor, Warp, etc.
  find_bundle_id() {
    local pid=$PPID
    while [[ -n "$pid" && "$pid" != "1" && "$pid" != "0" ]]; do
      local bid=$(lsappinfo info -only bundleID "$pid" 2>/dev/null \
        | grep -o 'bundleID="[^"]*"' | cut -d'"' -f2)
      if [[ -n "$bid" ]]; then
        echo "$bid"
        return
      fi
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
  }
  bundle_id=$(find_bundle_id)

  printf '%s' "$hook_json" | \
    CLAUDE_BUNDLE_ID="$bundle_id" CLAUDE_TTY="$my_tty" CLAUDE_HOOK_KEY="$hook_key" \
    zsh "$script_dir/claude_notification.zsh" "$event"
fi
