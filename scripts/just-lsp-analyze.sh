#!/bin/sh
# PostToolUse hook. Input: hook JSON on stdin. Analyzes tool_input.file_path
# with `just-lsp analyze` and, on Windows, `justlint` (claude-hooks-mk2
# cmd/justlint: interpreters that reach System32's WSL bash or need cygpath
# outside Git Bash). Prints the reports as hookSpecificOutput.additionalContext,
# exit 0. A missing justlint on Windows is a "justlint not run" section, not an
# error: it is optional. Missing jq, just-lsp, or file_path: one line on
# stderr, exit 2, no analysis.
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

# justlint judges how Windows resolves interpreters, so it runs only there.
# Exit 0 clean, 1 findings, 2 the file could not be checked.
lint=""
lint_head=""
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    if command -v justlint > /dev/null 2>&1; then
      lint=$(justlint "$target" 2>&1)
      case $? in
        0) ;;
        1) lint_head="justlint:" ;;
        *) lint_head="justlint could not check the file:" ;;
      esac
    else
      lint_head="justlint not run:"
      lint="justlint is not on PATH, so Windows interpreter resolution was not checked. It is cmd/justlint in primeinc/claude-hooks-mk2 and is not published yet."
    fi
    ;;
esac

[ -n "$report" ] || [ -n "$lint_head" ] || exit 0

# additionalContext cap is 10,000 characters; cut at 9,000.
jq -nc --arg r "$report" --argjson rc "$rc" --arg lh "$lint_head" --arg l "$lint" '
  (if $r == "" then "" elif $rc > 1 then "just-lsp analyze failed (exit \($rc)):\n" + $r else "just-lsp analyze:\n" + $r end) as $a
  | (if $lh == "" then "" else $lh + "\n" + $l end) as $b
  | ([$a, $b] | map(select(. != "")) | join("\n\n")) as $all
  | ($all | if length > 9000 then .[0:9000] + "\n[report truncated at 9000 characters]" else . end) as $body
  | {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $body}}'
