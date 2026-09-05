set minimum-version := '1.55.0'
set export
set script-interpreter := ['bash', '-euo', 'pipefail']

out_dir := 'tests/out'
probe_model := 'haiku'
probe_budget_usd := '0.50'
# empty = this repository; override to probe an alternate plugin directory
plugin_dir := ''

default:
    @just --list

# Validate plugin.json, marketplace.json, and hooks/hooks.json (warnings are errors); .lsp.json is checked only at runtime
validate:
    claude plugin validate . --strict

# Run just-lsp directly on every fixture, independent of Claude Code
[script]
analyze:
    for f in tests/fixtures/ext/foo.just tests/fixtures/lower/justfile tests/fixtures/upper/Justfile tests/fixtures/dot/.justfile; do
        echo "=== just-lsp analyze $f ==="
        NO_COLOR=1 just-lsp analyze "$f" || echo "rc=$?"
    done

# Exercise the hook script directly: missing jq, missing just-lsp, no path, dirty file, clean file
[script]
hook-unit:
    if command -v cygpath > /dev/null 2>&1; then root="$(cygpath -a -m .)"; else root="$(pwd)"; fi
    lsp_dir="$(dirname "$(command -v just-lsp)")"
    jq_dir="$(dirname "$(command -v jq)")"
    dirty="$root/tests/fixtures/lower/justfile"
    clean="$root/justfile"
    mkin() { jq -nc --arg p "$1" '{tool_input:{file_path:$p}}'; }
    fail() { echo "FAIL: $1" >&2; exit 1; }
    echo "--- no jq on PATH"
    out=$(mkin "$dirty" | PATH="$lsp_dir:/usr/bin:/bin" sh scripts/just-lsp-analyze.sh 2>&1) && fail "expected exit 2 without jq"
    printf '%s\n' "$out" | rg -q 'jq is not on PATH' || fail "missing jq message: $out"
    echo "--- no just-lsp on PATH"
    out=$(mkin "$dirty" | PATH="$jq_dir:/usr/bin:/bin" sh scripts/just-lsp-analyze.sh 2>&1) && fail "expected exit 2 without just-lsp"
    printf '%s\n' "$out" | rg -q 'just-lsp is not on PATH' || fail "missing just-lsp message: $out"
    echo "--- no file_path in input"
    out=$(printf '{}' | sh scripts/just-lsp-analyze.sh 2>&1) && fail "expected exit 2 without file_path"
    printf '%s\n' "$out" | rg -q 'no tool_input.file_path' || fail "missing no-path message: $out"
    echo "--- dirty file -> additionalContext JSON, exit 0"
    out=$(mkin "$dirty" | sh scripts/just-lsp-analyze.sh) || fail "expected exit 0 for dirty file"
    printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | test("missing-dependencies"))' > /dev/null || fail "unexpected JSON: $out"
    echo "--- clean file -> silent, exit 0"
    out=$(mkin "$clean" | sh scripts/just-lsp-analyze.sh) || fail "expected exit 0 for clean file"
    [ -z "$out" ] || fail "expected no output for clean file: $out"
    echo "hook-unit: ok"

# One LSP operation through Claude Code on one fixture; expect 'attach' or 'miss'
[script]
probe name file expect='attach' op='documentSymbol' line='1' character='1':
    mkdir -p "$out_dir"
    if command -v cygpath > /dev/null 2>&1; then root="$(cygpath -a -m .)"; else root="$(pwd)"; fi
    abs="$root/$file"
    log="$root/$out_dir/$name.debug.log"
    result="$out_dir/$name.result.json"
    pd="${plugin_dir:-$root}"
    rm -f "$log" "$result"
    prompt="Call the LSP tool exactly once with operation=$op, filePath=$abs, line=$line, character=$character. Reply with the tool's raw result verbatim and nothing else. If the tool returns an error, reply with the exact error text and nothing else."
    echo "=== probe $name: $abs (plugin: $pd, expect: $expect) ==="
    claude -p \
        --plugin-dir "$pd" \
        --debug-file "$log" \
        --tools LSP \
        --model "$probe_model" \
        --max-budget-usd "$probe_budget_usd" \
        --output-format json \
        --no-session-persistence \
        "$prompt" > "$result"
    echo "--- tool result ---"
    jq -r '.[] | select(.type=="user") | .tool_use_result.result // empty' "$result"
    echo "--- lsp log lines ---"
    rg -n 'Sent didOpen|No LSP server available|Received diagnostics from plugin:just-lsp' "$log" || true
    case "$expect" in
        attach)
            rg -q 'LSP: Sent didOpen for .*\(languageId: just\)' "$log" || { echo "FAIL: no didOpen with languageId just" >&2; exit 1; }
            jq -e '[.[] | select(.type=="user") | .tool_use_result.result // ""] | any(test("^No LSP server available")) | not' "$result" > /dev/null || { echo "FAIL: tool reported no server" >&2; exit 1; }
            ;;
        miss)
            rg -q 'No LSP server available for file type' "$log" || { echo "FAIL: expected a routing miss" >&2; exit 1; }
            ;;
        *) echo "FAIL: expect must be attach or miss" >&2; exit 1 ;;
    esac
    echo "probe $name: $expect confirmed"

# Canonical filename matrix: foo.just attaches; justfile and Justfile miss (Claude Code routes by extension only)
matrix: (probe 'ext' 'tests/fixtures/ext/foo.just' 'attach') (probe 'lower' 'tests/fixtures/lower/justfile' 'miss') (probe 'upper' 'tests/fixtures/upper/Justfile' 'miss')

# Hover and definition on `build` in `test: build` (foo.just line 14, col 7)
intel: (probe 'hover' 'tests/fixtures/ext/foo.just' 'attach' 'hover' '14' '7') (probe 'definition' 'tests/fixtures/ext/foo.just' 'attach' 'goToDefinition' '14' '7')

# Claude edits (tool=Edit) or creates (tool=Write) a scratch copy of a canonical justfile; the hook must deliver a report
[script]
hook-probe name='hook' fixture='tests/fixtures/lower/justfile' basename='justfile' tool='Edit':
    mkdir -p "$out_dir/$name"
    if command -v cygpath > /dev/null 2>&1; then root="$(cygpath -a -m .)"; else root="$(pwd)"; fi
    scratch="$root/$out_dir/$name/$basename"
    src="$root/$fixture"
    log="$root/$out_dir/$name.debug.log"
    result="$out_dir/$name.result.jsonl"
    rm -f "$log" "$result" "$scratch"
    case "$tool" in
        Edit)
            cp "$fixture" "$scratch"
            tools="Read,Edit"
            prompt="Read $scratch, then use the Edit tool exactly once on it: replace the line 'deploy: missing_recipe' with 'deploy: build'. After the edit, reply with the complete text of any hook feedback or tool-result feedback you received, verbatim, and nothing else."
            ;;
        Write)
            tools="Read,Write"
            prompt="Read $src, then use the Write tool exactly once to create $scratch with exactly the same contents. After the write, reply with the complete text of any hook feedback or tool-result feedback you received, verbatim, and nothing else."
            ;;
        *) echo "FAIL: tool must be Edit or Write" >&2; exit 1 ;;
    esac
    echo "=== hook-probe $name: $tool $scratch (plugin: ${plugin_dir:-$root}) ==="
    claude -p \
        --plugin-dir "${plugin_dir:-$root}" \
        --debug-file "$log" \
        --tools "$tools" \
        --permission-mode acceptEdits \
        --model "$probe_model" \
        --max-budget-usd "$probe_budget_usd" \
        --output-format stream-json \
        --include-hook-events \
        --verbose \
        --no-session-persistence \
        "$prompt" > "$result"
    echo "--- hook rule decisions and delivery ---"
    rg -n 'Skipping hook due to if condition|provided additionalContext|Hook PostToolUse:(Edit|Write) \(PostToolUse\) (success|error)' "$log" || true
    rg -q "Hook PostToolUse \(just-lsp analyze\) provided additionalContext" "$log" || { echo "FAIL: hook did not deliver additionalContext" >&2; exit 1; }
    n=$(rg -c 'Hook PostToolUse \(just-lsp analyze\) provided additionalContext' "$log")
    [ "$n" -eq 1 ] || { echo "FAIL: expected exactly one delivery, saw $n" >&2; exit 1; }
    rg -q '^deploy: build|^deploy: missing_recipe' "$scratch" || { echo "FAIL: scratch file unexpected" >&2; exit 1; }
    echo "hook-probe $name: delivered once"

# Every hook rule once: Edit justfile, Justfile, .justfile; Write justfile
hook-matrix: (hook-probe 'hook-lower' 'tests/fixtures/lower/justfile' 'justfile' 'Edit') (hook-probe 'hook-upper' 'tests/fixtures/upper/Justfile' 'Justfile' 'Edit') (hook-probe 'hook-dot' 'tests/fixtures/dot/.justfile' '.justfile' 'Edit') (hook-probe 'hook-write' 'tests/fixtures/lower/justfile' 'justfile' 'Write')

# Everything: schema, direct server, script unit tests, Claude Code matrix, hover/definition, hook matrix
check: validate analyze hook-unit matrix intel hook-matrix
