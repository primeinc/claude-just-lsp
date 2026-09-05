#!/bin/sh
# PostToolUse hook: run `just-lsp analyze` on the justfile Claude just edited and
# hand the report to Claude as hookSpecificOutput.additionalContext (exit 0).
#
# Reads the hook JSON on stdin and takes the edited path from
# tool_input.file_path. Only that file is analyzed. When a prerequisite is
# missing, one fixed line goes to stderr with exit 2, which PostToolUse shows
# to Claude; nothing else is analyzed in its place.
set -u

input=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  printf 'just-lsp hook: jq is not on PATH, so the edited file was not analyzed. Install jq: https://jqlang.org\n' >&2
  exit 2
fi

if ! command -v just-lsp > /dev/null 2>&1; then
  printf 'just-lsp hook: just-lsp is not on PATH, so the edited file was not analyzed. Install: cargo install just-lsp (https://github.com/terror/just-lsp#installation)\n' >&2
  exit 2
fi

target=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2> /dev/null) || target=""
if [ -z "$target" ]; then
  printf 'just-lsp hook: hook input carried no tool_input.file_path, so nothing was analyzed.\n' >&2
  exit 2
fi

# analyze prints diagnostics to stdout and its own failures to stderr;
# exit 0 = clean or warnings only, exit 1 = error-severity diagnostics or a failure.
report=$(NO_COLOR=1 just-lsp analyze "$target" 2>&1)
rc=$?

[ -n "$report" ] || exit 0

# additionalContext is capped at 10,000 characters by Claude Code; stay under it.
jq -nc --arg r "$report" --argjson rc "$rc" '
  (if $rc > 1 then "just-lsp analyze failed (exit \($rc)):\n" else "just-lsp analyze:\n" end) as $head
  | ($r | if length > 9000 then .[0:9000] + "\n[report truncated at 9000 characters]" else . end) as $body
  | {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: ($head + $body)}}'
