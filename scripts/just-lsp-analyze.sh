#!/bin/sh
# PostToolUse hook. Input: hook JSON on stdin. Analyzes tool_input.file_path
# with `just-lsp analyze` and prints the report as
# hookSpecificOutput.additionalContext, exit 0. Missing jq, missing just-lsp,
# or missing file_path: one line on stderr, exit 2, no analysis.
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

# analyze: diagnostics on stdout, failures on stderr; exit 0 clean or warnings, exit 1 errors or failure.
report=$(NO_COLOR=1 just-lsp analyze "$target" 2>&1)
rc=$?

[ -n "$report" ] || exit 0

# additionalContext cap is 10,000 characters; cut at 9,000.
jq -nc --arg r "$report" --argjson rc "$rc" '
  (if $rc > 1 then "just-lsp analyze failed (exit \($rc)):\n" else "just-lsp analyze:\n" end) as $head
  | ($r | if length > 9000 then .[0:9000] + "\n[report truncated at 9000 characters]" else . end) as $body
  | {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: ($head + $body)}}'
