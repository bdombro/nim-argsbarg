# argsbarg

`argsbarg` is a small, schema-first command-line toolkit for Nim: you describe commands, options, and positional arguments as plain `object` values, call `cliRun`, and get parsing, validation, scoped help, default styling, and zsh completion generation from the same source of truth.

## Quick start

```bash
nimble install argsbarg
```

```nim
import std/os
import argsbarg

proc greet(ctx: CliContext) =
  let n = ctx.optString("name")
  let who = if n.isSome: n.get else: "world"
  echo styleGreen("hello"), " ", who

let schema = CliSchema(
  name: "helloapp",
  description: "Tiny demo.",
  options: @[],
  defaultCommand: none(string),
  commands: @[
    CliCommand(
      name: "hello",
      description: "Say hello.",
      handler: some(greet),
      options: @[
        CliOption(
          name: "name",
          description: "Who to greet.",
          kind: cliValueString,
          isPositional: false,
          isRepeated: false,
        ),
      ],
      arguments: @[],
      commands: @[],
    ),
  ],
)

when isMainModule:
  cliRun(schema, commandLineParams())
```

Every app also receives built-ins merged by `cliRun`:

- `-h` / `--help` at any routing depth, scoped to that node (root help lists only root options and top-level commands).
- `completions-zsh` with `--print` to write the completion script to stdout, or install under `~/.zsh/completions/_{app}` by default.

Consumers must not declare their own top-level command named `completions-zsh`; it is reserved.


### Local development (this repository)

Build and run tests with [`just`](https://github.com/casey/just):

```bash
just build
just test
```

Compile examples against the working tree by passing the library `src` directory on the Nim search path:

```bash
nim c -p:src examples/nim_file.nim
nim c -p:src examples/nim_minimal.nim
```

`nimble test` is also wired to the same two unit-test binaries, but Nimble may refuse to run until the repository has at least one Git commit (it wants a VCS revision). If you hit that error, use `just test` or make an initial commit.

## Core ideas

- **Schema types** live in `argsbarg` (`CliSchema`, `CliCommand`, `CliOption`, `CliValueKind`, and friends).
- **`cliRun(schema, argv)`** validates the schema, parses argv, renders help or errors with shared styling, handles built-ins, and dispatches the resolved leaf handler.
- **`cliParse(schema, argv)`** returns a `CliParseResult` for tests and advanced callers; it expects a **merged** schema if you need built-ins to exist in the tree (use `cliMergeBuiltins`).

### `defaultCommand` (root only)

`CliSchema.defaultCommand` may name a **top-level** command to run when argv contains no command token after root options. If it is unset and the user passes no command, the framework prints **root** help.

Nested routing commands never use `defaultCommand`: if a node still has subcommands and argv ends before choosing one, **contextual help** for that node is printed.

### Handlers and routing nodes

- **Leaf** commands must supply `handler: some(...)`.
- **Intermediate** nodes that only route to subcommands use `handler: none(CliHandler)`; if argv stops there, help is shown instead of dispatch.

### Options and positionals

- Long options use `--name` and, for valued kinds, `--name value` or `--name=value`.
- Short flags other than `-h` are rejected with a clear error (matching the current parser).
- Positional arguments are `CliOption` values with `isPositional: true`, usually attached to leaf commands.

### Type helpers on `CliContext`

- `ctx.optString("opt")` → `Option[string]`
- `ctx.optNumber("opt")` → `Option[float]` with coercion
- `ctx.optFlag("opt")` → `bool` for `cliValueNone` options

## Example: `examples/nim_file.nim`

`nim_file` demonstrates nested commands, scoped help, validation, POSIX-flavored handlers, and completion generation.

Typical invocations:

```bash
nim c -p:src examples/nim_file.nim

./examples/nim_file                         # root help (no defaultCommand)
./examples/nim_file -h
./examples/nim_file stat -h
./examples/nim_file stat owner -h
./examples/nim_file stat owner lookup --user-name alice ./README.md
./examples/nim_file rm a.txt b.txt
./examples/nim_file touch a.txt
./examples/nim_file read ./README.md
./examples/nim_file write ./out.txt --content hello

./examples/nim_file completions-zsh --print > ./_nim_file
```

Root help lists `stat`, `rm`, `touch`, `read`, `write`, and the injected `completions-zsh` entry. `stat` keeps a three-level branch (`stat → owner → lookup`) with options at multiple levels; routing nodes print contextual help when no subcommand is chosen.

## Example: `examples/nim_minimal.nim`

The smallest end-to-end app: one leaf command (`hello`), one string option (`--name`), and `cliRun`.

```bash
nim c -p:src examples/nim_minimal.nim
./examples/nim_minimal hello --name world
./examples/nim_minimal -h
./examples/nim_minimal completions-zsh --print
```

## Zsh completions

- `completions-zsh --print` writes the script to stdout (no install-time warnings).
- Without `--print`, the script is written to `~/.zsh/completions/_{appname}`.
- If `~/.zsh/completions` is missing, a **warning** explains that you should create it and add it to `fpath` before running `compinit`. The generator does not inspect your dotfiles.

The completion script is derived from the same merged schema used for parsing and help. It offers commands, nested subcommands, and long options (including synthesized help flags) and falls back to `_files` on leaf commands that declare positional arguments.

## Project tasks

| Command | Purpose |
| --- | --- |
| `just build` | Compile the library and both examples |
| `just test` | Run `tests/` |
| `just run-example-file ARGS...` | Build and run `nim_file` |
| `just run-example-minimal ARGS...` | Build and run `nim_minimal` |
| `just smoke-file` | Build plus focused CLI checks for `nim_file` |
| `just smoke-minimal` | Build plus focused checks for `nim_minimal` |
| `just release-check` | `build`, `tests`, and zsh syntax checks on generated scripts |


## License

MIT. See `LICENSE`.
