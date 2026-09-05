# Claude Code LSP routing has no filename or glob match

Claude Code `2.1.261` (sha256 `f2f5d1a155167488aeb32cd263e15436253c7b1681ae147c9e73e4d6bbc3c852`), Windows 11, `just-lsp 0.7.1`.

## The gap

Plugin LSP servers are selected by file extension only. Languages whose canonical entrypoint is a file name, not an extension, cannot be routed:

| Ecosystem | Canonical names                          | Extension form that does route |
| --------- | ---------------------------------------- | ------------------------------ |
| Just      | `justfile`, `Justfile`, `.justfile`      | `*.just`                       |
| Make      | `Makefile`, `GNUmakefile`                | `*.mk`                         |
| Docker    | `Dockerfile`, `Dockerfile.*`             | `*.dockerfile`                 |
| Bazel     | `BUILD`, `WORKSPACE`                     | `*.bzl`                        |
| Ruby      | `Gemfile`, `Rakefile`, `Vagrantfile`     | `*.rb`                         |
| Starlark  | `Tiltfile`                               | `*.star`                       |

Editors resolve these with filename and glob rules next to extension rules. Claude Code's own syntax highlighter does the same: the binary carries `new Map([["Dockerfile","dockerfile"],["Makefile","makefile"],["Rakefile","ruby"],["Gemfile","ruby"],["CMakeLists","cmake"]])` for grammar selection. The LSP router never consults a filename.

## Reproduce

Plugin directory `p/` with two files.

`p/.claude-plugin/plugin.json`

```json
{ "name": "just-lsp", "lspServers": "./.lsp.json" }
```

`p/.lsp.json`

```json
{ "just": { "command": "just-lsp", "extensionToLanguage": { ".just": "just" } } }
```

Two identical fixture files: `ext/foo.just` and `lower/justfile`.

```sh
claude -p --plugin-dir ./p --tools LSP --debug-file ext.log \
  "Call the LSP tool exactly once with operation=documentSymbol, filePath=$PWD/ext/foo.just, line=1, character=1. Reply with the raw result."

claude -p --plugin-dir ./p --tools LSP --debug-file lower.log \
  "Call the LSP tool exactly once with operation=documentSymbol, filePath=$PWD/lower/justfile, line=1, character=1. Reply with the raw result."
```

## Observed

`foo.just`: nine document symbols. `ext.log` contains `LSP: Sent didOpen for .../foo.just (languageId: just)` and `Received diagnostics from plugin:just-lsp:just: 3 diagnostic(s)`.

`justfile`: tool result `No LSP server available for file type: ` (empty type). `lower.log` line: `No LSP server available for file type  for operation documentSymbol on file .../lower/justfile`. Same for `Justfile`.

## Cause

Server selection in the 2.1.261 binary:

```js
function F(xe){let De=FN.extname(xe).toLowerCase(),Ne=o.get(De);if(!Ne||Ne.length===0)return;...}
```

`path.extname("justfile")` is `""`, as it is for `Makefile`, `Dockerfile`, `Gemfile`, and `.justfile`. The only map key that could match is `""`, and the `extensionToLanguage` key schema forbids it:

```js
mc=m(()=>s().min(2).refine((e)=>e.startsWith("."),{message:'File extensions must start with dot (e.g., ".ts", not "ts")'}))
```

A plugin declaring `"extensionToLanguage": { "": "just" }` is rejected at load:

```text
LSP config validation failed for .lsp.json in plugin just-lsp-emptykey-probe: [ { "code": "invalid_key", ... "minimum": 2 ... "File extensions must start with dot" ... } ]
```

The per-server schema is closed (`additionalProperties: false`). Its complete field list is `command, args, extensionToLanguage, transport, env, initializationOptions, settings, workspaceFolder, startupTimeout, shutdownTimeout, restartOnCrash, maxRestarts, diagnostics`. No filename or pattern field exists, so an editor-style `filenames` key is rejected as unknown rather than ignored.

`claude plugin validate`, with or without `--strict`, passes a plugin whose `.lsp.json` the runtime rejects. The validator does not read `.lsp.json`.

## Prior report

[anthropics/claude-code#47748](https://github.com/anthropics/claude-code/issues/47748) (opened 2026-04-14, labels `enhancement`, `area:lsp`) proposed `filenameToLanguage` with `Dockerfile`, `Makefile`, `Jenkinsfile`, `Vagrantfile`, `Gemfile` as the affected set and Docker language servers as the use case. It received one comment, was closed `NOT_PLANNED` by the stale bot on 2026-06-08, and is locked. The bot asks for a new issue referencing it. It cites #15785 (compound extensions such as `docker-compose.yml`) as closed the same way. #32912 (multiple servers per extension) closed `NOT_PLANNED` on 2026-05-30.

## Corroboration

- `camjac251/cc-enhanced` @ `6b0be97d4386367c0dc8a1675567d9d51f792387` patches the bundle to add exactly this: `src/patches/lsp-filename-schema.ts` widens the per-server schema with `filenames` (basename → languageId) and `filenamePatterns` (glob → languageId), taking the key validator from `command` because the extension validator "requires a leading dot; reusing it would reject the extensionless basenames (`Dockerfile`, `Makefile`)". `src/patches/lsp-multi-server.ts` injects a `_lspByName` fallback into `getServerForFile` and the didOpen/didChange/didSave paths "when the file extension yields no server, e.g. `Dockerfile` / `Dockerfile.dev`".
- `retif/claudecode-linter` @ `3a9d6f544d6d725aca17ffa764cf99ff2fb51ad4`, `contracts/lsp.schema.json`, extracted from 2.1.261 the same day, lists the same thirteen fields with `additionalProperties: false`.

## Workaround in this plugin

`hooks/hooks.json` runs `just-lsp analyze` from a `PostToolUse` hook with `if` rules `Edit([Jj]ustfile)`, `Edit(.justfile)`, `Write([Jj]ustfile)`, `Write(.justfile)`, and returns the report as `hookSpecificOutput.additionalContext`. That restores diagnostics after edits for the canonical names. It cannot restore the LSP tool: hover, definition, references, and symbols on a bare `justfile` still fail at server selection. On Windows, `if` file rules match case-insensitively, so `Edit(justfile)` and `Edit(Justfile)` as separate rules fire twice; the character class fires once.

## Shadow-file experiments

A second name with the extension routes, so a shadow `justfile.just` beside `justfile` was tried both ways on Windows 11, NTFS.

| Shadow type | LSP tool through the shadow | Claude Code `Edit` on the shadow                                                      |
| ----------- | --------------------------- | ------------------------------------------------------------------------------------- |
| symlink     | works (9 symbols, 3 diagnostics) | refused: `Refusing to write <path>: it is a symbolic link. Write to the link's target path instead.` |
| hardlink    | works                       | succeeds, but the write is temp-file plus rename: the shadow becomes a new file with the edit and `justfile` keeps the old content. `fsutil hardlink list` shows one entry each afterwards. |

A symlink is therefore a safe read-only shadow. A hardlink silently forks the file. Neither makes `justfile` itself routable, and the plugin does not create either.

## Missing capability

A filename match in the LSP server config, alongside `extensionToLanguage`, applied in server selection and in the `languageId` chosen for `didOpen`:

```json
{
  "just": {
    "command": "just-lsp",
    "extensionToLanguage": { ".just": "just" },
    "filenameToLanguage": { "justfile": "just", ".justfile": "just" }
  }
}
```

matched case-insensitively against `path.basename()`, with an optional glob form for `Dockerfile.*`. The `didOpen` path already falls back to `"plaintext"` for an unmapped extension, so only the selection map and the `languageId` lookup gain a second key space.
