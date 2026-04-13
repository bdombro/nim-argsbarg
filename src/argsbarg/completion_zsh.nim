import std/[algorithm, options, os, strutils, tables]
import schema
import style

## One completion scope: command path, flags, children, and whether file completion applies.
type ScopeRec = object
  kids: seq[CliCommand]
  opts: seq[CliOption]
  path: string
  wantsFiles: bool


## Escapes a value for safe embedding inside single-quoted zsh words.
proc escZsh(s: string): string =
  result = s.replace("'", "'\\''")
  result = result.replace("\n", " ")


## Returns whether `cmd` declares any positional arguments.
proc hasPositionalArguments(cmd: CliCommand): bool =
  for a in cmd.arguments:
    if a.isPositional:
      return true
  false


## Maps an application name to a shell-safe identifier token for generated functions.
proc identToken(s: string): string =
  for ch in s:
    result.add(if ch.isAlphaNumeric: ch else: '_')


## Emits the `_nac_consume_long` helper that classifies `--flag` argv tokens per scope.
## Prints a single digit to stdout (0 unknown, 1 one word, 2 option plus separate value word)
## for capture by `_nac_simulate`; exits zero after printing.
proc emitConsumeLong(ident: string; scopes: seq[ScopeRec]): string =
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


## Emits `_nac_consume_short` which classifies short option argv tokens per scope.
## Prints a single digit to stdout (0 unknown, 1 one word, 2 valued flag needs next word)
## for capture by `_nac_simulate`; may `return` immediately after printing.
proc emitConsumeShort(ident: string; scopes: seq[ScopeRec]): string =
  var lines: seq[string] = @[]
  lines.add "_" & ident & "_nac_consume_short() {"
  lines.add "  local sid=\"$1\" w=\"$2\""
  lines.add "  case $sid in"
  for i, sc in scopes:
    lines.add "    " & $i & ")"
    lines.add "      local rest=${w#-}"
    lines.add "      local ch"
    lines.add "      local saw=0"
    lines.add "      while [[ -n $rest ]]; do"
    lines.add "        ch=${rest[1,1]}"
    lines.add "        rest=${rest[2,-1]}"
    lines.add "        case $ch in"
    var boolChars: seq[string] = @[]
    for o in sc.opts:
      if o.isPositional or o.shortName == CliNoShortName:
        continue
      if o.kind == cliValueNone:
        boolChars.add $o.shortName
      else:
        lines.add "          " & $o.shortName & ")"
        lines.add "            if [[ $saw -ne 0 || -n $rest ]]; then echo 0; return; fi"
        lines.add "            echo 2; return ;;"
    if boolChars.len > 0:
      lines.add "          " & boolChars.join("|") & ") ;;"
    lines.add "          *) echo 0; return ;;"
    lines.add "        esac"
    lines.add "        saw=1"
    lines.add "      done"
    lines.add "      echo 1"
    lines.add "      ;;"
  lines.add "    *) echo 0 ;;"
  lines.add "  esac"
  lines.add "  echo 0"
  lines.add "}"
  result = lines.join("\n") & "\n"


## Emits the compdef wrapper function body for the top-level command.
proc emitMainBody(schema: CliSchema; ident: string): string =
  let mainName = schema.name.replace("-", "_")
  result =
    "_" & mainName & "() {\n" &
    "  local curcontext=\"$curcontext\" ret=1\n" &
    "  _" & ident & "_nac_simulate\n" &
    "  local sid=$REPLY_SID\n" &
    "  if [[ $PREFIX == -* ]]; then\n" &
    "    local -a optsarr\n" &
    "    local oname=\"A_" & ident & "_${sid}_opts\"\n" &
    "    optsarr=(${(P@)oname})\n" &
    "    _describe -t options 'option' optsarr && ret=0\n" &
    "  else\n" &
    "    local lname=\"A_" & ident & "_${sid}_leaf\"\n" &
    "    if [[ ${(P)lname} -eq 0 ]]; then\n" &
    "      local -a cmdsarr\n" &
    "      local cname=\"A_" & ident & "_${sid}_cmds\"\n" &
    "      cmdsarr=(${(P@)cname})\n" &
    "      _describe -t commands 'command' cmdsarr && ret=0\n" &
    "    else\n" &
    "      local pname=\"A_" & ident & "_${sid}_pos\"\n" &
    "      if [[ ${(P)pname} -eq 1 ]]; then\n" &
    "        _files && ret=0\n" &
    "      fi\n" &
    "    fi\n" &
    "  fi\n" &
    "  return ret\n" &
    "}\n\n" &
    "compdef _" & mainName & " " & schema.name & "\n"


## Emits `_nac_match_child` mapping a word to the child scope index when applicable.
proc emitMatchChild(ident: string; scopes: seq[ScopeRec]; pathIndex: Table[string, int]): string =
  var lines: seq[string] = @[]
  lines.add "_" & ident & "_nac_match_child() {"
  lines.add "  local sid=\"$1\" w=\"$2\""
  lines.add "  case $sid in"
  for sid, sc in scopes:
    if sc.kids.len == 0:
      continue
    lines.add "    " & $sid & ")"
    lines.add "      case $w in"
    for ch in sc.kids:
      let childPath =
        if sc.path.len == 0:
          ch.name
        else:
          sc.path & "/" & ch.name
      let cid = pathIndex[childPath]
      lines.add "        " & ch.name & ") echo " & $cid & "; return 0 ;;"
    lines.add "      esac"
    lines.add "      ;;"
  lines.add "  esac"
  lines.add "  return 1"
  lines.add "}"
  result = lines.join("\n") & "\n"


## Emits `typeset` arrays holding command and option metadata for each scope row.
proc emitScopeArrays(ident: string; scopes: seq[ScopeRec]): string =
  var lines: seq[string] = @[]
  for i, sc in scopes:
    var cmdParts: seq[string] = @[]
    var sortedKids = sc.kids
    sortedKids.sort(proc(a, b: CliCommand): int = cmp(a.name, b.name))
    for c in sortedKids:
      cmdParts.add "'" & escZsh(c.name) & ":" & escZsh(c.description) & "'"
    lines.add "typeset -g -a A_" & ident & "_" & $i & "_cmds"
    if cmdParts.len == 0:
      lines.add "A_" & ident & "_" & $i & "_cmds=()"
    else:
      lines.add "A_" & ident & "_" & $i & "_cmds=(" & cmdParts.join(" ") & ")"
    var optParts: seq[string] = @[]
    optParts.add "'" & escZsh(CliHelpLongFlag) & ":" & escZsh("Show help for this command.") & "'"
    optParts.add "'" & escZsh(CliHelpShortFlag) & ":" & escZsh("Show help for this command.") & "'"
    var sortedOpts = sc.opts
    sortedOpts.sort(proc(a, b: CliOption): int = cmp(a.name, b.name))
    for o in sortedOpts:
      if o.isPositional:
        continue
      let lab =
        case o.kind
        of cliValueNone:
          escZsh("--" & o.name)
        of cliValueNumber:
          escZsh("--" & o.name & "=<number>")
        of cliValueString:
          escZsh("--" & o.name & "=<string>")
      optParts.add "'" & lab & ":" & escZsh(o.description) & "'"
      if o.shortName != CliNoShortName:
        optParts.add "'" & escZsh("-" & $o.shortName) & ":" & escZsh(o.description) & "'"
    lines.add "typeset -g -a A_" & ident & "_" & $i & "_opts"
    lines.add "A_" & ident & "_" & $i & "_opts=(" & optParts.join(" ") & ")"
    lines.add "typeset -g A_" & ident & "_" & $i & "_leaf=" &
      (if sc.kids.len == 0: "1" else: "0")
    lines.add "typeset -g A_" & ident & "_" & $i & "_pos=" &
      (if sc.wantsFiles: "1" else: "0")
  result = lines.join("\n") & "\n"


## Emits `_nac_simulate` which walks `words` to determine the active completion scope id.
proc emitSimulate(ident: string): string =
  result = "_" & ident & "_nac_simulate() {\n" &
    "  local i=2 sid=0\n" &
    "  while (( i < CURRENT )); do\n" &
    "    local w=$words[i]\n" &
    "    if [[ $w == " & CliHelpShortFlag & " || $w == " & CliHelpLongFlag &
    " ]]; then\n" &
    "      ((i++)); continue\n" &
    "    fi\n" &
    "    if [[ $w == --* ]]; then\n" &
    "      local steps\n" &
    "      steps=$(_" & ident & "_nac_consume_long \"$sid\" \"$w\" \"${words[i+1]}\")\n" &
    "      case $steps in\n" &
    "        0) break ;;\n" &
    "        1) ((i++)) ;;\n" &
    "        2) ((i+=2)) ;;\n" &
    "      esac\n" &
    "      continue\n" &
    "    fi\n" &
    "    if [[ $w == -* ]]; then\n" &
    "      local steps\n" &
    "      steps=$(_" & ident & "_nac_consume_short \"$sid\" \"$w\")\n" &
    "      case $steps in\n" &
    "        0) break ;;\n" &
    "        1) ((i++)) ;;\n" &
    "        2) ((i++)); break ;;\n" &
    "      esac\n" &
    "      continue\n" &
    "    fi\n" &
    "    local next\n" &
    "    next=$(_" & ident & "_nac_match_child \"$sid\" \"$w\") || break\n" &
    "    sid=$next\n" &
    "    ((i++))\n" &
    "  done\n" &
    "  REPLY_SID=$sid\n" &
    "}\n"


## Flattens the schema into a breadth-first list of completion scopes.
proc collectScopes(schema: CliSchema): seq[ScopeRec] =
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


## Builtin command definition merged into every consumer schema (handled in `cliRun`).
proc completionZshBuiltinCommand*(): CliCommand =
  CliCommand(
    arguments: @[],
    commands: @[],
    description: "Install zsh tab completions to ~/.zsh/completions/_<appname>. To print the script to stdout, use --print.",
    handler: none(CliHandler),
    name: CliBuiltinCompletionsZshName,
    options: @[
      CliOption(
        description: "Print the completion script to stdout instead of installing it.",
        isPositional: false,
        isRepeated: false,
        kind: cliValueNone,
        name: "print",
      ),
    ],
  )


## Builds a zsh completion script for the application name in `schema`.
proc completionZshScript*(schema: CliSchema): string =
  let ident = identToken(schema.name)
  let scopes = collectScopes(schema)
  var pathIndex = initTable[string, int]()
  for i, sc in scopes:
    pathIndex[sc.path] = i
  let arrays = emitScopeArrays(ident, scopes)
  let consume = emitConsumeLong(ident, scopes)
  let consumeShort = emitConsumeShort(ident, scopes)
  let matchc = emitMatchChild(ident, scopes, pathIndex)
  let sim = emitSimulate(ident)
  let mainB = emitMainBody(schema, ident)
  result = "#compdef " & schema.name & "\n\n" & arrays & consume & consumeShort & matchc & sim & mainB


## Installs or prints the zsh completion script for the active application.
proc completionZshRun*(schema: CliSchema; ctx: CliContext) =
  let script = completionZshScript(schema)
  if ctx.optFlag("print"):
    stdout.write(script)
    return
  let home = getEnv("HOME")
  if home.len == 0:
    stderr.writeLine styleRed("HOME is not set; cannot install completions.")
    quit(1)
  let dir = joinPath(home, ".zsh", "completions")
  if not dirExists(dir):
    stderr.writeLine styleYellow("WARNING: ") & styleDim(
      "~/.zsh/completions does not exist. Create it and add to fpath in " &
      "~/.zshrc, for example: fpath=(~/.zsh/completions $fpath); autoload -Uz compinit; compinit") & "\n"
  createDir(dir)
  let path = joinPath(dir, "_" & schema.name)
  writeFile(path, script)
