# just-lsp for Claude Code

Claude Code LSP plugin that runs [`terror/just-lsp`](https://github.com/terror/just-lsp), the language server for [`just`](https://github.com/casey/just). Diagnostics, hover, go-to-definition, references, and document symbols for Just files.

This repository is only the integration layer. It contains no parser and no language server.

## What works where

| File name                            | LSP tool (hover, definition, references, symbols) | Diagnostics after Claude edits the file  |
| ------------------------------------ | ------------------------------------------------- | ---------------------------------------- |
| `*.just`                             | yes, via `.lsp.json`                              | yes, via the language server             |
| `justfile`, `Justfile`, `.justfile`  | **no**                                            | yes, via a PostToolUse hook              |

Claude Code selects an LSP server by the file's extension (`path.extname()`) and rejects any `extensionToLanguage` key that is not at least two characters starting with `.`. There is no filename or glob match, so canonical entrypoints such as `justfile`, `Makefile`, `Dockerfile`, and `Gemfile` cannot reach any plugin's language server. See [docs/claude-code-extensionless-routing.md](docs/claude-code-extensionless-routing.md) for the reproduction and the prior report [anthropics/claude-code#47748](https://github.com/anthropics/claude-code/issues/47748).

For the canonical names this plugin ships `hooks/hooks.json`: after every `Edit` or `Write` whose target basename is `justfile`, `Justfile`, or `.justfile`, it runs `just-lsp analyze <file>` (just-lsp's own diagnostic CLI) and returns the report to Claude as hook context, the same channel native LSP diagnostics use. Nothing is reported for a clean file. The hook is `scripts/just-lsp-analyze.sh`, a POSIX `sh` script; it uses `jq` to read the edited path from the hook input and, when `jq` is absent, falls back to `just-lsp analyze` searching upward from the working directory and reporting through stderr.

The LSP tool still answers `No LSP server available for file type:` for a bare `justfile`. Rename or symlink a copy as `justfile.just` if you need hover or go-to-definition on one.

## Prerequisites

Install the `just-lsp` binary and put it on `PATH`. Claude Code launches it as `just-lsp` with no arguments, which starts the server over stdio.

| Platform     | Command                                                                 |
| ------------ | ----------------------------------------------------------------------- |
| any (cargo)  | `cargo install just-lsp`                                                |
| macOS        | `brew install just-lsp`                                                 |
| Arch         | `pacman -S just-lsp`                                                    |
| Alpine       | `apk add just-lsp`                                                      |
| Nix          | `nix-env -iA nixpkgs.just-lsp`                                          |
| Windows      | download `just-lsp-<version>-x86_64-pc-windows-msvc.zip` from the [releases page](https://github.com/terror/just-lsp/releases), verify against `SHA256SUMS`, copy `just-lsp.exe` into a `PATH` directory such as `%USERPROFILE%\.local\bin` |

Verify:

```sh
just-lsp --version
```

Formatting inside just-lsp shells out to `just --fmt --unstable`, so install [`just`](https://github.com/casey/just#installation) as well.

## Install the plugin

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
just validate    # claude plugin validate . --strict
just analyze     # just-lsp analyze on each fixture, no Claude Code involved
just matrix      # documentSymbol through Claude Code for foo.just, justfile, Justfile
just intel       # hover and goToDefinition through Claude Code on foo.just
just hook-probe  # Claude edits a scratch justfile; the hook must return diagnostics
just check       # all of the above
```

Each probe writes its result and a debug log under `tests/out/`. `LSP: Sent didOpen for ... (languageId: just)` shows an LSP attach. `No LSP server available for file type:` shows a routing miss. `Hook PostToolUse (just-lsp analyze) provided additionalContext` shows the hook delivering a report.

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
