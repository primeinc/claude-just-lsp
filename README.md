# just-lsp for Claude Code

Claude Code plugin `just-lsp`. Runs [terror/just-lsp](https://github.com/terror/just-lsp) as an LSP server for `*.just` files and runs `just-lsp analyze` after edits to `justfile`, `Justfile`, `.justfile`. Contains no parser and no language server.

## Coverage

Measured on Claude Code 2.1.261, just-lsp 0.7.1, Windows 11. Each cell names the recipe that proves it.

| File name                                  | LSP tool: symbols, hover, definition, references | Diagnostics after Claude edits or writes the file            |
| ------------------------------------------ | ------------------------------------------------ | ------------------------------------------------------------ |
| `*.just`                                   | yes (`just matrix`, `just intel`)                | yes, from the language server (`just diag-probe`)            |
| `justfile`, `Justfile`, `.justfile`, any case | no (`just matrix`)                            | yes, from a PostToolUse hook running `just-lsp analyze` (`just hook-matrix`) |

Cause of the `no`: Claude Code selects an LSP server by `path.extname(file)`; `extensionToLanguage` keys must be at least two characters starting with `.`; no filename or glob field exists. `path.extname("justfile")` is `""`. Details, binary evidence, and the prior upstream report: [docs/claude-code-extensionless-routing.md](docs/claude-code-extensionless-routing.md).

## Prerequisites

| Binary     | Purpose                                              | Install                                                                                                                                                                                    |
| ---------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `just-lsp` | language server and `analyze` CLI                    | `cargo install just-lsp`; `brew install just-lsp`; `pacman -S just-lsp`; `apk add just-lsp`; `xbps-install -S just-lsp`; `nix-env -iA nixpkgs.just-lsp`; Windows: `just-lsp-<version>-x86_64-pc-windows-msvc.zip` or `-aarch64-pc-windows-msvc.zip` from [releases](https://github.com/terror/just-lsp/releases), verify against `SHA256SUMS`, place `just-lsp.exe` on `PATH` |
| `just`     | `just-lsp` formats through `just --fmt --unstable`   | [casey/just installation](https://github.com/casey/just#installation)                                                                                                                      |
| `jq`       | the hook reads the edited path from hook JSON        | [jqlang.org](https://jqlang.org)                                                                                                                                                           |
| Git Bash   | Windows only: Claude Code runs shell-form hooks in it | ships with Git for Windows                                                                                                                                                                 |

Check: `just-lsp --version`, `jq --version`.

## Install

```text
/plugin marketplace add primeinc/claude-just-lsp
/plugin install just-lsp@claude-just-lsp
```

Local checkout for one session: `claude --plugin-dir /path/to/claude-just-lsp`.

## Files

| Path                          | Content                                                                                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.claude-plugin/plugin.json`  | manifest; `"lspServers": "./.lsp.json"`                                                                                                                      |
| `.claude-plugin/marketplace.json` | marketplace `claude-just-lsp` with one plugin, source `./`                                                                                               |
| `.lsp.json`                   | server `just`: `command: just-lsp`, `extensionToLanguage: {".just": "just"}`                                                                                 |
| `hooks/hooks.json`            | PostToolUse, matcher `Edit\|Write`, four `if` rules: `Edit`/`Write` × `//**/[Jj][Uu][Ss][Tt][Ff][Ii][Ll][Ee]` and `//**/.[Jj][Uu][Ss][Tt][Ff][Ii][Ll][Ee]` |
| `scripts/just-lsp-analyze.sh` | POSIX sh hook body                                                                                                                                           |
| `justfile`                    | verification recipes                                                                                                                                         |
| `tests/fixtures/`             | one 26-line Just file under four names: `ext/foo.just`, `lower/justfile`, `upper/Justfile`, `dot/.justfile`; each yields 1 warning and 2 errors from `just-lsp analyze` |
| `docs/`                       | routing analysis and upstream reproduction                                                                                                                   |

## Hook behaviour

Trigger: `Edit` or `Write` whose target basename is `justfile` or `.justfile` in any letter case, at any path (`//**/` anchors at the filesystem root; Windows paths are normalized to `/c/...` before matching). On Windows the rule also matches case-insensitively by platform; one rule per tool and name form fires once per event.

Script, in order:

1. `jq` missing: stderr `just-lsp hook: jq is not on PATH, so the edited file was not analyzed. Install jq: https://jqlang.org`, exit 2.
2. `just-lsp` missing: stderr `just-lsp hook: just-lsp is not on PATH, so the edited file was not analyzed. Install: cargo install just-lsp (...)`, exit 2.
3. `tool_input.file_path` absent: stderr `just-lsp hook: hook input carried no tool_input.file_path, so nothing was analyzed.`, exit 2.
4. `NO_COLOR=1 just-lsp analyze <file_path> 2>&1`. Empty output: exit 0, no message.
5. Non-empty output: stdout `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"just-lsp analyze:\n<report>"}}`, exit 0. Report longer than 9,000 characters is cut at 9,000 with the line `[report truncated at 9000 characters]`. `just-lsp` exit code above 1 changes the header to `just-lsp analyze failed (exit N):`.

Exit 2 on PostToolUse shows stderr to Claude and renders a hook error notice to the user. Exit 0 with `additionalContext` inserts the text next to the tool result, the channel native LSP diagnostics use. No other file is ever analyzed in place of the edited one.

Shell form is used deliberately: Claude Code runs shell-form hooks in Git Bash on Windows; exec form would need `sh` on the Windows `PATH`, and `bash` on the Windows `PATH` resolves to `System32\bash.exe` (WSL) on a default install.

## Shadow file for hover and definition on a bare `justfile`

| Shadow `justfile.just` beside `justfile` | LSP tool through the shadow                       | Claude Code `Edit` on the shadow                                                                                     |
| ---------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| symlink                                  | works                                             | refused: `Refusing to write <path>: it is a symbolic link. Write to the link's target path instead.`                 |
| hardlink                                 | works                                             | succeeds by temp file plus rename; the pair splits; `justfile` keeps the old content with no error. Do not use.      |

The plugin creates neither. Measured on Windows 11 NTFS; `tests/out/link-sym.debug.log`, `tests/out/link-hard`.

## Verify

Requires `just`, `just-lsp`, `jq`, `rg`, `bash`, `claude` on `PATH`. Recipes marked API call the Claude API on model `haiku` with a `$0.50` cap per invocation. Every recipe exits non-zero when its assertion fails.

| Recipe             | API calls | Asserts                                                                                                                   |
| ------------------ | --------- | ------------------------------------------------------------------------------------------------------------------------- |
| `just validate`    | 0         | `claude plugin validate . --strict` passes (plugin.json, marketplace.json, hooks.json; `.lsp.json` is not validated by this command) |
| `just analyze`     | 0         | prints `just-lsp analyze` output for the four fixtures                                                                   |
| `just hook-unit`   | 0         | script: exit 2 and message without `jq`; without `just-lsp`; without `file_path`; JSON with `missing-dependencies` for a dirty file; silence for a clean file |
| `just matrix`      | 4         | `foo.just`: `LSP: Sent didOpen ... (languageId: just)`; `justfile`, `Justfile`, `.justfile`: `No LSP server available for file type` |
| `just intel`       | 3         | `hover`, `goToDefinition`, `findReferences` on `build` at foo.just 14:7 attach                                            |
| `just hook-matrix` | 4         | `Edit` on `justfile`, `Justfile`, `.justfile` and `Write` on `justfile`: exactly one `Hook PostToolUse (just-lsp analyze) provided additionalContext` |
| `just diag-probe`  | 2 turns   | after an `Edit` of a scratch `foo.just`, log line `LSP Diagnostics: Delivering` and the second turn quotes the diagnostics |
| `just check`       | 13        | all of the above                                                                                                          |

`diag-probe` runs with Claude Code's default tool set. A session started with `--tools` restricted to `Read,Edit` never builds LSP diagnostic attachments (`getLSPDiagnosticAttachments` returns before reading the registry); diagnostics are still received and registered but not delivered.

Outputs: `tests/out/<name>.result.json|jsonl` and `tests/out/<name>.debug.log`, gitignored.

## Runtime message at session end

Claude Code sends `shutdown` with `params: {}`. tower-lsp 0.20 (just-lsp's server framework) answers `-32602 Unexpected params: {}`; Claude Code logs `Failed to stop LSP server` at error level. The server process exits. Visible in `--debug` output only.

## Provenance

| Artifact                             | Revision                                                                 |
| ------------------------------------ | ------------------------------------------------------------------------ |
| terror/just-lsp                      | tag `0.7.1`, `52d7d338480258002ba20c941d09cb4dfdc3a2c8`                  |
| Claude Code                          | `2.1.261`, binary sha256 `f2f5d1a155167488aeb32cd263e15436253c7b1681ae147c9e73e4d6bbc3c852` |
| anthropics/claude-plugins-official   | `85cce0381e7860082641b59d961a2b8c368b8b79`                               |
| tylerlaprade/basedpyright-lsp        | `551c135dc8898b33690b88b9040cd30b8b0d374b`                               |
| michael-denyer/pyrefly-lsp-cc-plugin | `fb573147afecbfded18c74d0a881f611c213cd73`                               |
| Claude Code docs                     | code.claude.com/docs/en/{plugins-reference,plugins,plugin-marketplaces,hooks,permissions}.md fetched 2026-09-05 |

## License

MIT for this repository. just-lsp is CC0-1.0; none of its code is included here.
