# just-lsp for Claude Code

Claude Code LSP plugin that runs [`terror/just-lsp`](https://github.com/terror/just-lsp), the language server for [`just`](https://github.com/casey/just). Diagnostics, hover, go-to-definition, references, and document symbols for Just files.

This repository is only the integration layer. It contains no parser and no language server.

## What works where

| File name                                        | LSP tool (hover, definition, symbols)  | Diagnostics after Claude edits the file                                                                 |
| ------------------------------------------------ | -------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `*.just`                                         | yes, via `.lsp.json` (probed)          | the server publishes them on every edit (probed); Claude Code's injection into context is its documented behaviour, not observed by this harness |
| `justfile`, `Justfile`, `.justfile`, any casing  | **no**                                 | yes, via a PostToolUse hook (probed)                                                                    |

Claude Code selects an LSP server by the file's extension (`path.extname()`) and rejects any `extensionToLanguage` key that is not at least two characters starting with `.`. There is no filename or glob match, so canonical entrypoints such as `justfile`, `Makefile`, `Dockerfile`, and `Gemfile` cannot reach any plugin's language server. See [docs/claude-code-extensionless-routing.md](docs/claude-code-extensionless-routing.md) for the reproduction and the prior report [anthropics/claude-code#47748](https://github.com/anthropics/claude-code/issues/47748).

For the canonical names this plugin ships `hooks/hooks.json`: after every `Edit` or `Write` whose target basename is `justfile` or `.justfile` in any letter case, anywhere on the filesystem, it runs `just-lsp analyze <file>` (just-lsp's own diagnostic CLI) on that file and returns the report to Claude as hook context, the same channel native LSP diagnostics use. Nothing is reported for a clean file. Reports longer than 9,000 characters are cut with a marker, under Claude Code's 10,000-character cap. The hook is `scripts/just-lsp-analyze.sh`, a POSIX `sh` script that needs `jq` to read the edited path from the hook input. When `jq` or `just-lsp` is missing, the hook reports that one fact to Claude and analyzes nothing.

The LSP tool still answers `No LSP server available for file type:` for a bare `justfile`. For hover or go-to-definition on one, a **symlink** `justfile.just -> justfile` works as a read-only shadow: the LSP tool routes through it, and Claude Code refuses to write through a symlink (`Refusing to write ...: it is a symbolic link`), so edits keep going to `justfile` where the hook reports. Do not use a **hardlink**: Claude Code writes by temp file and rename, which splits the pair and leaves `justfile` stale without any error.

## Prerequisites

Install the `just-lsp` binary and put it on `PATH`. Claude Code launches it as `just-lsp` with no arguments, which starts the server over stdio.

| Platform     | Command                                                                 |
| ------------ | ----------------------------------------------------------------------- |
| any (cargo)  | `cargo install just-lsp`                                                |
| macOS        | `brew install just-lsp`                                                 |
| Arch         | `pacman -S just-lsp`                                                    |
| Alpine       | `apk add just-lsp`                                                      |
| Void         | `xbps-install -S just-lsp`                                              |
| Nix          | `nix-env -iA nixpkgs.just-lsp`                                          |
| Windows      | download `just-lsp-<version>-x86_64-pc-windows-msvc.zip` (or `aarch64-pc-windows-msvc`) from the [releases page](https://github.com/terror/just-lsp/releases), verify against `SHA256SUMS`, copy `just-lsp.exe` into a `PATH` directory such as `%USERPROFILE%\.local\bin` |

The hook also needs `jq` on `PATH`.

Verify:

```sh
just-lsp --version
```

Formatting inside just-lsp shells out to `just --fmt --unstable`, so install [`just`](https://github.com/casey/just#installation) as well.

## Install the plugin

The repository must be readable by the installing account.

```text
/plugin marketplace add primeinc/claude-just-lsp
/plugin install just-lsp@claude-just-lsp
```

For local development:

```sh
claude --plugin-dir /path/to/claude-just-lsp
```

## Configuration

`.lsp.json`:

```json
{
  "just": {
    "command": "just-lsp",
    "extensionToLanguage": {
      ".just": "just"
    }
  }
}
```

just-lsp reads `initializationOptions` for formatting indentation and per-rule severities. None are set here. To change them, add an `initializationOptions` object to the `just` entry; the schema is in the [just-lsp README](https://github.com/terror/just-lsp#configuration).

## Verify

Requires `just`, `just-lsp`, `claude`, `bash`, `jq`, and `rg` on `PATH`. Probes call the Claude API on the `haiku` model with a budget cap per probe.

```sh
just validate     # claude plugin validate . --strict (plugin.json, marketplace.json, hooks.json)
just analyze      # just-lsp analyze on each fixture, no Claude Code involved
just hook-unit    # the hook script alone: missing jq, missing just-lsp, no path, dirty file, clean file
just matrix       # documentSymbol through Claude Code: foo.just must attach, justfile and Justfile must miss
just intel        # hover and goToDefinition through Claude Code on foo.just must attach
just hook-matrix  # Claude edits justfile, Justfile, .justfile and writes a justfile; each must deliver a report
just check        # all of the above
```

Every recipe exits non-zero when its expectation fails. Each probe leaves its result and debug log under `tests/out/`; the assertions read `LSP: Sent didOpen for ... (languageId: just)`, `No LSP server available for file type`, and `Hook PostToolUse (just-lsp analyze) provided additionalContext` from that log.

## Known runtime message

At session end Claude Code sends `shutdown` with `params: {}`. tower-lsp, which just-lsp is built on, answers `-32602 Unexpected params: {}`, and Claude Code logs `Failed to stop LSP server`. The server still exits. Visible only in `--debug` output.

## Provenance

| Artifact                               | Revision                                   |
| -------------------------------------- | ------------------------------------------ |
| terror/just-lsp                        | tag `0.7.1`, `52d7d338480258002ba20c941d09cb4dfdc3a2c8` |
| anthropics/claude-plugins-official     | `85cce0381e7860082641b59d961a2b8c368b8b79` |
| tylerlaprade/basedpyright-lsp          | `551c135dc8898b33690b88b9040cd30b8b0d374b` |
| michael-denyer/pyrefly-lsp-cc-plugin   | `fb573147afecbfded18c74d0a881f611c213cd73` |
| Claude Code                            | `2.1.261`                                  |

## License

MIT. just-lsp itself is CC0-1.0.
