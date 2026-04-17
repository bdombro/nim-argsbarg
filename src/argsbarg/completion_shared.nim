import schema
import std/strutils

type ScopeRec* = object
  kids*: seq[CliCommand]
  opts*: seq[CliOption]
  path*: string
  wantsFiles*: bool


## Emits the `_nac_consume_long` helper that classifies `--flag` argv tokens per scope.
proc emitConsumeLong*(ident: string; scopes: seq[ScopeRec]): string =
  var lines: seq[string] = @[]
  lines.add "_" & ident & "_nac_consume_long() {"
  lines.add "  local sid=\"$1\" w=\"$2\" nw=\"$3\""
  lines.add "  case $sid in"
  for i, sc in scopes:
    lines.add "    " & $i & ")"
    lines.add "      case $w in"
    lines.add "        " & CliHelpLongFlag & "|" & CliHelpLongFlag &
      "=*|" & CliHelpShortFlag & ") echo 1 ;;"
    for o in sc.opts:
      if o.isPositional:
        continue
      let base = "--" & o.name
      case o.kind
      of cliValueNone:
        lines.add "        " & base & "|" & base & "=*) echo 1 ;;"
      of cliValueNumber, cliValueString:
        lines.add "        " & base & "=*) echo 1 ;;"
        lines.add "        " & base & ") echo 2 ;;"
    lines.add "        *) echo 0 ;;"
    lines.add "      esac"
    lines.add "      ;;"
  lines.add "    *) echo 0 ;;"
  lines.add "  esac"
  lines.add "}"
  result = lines.join("\n") & "\n"


## Escapes a value for safe embedding inside single-quoted bash/zsh words.
proc escShellSingleQuoted*(s: string): string =
  result = s.replace("'", "'\\''")
  result = result.replace("\n", " ")


## Returns whether `cmd` declares any positional arguments.
proc hasPositionalArguments*(cmd: CliCommand): bool =
  for a in cmd.arguments:
    if a.isPositional:
      return true
  false


## Maps an application name to a shell-safe identifier token for generated functions.
proc identToken*(s: string): string =
  for ch in s:
    result.add(if ch.isAlphaNumeric: ch else: '_')


## Flattens the schema into a breadth-first list of completion scopes.
proc collectScopes*(schema: CliSchema): seq[ScopeRec] =
  var acc: seq[ScopeRec] = @[]
  acc.add ScopeRec(
    kids: schema.commands,
    opts: schema.options,
    path: "",
    wantsFiles: false,
  )

  ## Appends scopes for `cmd` and recursively descends into its subcommands.
  proc walk(cmdPath: string; cmd: CliCommand) =
    acc.add ScopeRec(
      kids: cmd.commands,
      opts: cmd.options,
      path: cmdPath,
      wantsFiles: hasPositionalArguments(cmd),
    )
    for ch in cmd.commands:
      let nextPath =
        if cmdPath.len == 0:
          ch.name
        else:
          cmdPath & "/" & ch.name
      walk(nextPath, ch)

  for c in schema.commands:
    walk(c.name, c)
  result = acc
