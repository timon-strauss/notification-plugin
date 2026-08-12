---
description: View or edit notification-plugin settings (sounds, per-hook enable/disable).
argument-hint: "[key=value ...]  e.g. stop.enabled=false  stop.sound=Glass"
allowed-tools: Bash(zsh:*)
---

You are editing the notification-plugin's `config.json` on behalf of the user.

The single source of truth for reads, writes, and validation is the helper script:

    ${CLAUDE_PLUGIN_ROOT}/hooks/notification/config_edit.zsh

**Never read or edit `config.json` directly.** Always shell out to the helper. Do not use Read, Edit, or Write on `config.json`. Only use keys returned by `list-keys` and sound values returned by `list-sounds` — never invent values.

**Always re-render settings after any successful write.** After any successful `set` call — or sequence of `set` calls — the last action of the turn MUST be to run `... list` and print its output verbatim inside a **plain code fence** (no `json` language tag; the helper's `list` output is already formatted text, not JSON). This applies to one-shot mode, show-and-ask mode, and any recovery after a partial-write error where some `set` calls already succeeded.

User arguments: `$ARGUMENTS`

## Dispatch

- If `$ARGUMENTS` is empty → **show-and-ask mode**.
- Else → **one-shot mode**: treat each whitespace-separated token as `key=value`.

## Show-and-ask mode

1. Run `zsh "${CLAUDE_PLUGIN_ROOT}/hooks/notification/config_edit.zsh" list` and print the output verbatim inside a plain code fence, titled "Current configuration".
2. In plain text, ask the user: **"What do you want to change?"** Then stop the turn and wait for their reply.
3. When the user's next message arrives, interpret it as one or more desired changes. Map each to a `key=value` pair using the settable keys from `list-keys` and — for sound changes — the whitelist from `list-sounds`. Fetch these lists from the helper if you need to reference them; do not rely on memory.
4. If the reply is "nothing", "cancel", empty, or otherwise clearly declines → print "No changes made." and stop. Do not issue any `set`.
5. If any part of the reply is ambiguous, refers to an unknown key, or names a sound not in `list-sounds` → tell the user exactly what you couldn't map (e.g. `"unknown sound: Wobble — valid sounds are: <list>"`) and stop **without writing anything**. Do not guess.
6. Otherwise, run `zsh "${CLAUDE_PLUGIN_ROOT}/hooks/notification/config_edit.zsh" set <key> <value>` for each mapped pair, in the order the user gave them. On the first non-zero exit, surface the helper's stderr verbatim and stop processing remaining pairs — then still run `... list` (per the top-of-file rule) to show the actual post-partial-write state.
7. After all `set` calls succeed, run `... list` and print its output verbatim inside a plain code fence — this is required, not optional.

## One-shot mode

For each whitespace-separated token in `$ARGUMENTS`, in order:

1. Split on the first `=` into `key` and `value`. If the token has no `=`, print `invalid arg (expected key=value): <token>` and stop — do not process remaining tokens.
2. Run `zsh "${CLAUDE_PLUGIN_ROOT}/hooks/notification/config_edit.zsh" set "<key>" "<value>"`.
3. If exit code is non-zero, surface the helper's stderr verbatim and stop processing remaining tokens.

Whether all `set` calls succeed or the run halts mid-way after at least one succeeded, the final action of the turn MUST be `... list` printed verbatim in a plain code fence. Only skip the render if **no** `set` call was ever invoked (e.g. the first token had no `=`, or the very first `set` failed on validation before any write).

## Error handling

- Never retry a helper call silently. Show the helper's stderr as-is.
- If the helper reports missing `jq` (exit 6), tell the user: "This plugin requires `jq`. Install with `brew install jq`."
- If the helper reports malformed JSON (exit 5) or missing config (exit 2), tell the user to reinstall the plugin — do not attempt to recreate `config.json`.
