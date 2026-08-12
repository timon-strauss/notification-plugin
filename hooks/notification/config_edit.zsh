#!/bin/zsh
#
# notification-plugin config editor.
#
# Sole read/write/validate entry point for config.json. The /config slash
# command shells out to this script — nothing else should edit config.json.
#
# Usage:
#   config_edit.zsh list
#   config_edit.zsh get <key>
#   config_edit.zsh set <key> <value>
#   config_edit.zsh list-sounds
#   config_edit.zsh list-keys
#   config_edit.zsh validate
#
# Exit codes:
#   0  ok
#   1  usage error
#   2  I/O error (config.json missing/unreadable/unwritable)
#   3  unknown key
#   4  invalid value (bad bool or unknown sound)
#   5  malformed JSON
#   6  missing jq

set -u

script_dir="${0:A:h}"
config_file="$script_dir/config.json"

# Case-sensitive; mirrors the valid_sounds array in claude_notification.zsh.
VALID_SOUNDS=(Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr \
              Sosumi Submarine Tink default none)
BOOL_KEYS=(stop.enabled stopFailure.enabled permission.enabled)
SOUND_KEYS=(defaultSound stop.sound stopFailure.sound permission.sound)

die() { print -u2 -- "config_edit: $2"; exit $1 }

is_bool_key()    { (( ${BOOL_KEYS[(Ie)$1]}    )) }
is_sound_key()   { (( ${SOUND_KEYS[(Ie)$1]}   )) }
is_valid_sound() { (( ${VALID_SOUNDS[(Ie)$1]} )) }

# Atomic write: same-dir tmp file + mv = rename(2), so a concurrent hook
# script reader never sees a torn file.
write_atomic() {
  local tmp
  tmp="$(mktemp "${config_file}.XXXXXX")" || die 2 "mktemp failed"
  cat > "$tmp" || { rm -f "$tmp"; die 2 "write failed"; }
  jq -e . "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; die 5 "produced invalid JSON"; }
  mv -f "$tmp" "$config_file" || { rm -f "$tmp"; die 2 "mv failed"; }
}

command -v jq >/dev/null 2>&1 || die 6 "jq not found on PATH (brew install jq)"

sub="${1:-}"
(( $# )) && shift

# Subcommands that don't touch config.json — no need to validate the file.
case "$sub" in
  list-sounds) printf '%s\n' "${VALID_SOUNDS[@]}"; exit 0 ;;
  list-keys)   printf '%s\n' "${BOOL_KEYS[@]}" "${SOUND_KEYS[@]}"; exit 0 ;;
  ""|-h|--help)
    die 1 "usage: config_edit.zsh {list|get <key>|set <key> <value>|list-sounds|list-keys|validate}" ;;
esac

[[ -r "$config_file" ]] || die 2 "cannot read $config_file"
jq -e . "$config_file" >/dev/null 2>&1 || die 5 "malformed JSON in $config_file"

case "$sub" in
  list)
    # Pretty, aligned view. Column widths are hardcoded — every render is
    # identical. Missing `.enabled` → enabled (matches hook runtime).
    # Missing `.sound`   → "(defaultSound)" so the fallback is visible.
    local raw
    raw=$(jq -r '[
      (.defaultSound       // ""),
      (.stop.enabled        | tostring),
      (.stop.sound         // ""),
      (.stopFailure.enabled | tostring),
      (.stopFailure.sound  // ""),
      (.permission.enabled  | tostring),
      (.permission.sound   // "")
    ] | @tsv' "$config_file")
    # Split on literal tab, preserving empty fields (`read -r` with IFS=$'\t'
    # collapses adjacent tabs on macOS zsh, so we use array-parameter split).
    local -a fields
    fields=("${(@ps:\t:)raw}")
    local ds="${fields[1]}"  se="${fields[2]}"  ss="${fields[3]}"
    local sfe="${fields[4]}" sfs="${fields[5]}"
    local pe="${fields[6]}"  ps="${fields[7]}"

    print -- "notification-plugin settings"
    print --
    if [[ -z "$ds" ]]; then
      printf '  %-12s  (unset — falls back to macOS default)\n' "defaultSound"
    else
      printf '  %-12s  %s\n' "defaultSound" "$ds"
    fi
    print --

    render_hook() {
      local name="$1" enabled_raw="$2" sound="$3"
      # `status` is a read-only builtin in zsh — use `state` instead.
      local indicator state
      # "false" disables; anything else (true / null / missing / malformed)
      # keeps the hook enabled, mirroring claude_notification_check.zsh:26-29.
      if [[ "$enabled_raw" == "false" ]]; then
        indicator="○"; state="disabled"
      else
        indicator="●"; state="enabled"
      fi
      [[ -z "$sound" ]] && sound="(defaultSound)"
      printf '  %s %-11s  %-8s  sound: %s\n' "$indicator" "$name" "$state" "$sound"
    }

    render_hook stop        "$se"  "$ss"
    render_hook stopFailure "$sfe" "$sfs"
    render_hook permission  "$pe"  "$ps"
    ;;

  get)
    key="${1:-}"
    [[ -n "$key" ]] || die 1 "usage: get <key>"
    is_bool_key "$key" || is_sound_key "$key" || die 3 "unknown key: $key (see \`list-keys\`)"
    # `if . == null then "" else . end` — `// empty` would swallow `false`.
    jq -r ".${key} | if . == null then \"\" else . end" "$config_file"
    ;;

  set)
    key="${1:-}"
    val="${2:-}"
    [[ -n "$key" && -n "$val" ]] || die 1 "usage: set <key> <value>"

    if is_bool_key "$key"; then
      [[ "$val" == "true" || "$val" == "false" ]] \
        || die 4 "value for $key must be true or false (got: $val)"
      jq --argjson v "$val" ".${key} = \$v" "$config_file" | write_atomic
    elif is_sound_key "$key"; then
      is_valid_sound "$val" \
        || die 4 "invalid sound: $val (see \`list-sounds\`)"
      jq --arg v "$val" ".${key} = \$v" "$config_file" | write_atomic
    else
      die 3 "unknown key: $key (see \`list-keys\`)"
    fi
    print -- "$val"
    ;;

  validate)
    for k in $BOOL_KEYS; do
      v=$(jq -r ".${k} | if . == null then \"\" else . end" "$config_file")
      [[ -z "$v" || "$v" == "true" || "$v" == "false" ]] \
        || die 4 "$k has non-bool value: $v"
    done
    for k in $SOUND_KEYS; do
      v=$(jq -r ".${k} | if . == null then \"\" else . end" "$config_file")
      [[ -z "$v" ]] && continue
      is_valid_sound "$v" || die 4 "$k has invalid sound: $v"
    done
    print -- ok
    ;;

  *) die 1 "unknown subcommand: $sub" ;;
esac
