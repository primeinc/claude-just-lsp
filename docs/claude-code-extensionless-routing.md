# Claude Code LSP routing has no filename or glob match

Claude Code `2.1.261` (binary sha256 `f2f5d1a155167488aeb32cd263e15436253c7b1681ae147c9e73e4d6bbc3c852`), Windows 11, `just-lsp 0.7.1`, Node `v25.9.0` for the `path.extname` table.

## Affected names

`path.extname` per Node v25.9.0 (`node -e 'require("path").extname(n)'`):

| Name                 | `path.extname` | Routable by an `extensionToLanguage` key |
| -------------------- | -------------- | ----------------------------------------- |
| `justfile`           | `""`           | no                                        |
| `Justfile`           | `""`           | no                                        |
| `.justfile`          | `""`           | no                                        |
| `foo.just`           | `.just`        | yes                                       |
| `Makefile`           | `""`           | no                                        |
| `GNUmakefile`        | `""`           | no                                        |
| `Dockerfile`         | `""`           | no                                        |
| `Dockerfile.dev`     | `.dev`         | only by claiming every `.dev` file        |
| `BUILD`, `WORKSPACE` | `""`           | no                                        |
| `Gemfile`, `Rakefile`, `Vagrantfile` | `""` | no                                      |
| `Tiltfile`           | `""`           | no                                        |
| `docker-compose.yml` | `.yml`         | only by claiming every `.yml` file        |
| `CMakeLists.txt`     | `.txt`         | only by claiming every `.txt` file        |

The 2.1.261 binary contains `new Map([["Dockerfile","dockerfile"],["Makefile","makefile"],["Rakefile","ruby"],["Gemfile","ruby"],["CMakeLists","cmake"]])` in the syntax-highlighting grammar selector (adjacent to diff decoration and shebang sniffing code). The LSP router does not read it.

## Reproduction

Plugin directory `p/`:

`p/.claude-plugin/plugin.json`

```json
{ "name": "just-lsp", "lspServers": "./.lsp.json" }
```

`p/.lsp.json`

```json
{ "just": { "command": "just-lsp", "extensionToLanguage": { ".just": "just" } } }
```

Identical fixture files `ext/foo.just` and `lower/justfile`.

```sh
claude -p --plugin-dir ./p --tools LSP --debug-file ext.log \
  "Call the LSP tool exactly once with operation=documentSymbol, filePath=$PWD/ext/foo.just, line=1, character=1. Reply with the raw result."

claude -p --plugin-dir ./p --tools LSP --debug-file lower.log \
  "Call the LSP tool exactly once with operation=documentSymbol, filePath=$PWD/lower/justfile, line=1, character=1. Reply with the raw result."
```

## Result

| File        | Tool result                               | Debug log                                                                                                   |
| ----------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `foo.just`  | 9 document symbols                        | `LSP: Sent didOpen for .../foo.just (languageId: just)`; `Received diagnostics from plugin:just-lsp:just: 3 diagnostic(s)` |
| `justfile`  | `No LSP server available for file type: ` | `No LSP server available for file type  for operation documentSymbol on file .../lower/justfile`            |
| `Justfile`  | same                                      | same                                                                                                        |
| `.justfile` | same                                      | same                                                                                                        |

## Cause

Server selection, binary 2.1.261:

```js
function F(xe){let De=FN.extname(xe).toLowerCase(),Ne=o.get(De);if(!Ne||Ne.length===0)return;...}
```

`languageId` for `didOpen`, same binary:

```js
je=Ne.config.extensionToLanguage[He]||"plaintext"
```

`extensionToLanguage` key schema, same binary:

```js
mc=m(()=>s().min(2).refine((e)=>e.startsWith("."),{message:'File extensions must start with dot (e.g., ".ts", not "ts")'}))
```

The only key `F` could match for an extensionless name is `""`. A plugin declaring `"extensionToLanguage": { "": "just" }` is rejected at session start:

```text
LSP config validation failed for .lsp.json in plugin just-lsp-emptykey-probe: [ { "code": "invalid_key", ... "minimum": 2 ... "File extensions must start with dot" ... } ]
```

Per-server schema fields, complete: `command, args, extensionToLanguage, transport, env, initializationOptions, settings, workspaceFolder, startupTimeout, shutdownTimeout, restartOnCrash, maxRestarts, diagnostics`. The object is closed; an unknown field such as `filenames` is rejected.

`claude plugin validate`, with and without `--strict`, does not read `.lsp.json`. The empty-key plugin passes validation and fails at load.

## Prior report

[anthropics/claude-code#47748](https://github.com/anthropics/claude-code/issues/47748): opened 2026-04-14, labels `enhancement`, `area:lsp`, `stale`; proposes `filenameToLanguage`; lists `Dockerfile`, `Makefile`, `Jenkinsfile`, `Vagrantfile`, `Gemfile`; three comments (one person, two bot); closed `NOT_PLANNED` by github-actions on 2026-06-08; locked; the closing comment asks for a new issue referencing it. Cites #15785 (compound extensions), closed `NOT_PLANNED` 2026-02-14. #32912 (multiple servers per extension) closed `NOT_PLANNED` 2026-05-30. #89472 (project-scoped LSP config) open, 2026-08-25, states a repo-root `.lsp.json` is not discovered.

## Corroboration

- `camjac251/cc-enhanced` @ `6b0be97d4386367c0dc8a1675567d9d51f792387`: `src/patches/lsp-filename-schema.ts` adds `filenames` (basename → languageId) and `filenamePatterns` (glob → languageId) to the per-server schema, taking the key validator from `command` because the extension validator "requires a leading dot; reusing it would reject the extensionless basenames (`Dockerfile`, `Makefile`)". `src/patches/lsp-multi-server.ts` injects `_lspByName` into `getServerForFile` and the `didOpen`/`didChange`/`didSave` paths "when the file extension yields no server, e.g. `Dockerfile` / `Dockerfile.dev`".
- `retif/claudecode-linter` @ `3a9d6f544d6d725aca17ffa764cf99ff2fb51ad4`, `contracts/lsp.schema.json`, extracted from 2.1.261: the same thirteen fields, `additionalProperties: false`.

## Workaround in this plugin

`hooks/hooks.json`: PostToolUse, matcher `Edit|Write`, `if` rules `Edit(//**/[Jj][Uu][Ss][Tt][Ff][Ii][Ll][Ee])`, `Edit(//**/.[Jj][Uu][Ss][Tt][Ff][Ii][Ll][Ee])`, and the same two for `Write`. `//**/` anchors at the filesystem root (permissions reference: `Read(//**/.env)` matches any `.env` anywhere on the filesystem; Windows paths are normalized to `/c/...`). The character classes match every casing; `just` and `just-lsp` compare the justfile name with `eq_ignore_ascii_case`. Each rule fires once per event on Windows; separate `Edit(justfile)` and `Edit(Justfile)` rules fired twice on Windows because file rules match case-insensitively there.

The hook returns `just-lsp analyze <file>` output as `hookSpecificOutput.additionalContext`. It restores diagnostics after edits. The LSP tool operations (hover, definition, references, symbols) remain unavailable for these names.

## Shadow file

A second name with the extension routes. `justfile.just` beside `justfile`, Windows 11 NTFS:

| Shadow   | LSP tool through the shadow      | Claude Code `Edit` on the shadow                                                                                                                   |
| -------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| symlink  | 9 symbols, 3 diagnostics         | refused: `Refusing to write <path>: it is a symbolic link. Write to the link's target path instead.`                                               |
| hardlink | 9 symbols, 3 diagnostics         | write succeeds by temp file plus rename; afterwards `fsutil hardlink list` shows one entry per name; `justfile.just` has the edit, `justfile` does not |

## Missing capability

A filename match in the LSP server config, applied in server selection and in the `languageId` lookup for `didOpen`:

```json
{
  "just": {
    "command": "just-lsp",
    "extensionToLanguage": { ".just": "just" },
    "filenameToLanguage": { "justfile": "just", ".justfile": "just" }
  }
}
```

matched case-insensitively against `path.basename()`, plus a glob form for `Dockerfile.*`. The `didOpen` path already falls back to `"plaintext"` for an unmapped extension; the change adds one key space to the selection map and the `languageId` lookup.
