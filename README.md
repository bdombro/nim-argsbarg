# argsbarg

Describe your CLI as plain Nim objects. `argsbarg` handles the rest: parsing, validation,
scoped help, ANSI styling, and zsh tab completion. One schema in, less yak shaving out.

## Quick start

If you want the elevator pitch: define commands and options as normal Nim values, call
`cliRun`, and go back to building your actual tool.

```bash
nimble install argsbarg
```

```nim
import std/[os, options]
import argsbarg

proc greet(ctx: CliContext) =
  let n = ctx.optString("name")
  let who = if n.isSome: n.get else: "world"
  echo styleGreen("hello"), " ", who

let schema = CliSchema(
  commands: @[
    cliLeaf(
      "hello",
      "Say hello.",
      greet,
      options = @[
        cliOptString("name", "Who to greet.", 'n'),
        cliOptFlag("verbose", "Enable extra logging.", 'v'),
      ],
    ),
  ],
  description: "Tiny demo.",
  name: "helloapp",
)

when isMainModule:
  cliRun(schema, commandLineParams())
```

Every app gets two built-ins injected by `cliRun` for free:

- `-h` / `--help` at any routing depth, scoped to the current node.
- `completion zsh` / `completion bash` print a completion script to stdout (zsh: see also
  `--print` / install flow in the shell completions section below).

So yes, `completion` is already spoken for. Don't reuse that as a top-level command unless
you enjoy arguing with validation errors.


### Hacking on this repo

Use [`just`](https://github.com/casey/just) for the usual build/test loop:

```bash
just build
just test
```

If you want to compile the examples against the working tree directly:

```bash
nim c -p:src examples/nim_file.nim
nim c -p:src examples/nim_minimal.nim
```

`nimble test` also works, but Nimble gets weird until the repo has at least one Git commit
because it wants a VCS revision. If it starts pouting, use `just test` or make an initial commit.

## How it works

The whole idea is pretty simple:

- **Define a schema** with `CliSchema`, `CliCommand`, `CliOption`, and the `cliLeaf` / `cliGroup` /
  `cliOpt*` helpers. On Nim 2+, empty seqs and common booleans default sanely, so you usually only
  write the interesting parts.
- **Call `cliRun(schema, argv)`** and let it validate the schema, parse argv, render help or
  errors, wire in the built-ins, and dispatch the right leaf handler.
- **Call `cliParse(schema, argv)`** if you want the raw `CliParseResult` for tests or custom
  dispatch. If you want built-ins included there too, pass a merged schema via
  `cliMergeBuiltins`.

### Commands: leaves vs. routing nodes

A **leaf** is built with `cliLeaf` and must include a `CliHandler`. It does not declare child
subcommands (the backing node keeps an empty `commands` sequence).

A **routing node** is built with `cliGroup`, which requires a non-optional `commands` sequence.
argsbarg shows contextual help if the user stops on that node instead of choosing a subcommand.

### Options and positionals

- Long options: `--name` or `--name value` or `--name=value`.
- Short aliases: pass a `char` as the last argument to `cliOptFlag` / `cliOptString` /
  `cliOptNumber` (or omit it for long-only flags). Valued shorts use `-n value`; boolean shorts
  can be bundled (`-abc` sets all three when every flag in the bundle is presence-only).
- Positionals: `cliOptPositional` (and `isRepeated = true` for a tail that collects every remaining
  word), attached to leaf commands via `arguments`.

### Reading values in a handler

Inside your handler, you read parsed values from `CliContext`:

```nim
ctx.optFlag("verbose")   # bool  — was the flag passed?
ctx.optNumber("count")   # Option[float]
ctx.optString("name")    # Option[string]
```


### Root command fallback (`fallbackCommand` / `fallbackMode`)

Many CLIs spell the real work as a subcommand (`compress`, `run`, `read`, …). Users often skip
that word and start with flags or paths (`tool -q 2 a.pdf`). Root fallback lets you describe that
behavior in the schema instead of maintaining a separate argv preprocessor.

You set two optional fields on **`CliSchema`**:

- **`fallbackCommand`**: a `some("name")` top-level command. The name must match a direct child of
  `commands` (after `cliMergeBuiltins`, built-ins such as `completion` count as siblings).
- **`fallbackMode`**: when that fallback is allowed to run. Three choices below.

Only the **app root** uses this. Nested `cliGroup` nodes do not auto-pick a child when argv stops
halfway down the tree.

If you leave **`fallbackCommand` unset**, nothing special happens: empty argv still shows root
help (unless the user passes `-h` / `--help`). The modes **`cliFallbackWhenMissingOrUnknown`** and
**`cliFallbackWhenUnknown`** require **`fallbackCommand`** to be set, or `cliSchemaValidate` raises.

The examples below assume a toy app with top-level commands **`compress`** (the main job),
**`list`**, plus the usual **`completion`** (with subcommand `zsh`), and
**`fallbackCommand: some("compress")`**.

#### `cliFallbackWhenMissing` (default)

Use the fallback **only** when there is no top-level command word left after root options. If the
user types another real command, that command wins.

```bash
mytool                         # → runs compress (argv was “empty” at the command slot)
mytool compress doc.pdf        # → runs compress
mytool list                    # → runs list
mytool -q 2 doc.pdf            # → error unless -q is a declared *root* option
```

Pick this when **`mytool` alone should run the main subcommand** and you still want unknown first
words to be errors (typos surface as “unknown command”).

#### `cliFallbackWhenMissingOrUnknown`

Same as **`cliFallbackWhenMissing`** for an empty command slot, **and**: if the next token is not a
known top-level command, behave as if **`compress`** were written first. Declared root options are
still parsed first; other leading flags can belong to **`compress`**. Real command names
(including **`completion bash`** / **`completion zsh`**) still beat the fallback.

```bash
mytool                         # → runs compress
mytool -q 2 doc.pdf            # → runs compress with -q and doc.pdf (typical single-action CLI)
mytool doc.pdf                 # → runs compress; doc.pdf is a positional for compress
mytool list                    # → runs list
mytool completion bash       # → built-in, not compress
mytool completion zsh        # → built-in, not compress
```

Pick this for **verb-optional** single-action tools (`pdf-compress`-style).

#### `cliFallbackWhenUnknown`

Like **`cliFallbackWhenMissingOrUnknown`** for the **non-empty** case, but **never** auto-select the
fallback when the command slot is completely empty: **`mytool` alone prints root overview help**.
As soon as there is at least one token that is not a known top-level command, routing matches
**`cliFallbackWhenMissingOrUnknown`**.

```bash
mytool                         # → root help (lists compress, list, completion bash|zsh, …)
mytool doc.pdf                 # → runs compress on doc.pdf
mytool -q 2 doc.pdf            # → runs compress with flags and file
mytool list                    # → runs list
```

Pick this when the app has **several** top-level commands but **one path-shaped default**. In this
repo that includes **`nim_file`**, **`nimr`**, **`gor`**, and the **`te-bin`** tools.


## Examples

### `examples/nim_minimal.nim`

The tiny version: one command, one option, no drama.

```bash
nim c -p:src examples/nim_minimal.nim
./examples/nim_minimal hello --name world
./examples/nim_minimal hello -n world
./examples/nim_minimal --name world
./examples/nim_minimal -h
./examples/nim_minimal completion zsh --print
./examples/nim_minimal completion bash > /tmp/_nim_minimal.bash && bash -n /tmp/_nim_minimal.bash
```

### `examples/nim_file.nim`

The less toy-looking version: nested subcommands (`stat → owner → lookup`), options at multiple
routing levels, and positional arguments.

```bash
nim c -p:src examples/nim_file.nim

./examples/nim_file                         # overview help (no args)
./examples/nim_file ./README.md            # same as read (bare path)
./examples/nim_file stat -h
./examples/nim_file stat owner -h
./examples/nim_file stat owner lookup --user-name alice ./README.md
./examples/nim_file rm a.txt b.txt
./examples/nim_file read ./README.md
./examples/nim_file write ./out.txt --content hello
./examples/nim_file completion zsh --print > ./_nim_file
./examples/nim_file completion bash > ./_nim_file.bash && bash -n ./_nim_file.bash
```

## Schema reference

All schema types are plain Nim `object` values on Nim 2+. **Required** fields still need to be
set explicitly. Fields with defaults can be omitted in constructors, though spelling them out is
also perfectly fine if you want the extra noise on purpose.

Quick legend:

- **Required** means you need to set it yourself.
- **Default** means you can omit it and let Nim do the boring part.
- **Notes** is where the sharp edges and useful behavior live.

### `cliGroup`

Builds a routing node: `commands` is a required parameter, so you cannot forget nested
subcommands at compile time. `handler` is always unset (implicit). The return value is the same
anonymous node type accepted in `CliSchema.commands` and in nested `commands` arguments (see
`argsbarg/schema.nim` for the full proc signature).

| Parameter | Notes |
| --- | --- |
| `name` / `description` | CLI token and help text for this routing node. |
| `commands` | **Required.** Child commands (each built with `cliLeaf` or `cliGroup`). |
| `options` | Optional flags on this routing node. |

### `cliLeaf`

Builds a leaf: `handler` is a required `CliHandler` parameter (not an `Option`), so omitting it is
a compile-time error. Return type is the same node type as for `cliGroup` (again, see
`argsbarg/schema.nim` for the exact signature).

| Parameter | Notes |
| --- | --- |
| `name` / `description` | Command token and help blurb. |
| `handler` | **Required.** Named proc implementing the command (must match `{.nimcall.}`). |
| `arguments` | Positional slots (`cliOptPositional` or `CliOption` with `isPositional: true`). |
| `options` | Flags (`cliOpt*` helpers or explicit `CliOption` values). |

### `CliCommand`

Declares one command node (leaf or routing). Prefer `cliLeaf` / `cliGroup` so required fields are
obvious at compile time; you can also construct `CliCommand(...)` directly when you need full
control.

| Field | Type | Required / Default | Notes |
| --- | --- | --- | --- |
| `arguments` | `seq[CliOption]` | Default: `@[]` | Positional slots for a leaf command. Use `cliOptPositional` or set `isPositional: true` on each `CliOption`. |
| `commands` | `seq[CliCommand]` | Default: `@[]` | Nested subcommands. If this has entries, the command is a routing node. |
| `description` | `string` | Required | Human-readable description shown in help. |
| `handler` | `Option[CliHandler]` | Required | Leaf: `some(yourProc)`. Routing node: `none(CliHandler)`. If argv stops on a routing node, argsbarg prints contextual help. |
| `name` | `string` | Required | The token users type on the command line. |
| `options` | `seq[CliOption]` | Default: `@[]` | Flags scoped to this command. |

### `CliContext`

This is what your handler receives. It is runtime data, not part of the schema.

| Field | Type | Meaning |
| --- | --- | --- |
| `appName` | `string` | Same as `CliSchema.name`. |
| `args` | `seq[string]` | Positional arguments collected for the leaf, in order. |
| `command` | `seq[string]` | Full command path to the invoked leaf, for example `@["stat", "owner", "lookup"]`. |
| `opts` | `Table[string, string]` | Parsed flags keyed by long `name`. Presence flags store `"1"`; use `optFlag`, `optNumber`, or `optString` instead of poking this directly unless you have a good reason. |

### `CliHandler`

```nim
type CliHandler* = proc (ctx: CliContext) {.nimcall.}
```

Use a named proc and pass it as the `handler` argument to `cliLeaf` (it must use the
`{.nimcall.}` calling convention, which plain top-level procs satisfy).

### `CliOption`

This covers both `--flags` and positional slots. `isPositional` is the switch that decides which
job it is doing. The following `cliOpt*` helpers are shorthand; you may still spell
`CliOption(...)` out by hand.

| Field | Type | Required / Default | Notes |
| --- | --- | --- | --- |
| `description` | `string` | Required | Shown in help output. |
| `isPositional` | `bool` | Default: `false` | Set to `true` to make the option a positional slot instead of a `--flag`. |
| `isRepeated` | `bool` | Default: `false` | When `isPositional: true`, collects all remaining argv words into `ctx.args`. |
| `kind` | `CliValueKind` | Required | Value kind. See `CliValueKind` below. |
| `name` | `string` | Required | Long option stem without the `--`. Also the key in `ctx.opts`. |
| `shortName` | `char` | Default: `'\0'` | Set to something like `'v'` to enable `-v`. Short aliases on positionals are rejected by validation. `-h` is reserved for help. Short names must be unique within each command's `options` list. Root `CliSchema.options` is not checked today, so keep those unique yourself. |

### `cliOptFlag`

Presence-only flag (`cliValueNone`). Optional `shortName` defaults to `CliNoShortName` (long
names only). Full signature lives in `argsbarg/schema.nim`.

### `cliOptNumber`

Valued flag parsed and validated as a float (`cliValueNumber`). Optional short alias like
`cliOptFlag`.

### `cliOptPositional`

String positional slot (`cliValueString`, `isPositional: true`). Optional `isRepeated` (default
`false`); when `true`, all remaining argv tokens after flags are collected into `ctx.args`.

### `cliOptString`

Valued string flag (`cliValueString`). Optional short alias like `cliOptFlag`.

### `CliFallbackMode`

Enum for `CliSchema.fallbackMode`. See **Root command fallback** above for full explanation and
`bash` examples.

| Value | Meaning |
| --- | --- |
| `cliFallbackWhenMissing` | Fallback only when no top-level command token remains (after root flags). |
| `cliFallbackWhenMissingOrUnknown` | Same, plus unknown first token is parsed as if `fallbackCommand` were first. |
| `cliFallbackWhenUnknown` | Empty command slot → root help; unknown first token behaves like `cliFallbackWhenMissingOrUnknown`. |

### `CliSchema`

| Field | Type | Required / Default | Notes |
| --- | --- | --- | --- |
| `commands` | `seq[CliCommand]` | Required | Top-level commands (from `cliLeaf` / `cliGroup` or `CliCommand(...)`). `cliMergeBuiltins` appends `completion` here, so don't steal that name. |
| `description` | `string` | Required | One-liner shown in root help. |
| `fallbackCommand` | `Option[string]` | Default: `none(string)` | Top-level command name used when fallback applies. Must exist in `commands`; validated. |
| `fallbackMode` | `CliFallbackMode` | Default: `cliFallbackWhenMissing` | When `fallbackCommand` applies; includes `cliFallbackWhenUnknown` (empty → root help, unknown token → fallback). |
| `name` | `string` | Required | App name. Also used for the completion script filename as `_{name}`. |
| `options` | `seq[CliOption]` | Default: `@[]` | Root-level flags, parsed before the first command token. |

### `CliValueKind`

`CliOption.kind` (or the matching `cliOpt*` helper) uses one of these values:

| Value | Meaning |
| --- | --- |
| `cliValueNone` | Presence flag. No value expected; sets `"1"` in `ctx.opts` when passed. Supports short bundling like `-abc`. |
| `cliValueNumber` | Takes a value and validates it as a float after parsing. |
| `cliValueString` | Takes a string value. |

## Shell completions

**Zsh:** run `<app> completion zsh` to install the script to `~/.zsh/completions/_{appname}`, or pass
`--print` to write it to stdout instead. If the completions directory doesn't exist yet, you'll
get a warning with the exact `fpath` setup instructions. argsbarg does not quietly jam files into
a directory zsh is not using and call that success.

**Bash:** run `<app> completion bash` and save stdout to a file you `source` from `~/.bashrc` or drop
under `bash_completion.d` (whatever your distro expects). `bash -n` on the generated file should
pass cleanly.

Both generators cover commands, subcommands, long options, and short aliases. Leaf commands with
positional arguments use file-path completion (`_files` on zsh, `compgen -f` on bash).

## Project tasks

- **`just build`** — Compile the library and both examples.
- **`just test`** — Run `tests/`.
- **`just smoke-file`** — Build and run focused CLI checks for `nim_file`.
- **`just smoke-minimal`** — Build and run focused checks for `nim_minimal`.
- **`just run-example-file ARGS...`** — Build and run `nim_file` with your args.
- **`just run-example-minimal ARGS...`** — Build and run `nim_minimal` with your args.
- **`just release-check`** — Full build, tests, and `zsh -n` / `bash -n` on generated completion scripts.

## License

MIT. See `LICENSE`.
