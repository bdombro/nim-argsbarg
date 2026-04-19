import std/[algorithm, strutils, tables]
import completion_shared
import schema

## Emits `_nac_consume_short` which classifies short option argv tokens per scope.
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
    lines.add "        ch=${rest:0:1}"
    lines.add "        rest=${rest:1}"
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
  lines.add "}"
  result = lines.join("\n") & "\n"


## Emits the main completion function and `complete -F` registration.
proc emitMainBody(schema: CliSchema; ident: string; scopes: seq[ScopeRec]): string =
  let mainName = schema.name.replace("-", "_")
  var lines: seq[string] = @[]
  lines.add "_" & mainName & "() {"
  lines.add "  local cur prev words cword split=false"
  lines.add "  _init_completion -s || return"
  for i, sc in scopes:
    var cmdParts: seq[string] = @[]
    var sortedKids = sc.kids
    sortedKids.sort(proc(a, b: CliCommand): int = cmp(a.name, b.name))
    for c in sortedKids:
      cmdParts.add "'" & escShellSingleQuoted(c.name) & "'"
    if cmdParts.len == 0:
      lines.add "  local -a _" & ident & "_cmds_" & $i & "=()"
    else:
      lines.add "  local -a _" & ident & "_cmds_" & $i & "=(" & cmdParts.join(" ") & ")"
    var optParts: seq[string] = @[]
    optParts.add "'" & escShellSingleQuoted(CliHelpLongFlag) & "'"
    optParts.add "'" & escShellSingleQuoted(CliHelpShortFlag) & "'"
    var sortedOpts = sc.opts
    sortedOpts.sort(proc(a, b: CliOption): int = cmp(a.name, b.name))
    for o in sortedOpts:
      if o.isPositional:
        continue
      case o.kind
      of cliValueNone:
        optParts.add "'" & escShellSingleQuoted("--" & o.name) & "'"
      of cliValueNumber, cliValueString:
        optParts.add "'" & escShellSingleQuoted("--" & o.name & "=") & "'"
      if o.shortName != CliNoShortName:
        optParts.add "'" & escShellSingleQuoted("-" & $o.shortName) & "'"
    lines.add "  local -a _" & ident & "_opts_" & $i & "=(" & optParts.join(" ") & ")"
    lines.add "  local _" & ident & "_leaf_" & $i & "=" & (if sc.kids.len == 0: "1" else: "0")
    lines.add "  local _" & ident & "_pos_" & $i & "=" & (if sc.wantsFiles: "1" else: "0")
  lines.add "  local sid"
  lines.add "  sid=$(_" & ident & "_nac_simulate)"
  lines.add "  if [[ $cur == -* ]]; then"
  lines.add "    case $sid in"
  for i in 0 ..< scopes.len:
    lines.add "      " & $i &
      ") COMPREPLY=( $(compgen -W \"${_" & ident & "_opts_" & $i & "[*]}\" -- \"$cur\") ) ;;"
  lines.add "    esac"
  lines.add "  else"
  lines.add "    case $sid in"
  for i in 0 ..< scopes.len:
    lines.add "      " & $i & ")"
    lines.add "        if [[ ${_" & ident & "_leaf_" & $i & "} -eq 0 ]]; then"
    lines.add "          COMPREPLY=( $(compgen -W \"${_" & ident & "_cmds_" & $i &
      "[*]}\" -- \"$cur\") )"
    lines.add "        elif [[ ${_" & ident & "_pos_" & $i & "} -eq 1 ]]; then"
    lines.add "          COMPREPLY=( $(compgen -f -- \"$cur\") )"
    lines.add "        fi ;;"
  lines.add "    esac"
  lines.add "  fi"
  lines.add "}"
  lines.add ""
  lines.add "complete -F _" & mainName & " " & schema.name
  result = lines.join("\n") & "\n"


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


## Emits `_nac_simulate` which walks `words` to determine the active completion scope id.
proc emitSimulate(ident: string): string =
  result = "_" & ident & "_nac_simulate() {\n" &
    "  local i=1 sid=0 w steps next\n" &
    "  while (( i < cword )); do\n" &
    "    w=${words[i]}\n" &
    "    if [[ $w == " & CliHelpShortFlag & " || $w == " & CliHelpLongFlag &
    " ]]; then\n" &
    "      ((i++)); continue\n" &
    "    fi\n" &
    "    if [[ $w == --* ]]; then\n" &
    "      steps=$(_" & ident & "_nac_consume_long \"$sid\" \"$w\" \"${words[i+1]}\")\n" &
    "      case $steps in\n" &
    "        0) break ;;\n" &
    "        1) ((i++)) ;;\n" &
    "        2) ((i+=2)) ;;\n" &
    "        *) break ;;\n" &
    "      esac\n" &
    "      continue\n" &
    "    fi\n" &
    "    if [[ $w == -* ]]; then\n" &
    "      steps=$(_" & ident & "_nac_consume_short \"$sid\" \"$w\")\n" &
    "      case $steps in\n" &
    "        0) break ;;\n" &
    "        1) ((i++)) ;;\n" &
    "        2) ((i++)); break ;;\n" &
    "        *) break ;;\n" &
    "      esac\n" &
    "      continue\n" &
    "    fi\n" &
    "    next=$(_" & ident & "_nac_match_child \"$sid\" \"$w\") || break\n" &
    "    sid=$next\n" &
    "    ((i++))\n" &
    "  done\n" &
    "  printf '%s\\n' \"$sid\"\n" &
    "}\n"


## Builtin `completion bash` leaf merged into every consumer schema (handled in `cliRun`).
proc completionBashBuiltinCommand*(): CliCommand =
  proc noop(ctx: CliContext) {.nimcall.} =
    discard

  cliLeaf(
    CliBuiltinCompletionBashName,
    "Generate the autocompletion script for bash.",
    noop,
    notes =
      "Prints the completion script to stdout only (no automatic file write). Two ways to " &
      "activate it:\n" &
      "\n" &
      "Save and source (persistent, recommended):\n" &
      "  {app} completion bash > ~/.bash_completions/{app}\n" &
      "  bash -n ~/.bash_completions/{app}\n" &
      "  echo 'source ~/.bash_completions/{app}' >> ~/.bashrc\n" &
      "  source ~/.bashrc\n" &
      "\n" &
      "Process substitution (re-reads the script every new shell):\n" &
      "  echo 'source <({app} completion bash)' >> ~/.bashrc\n" &
      "  source ~/.bashrc\n" &
      "\n" &
      "If you use the bash-completion package, you can install to:\n" &
      "  ~/.local/share/bash-completion/completions/{app}",
  )


## Builds a bash completion script for the application name in `schema`.
proc completionBashScript*(schema: CliSchema): string =
  let ident = identToken(schema.name)
  let scopes = collectScopes(schema)
  var pathIndex = initTable[string, int]()
  for i, sc in scopes:
    pathIndex[sc.path] = i
  let consume = emitConsumeLong(ident, scopes)
  let consumeShort = emitConsumeShort(ident, scopes)
  let matchc = emitMatchChild(ident, scopes, pathIndex)
  let sim = emitSimulate(ident)
  let mainB = emitMainBody(schema, ident, scopes)
  result = "# Generated bash completion for " & schema.name & ".\n\n" & consume & consumeShort &
    matchc & sim & mainB


## Prints the bash completion script to stdout.
proc completionBashRun*(schema: CliSchema; ctx: CliContext) =
  stdout.write(completionBashScript(schema))
