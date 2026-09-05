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

# Validate plugin manifest and .lsp.json schema (warnings are errors)
validate:
    claude plugin validate . --strict

# Run just-lsp directly on every fixture, independent of Claude Code
[script]
analyze:
    for f in tests/fixtures/ext/foo.just tests/fixtures/lower/justfile tests/fixtures/upper/Justfile; do
        echo "=== just-lsp analyze $f ==="
        NO_COLOR=1 just-lsp analyze "$f" || echo "rc=$?"
    done

# Ask Claude Code (with this plugin loaded) for one LSP operation on one fixture
[script]
probe name file op='documentSymbol' line='1' character='1':
    mkdir -p "$out_dir"
    if command -v cygpath > /dev/null 2>&1; then root="$(cygpath -a -m .)"; else root="$(pwd)"; fi
    abs="$root/$file"
    log="$root/$out_dir/$name.debug.log"
    result="$out_dir/$name.result.json"
    pd="${plugin_dir:-$root}"
    rm -f "$log" "$result"
    prompt="Call the LSP tool exactly once with operation=$op, filePath=$abs, line=$line, character=$character. Reply with the tool's raw result verbatim and nothing else. If the tool returns an error, reply with the exact error text and nothing else."
    echo "=== probe $name: $abs (plugin: $pd) ==="
    claude -p \
        --plugin-dir "$pd" \
        --debug-file "$log" \
        --tools LSP \
        --model "$probe_model" \
        --max-budget-usd "$probe_budget_usd" \
        --output-format json \
        --no-session-persistence \
        "$prompt" > "$result" || echo "claude rc=$?"
    echo "--- result ($result) ---"
    cat "$result"
    echo
    echo "--- debug log lines mentioning lsp/plugin ($log) ---"
    rg -n -i 'lsp|plugin' "$log" || echo "rg rc=$? (no lsp/plugin lines)"

# Full canonical filename matrix: foo.just, justfile, Justfile
matrix: (probe 'ext' 'tests/fixtures/ext/foo.just') (probe 'lower' 'tests/fixtures/lower/justfile') (probe 'upper' 'tests/fixtures/upper/Justfile')

# Hover and definition on `build` in `test: build` (foo.just line 14, col 7)
intel: (probe 'hover' 'tests/fixtures/ext/foo.just' 'hover' '14' '7') (probe 'definition' 'tests/fixtures/ext/foo.just' 'goToDefinition' '14' '7')

# Edit a scratch copy of a canonical justfile through Claude Code; the PostToolUse hook must report diagnostics
[script]
hook-probe name='hook' fixture='tests/fixtures/lower/justfile' basename='justfile':
    mkdir -p "$out_dir/$name"
    if command -v cygpath > /dev/null 2>&1; then root="$(cygpath -a -m .)"; else root="$(pwd)"; fi
    scratch="$root/$out_dir/$name/$basename"
    log="$root/$out_dir/$name.debug.log"
    result="$out_dir/$name.result.jsonl"
    cp "$fixture" "$scratch"
    rm -f "$log" "$result"
    prompt="Read $scratch, then use the Edit tool exactly once on it: replace the line 'deploy: missing_recipe' with 'deploy: build'. After the edit, reply with the complete text of any hook feedback or tool-result feedback you received, verbatim, and nothing else."
    echo "=== hook-probe $name: $scratch ==="
    claude -p \
        --plugin-dir "${plugin_dir:-$root}" \
        --debug-file "$log" \
        --tools Read,Edit \
        --permission-mode acceptEdits \
        --model "$probe_model" \
        --max-budget-usd "$probe_budget_usd" \
        --output-format stream-json \
        --include-hook-events \
        --verbose \
        --no-session-persistence \
        "$prompt" > "$result" || echo "claude rc=$?"
    echo "--- hook events and tool results ($result) ---"
    rg -n '"type":"hook_|"type":"user"|"type":"result"' "$result" || echo "rg rc=$? (no hook/result lines)"
    echo "--- debug log lines mentioning hook ($log) ---"
    rg -n -i 'hook' "$log" || echo "rg rc=$? (no hook lines)"
    echo "--- scratch file after edit ---"
    cat "$scratch"

# Everything: schema, direct server, Claude Code matrix, hover/definition, hook
check: validate analyze matrix intel hook-probe
