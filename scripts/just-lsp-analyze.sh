#!/bin/sh
# PostToolUse hook: run `just-lsp analyze` on the justfile Claude just edited and
# hand the report to Claude. Reads the hook JSON on stdin.
#
# With jq: analyzes the exact file and returns the report as additionalContext
# (exit 0), the same channel native LSP diagnostics use.
# Without jq: `just-lsp analyze` searches the working directory and its parents
# for a justfile, and the report goes to stderr with exit 2, which PostToolUse
# shows to Claude.
set -u

input=$(cat)
have_jq=0
target=""
if command -v jq > /dev/null 2>&1; then
  have_jq=1
  target=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
fi

if [ -n "$target" ]; then
  report=$(NO_COLOR=1 just-lsp analyze "$target" 2>&1)
else
  report=$(NO_COLOR=1 just-lsp analyze 2>&1)
fi

[ -n "$report" ] || exit 0

if [ "$have_jq" -eq 1 ]; then
  jq -nc --arg r "$report" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("just-lsp analyze:\n" + $r)}}'
  exit 0
fi

printf 'just-lsp analyze:\n%s\n' "$report" >&2
exit 2
