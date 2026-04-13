import std/[options, strutils, tables]
import schema

## Parses argv against a merged schema and returns help, ok, or error outcomes.
proc cliParse*(schema: CliSchema; argv: seq[string]): CliParseResult =
  var i = 0
  var path: seq[string] = @[]
  var opts = initTable[string, string]()

  ## Resolves a direct child command by name from `cmds`.
  proc findChild(cmds: seq[CliCommand]; name: string): Option[CliCommand] =
    for c in cmds:
      if c.name == name:
        return some(c)
    none(CliCommand)


  ## Looks up an option definition by long name within `defs`.
  proc findOptionDef(defs: seq[CliOption]; name: string): Option[CliOption] =
    for o in defs:
      if o.name == name:
        return some(o)
    none(CliOption)


  ## Recognizes `-h` / `--help` tokens for help branch handling.
  proc isHelpTok(tok: string): bool {.inline.} =
    tok == CliHelpShortFlag or tok == CliHelpLongFlag


  ## Consumes long options at the current argv index until a non-flag token.
  proc consumeOptions(defs: seq[CliOption]): Option[string] =
    while i < argv.len:
      let tok = argv[i]
      if isHelpTok(tok):
        return none(string)
      if not tok.startsWith("-"):
        break
      if tok.startsWith("--"):
        var optName: string
        var optVal: string
        let eq = tok.find('=')
        if eq >= 0:
          optName = tok[2 ..< eq]
          optVal = tok[eq + 1 .. ^1]
        else:
          optName = tok[2 .. ^1]
          let def = findOptionDef(defs, optName)
          if def.isNone:
            return some("Unknown option: --" & optName)
          if def.get.kind == cliValueNone:
            optVal = "1"
          else:
            inc i
            if i >= argv.len:
              return some("Missing value for option: --" & optName)
            optVal = argv[i]
        let def2 = findOptionDef(defs, optName)
        if def2.isNone:
          return some("Unknown option: --" & optName)
        opts[optName] = optVal
        inc i
      else:
        return some("Short options other than -h are not supported: " & tok)
    none(string)


  ## Builds a parse result that requests help for path `p`.
  proc helpResult(p: seq[string]): CliParseResult =
    CliParseResult(kind: cliParseHelp, helpPath: p)


  ## Builds a parse result carrying a user-facing error message.
  proc errorResult(m: string): CliParseResult =
    CliParseResult(kind: cliParseError, msg: m)


  ## Builds a successful parse result with path, options, and positional args.
  proc okResult(p: seq[string]; o: Table[string, string]; a: seq[string]): CliParseResult =
    CliParseResult(kind: cliParseOk, path: p, opts: o, args: a)


  ## Finishes parsing at a leaf command, collecting positional arguments.
  proc finishLeaf(node: CliCommand): CliParseResult =
    var args: seq[string] = @[]
    for p in node.arguments:
      if not p.isPositional:
        continue
      if p.isRepeated:
        while i < argv.len:
          args.add argv[i]
          inc i
        break
      if i >= argv.len:
        return errorResult("Missing positional argument: " & p.name)
      args.add argv[i]
      inc i
    if i < argv.len:
      return errorResult("Unexpected extra arguments")
    okResult(path, opts, args)

  let rootOptErr = consumeOptions(schema.options)
  if rootOptErr.isSome:
    return errorResult(rootOptErr.get)
  if i < argv.len and isHelpTok(argv[i]):
    return helpResult(@[])

  var cmdName: string
  if i < argv.len:
    cmdName = argv[i]
    inc i
  elif schema.defaultCommand.isSome:
    cmdName = schema.defaultCommand.get
  else:
    return helpResult(@[])

  var nodeOpt = findChild(schema.commands, cmdName)
  if nodeOpt.isNone:
    return errorResult("Unknown command: " & cmdName)
  path.add cmdName
  var node = nodeOpt.get

  while true:
    let oerr = consumeOptions(node.options)
    if oerr.isSome:
      return errorResult(oerr.get)
    if i < argv.len and isHelpTok(argv[i]):
      return helpResult(path)

    if i >= argv.len:
      if node.commands.len > 0:
        return helpResult(path)
      return finishLeaf(node)

    let tok = argv[i]
    if tok.startsWith("-"):
      return errorResult("Unexpected option token: " & tok)

    let childOpt = findChild(node.commands, tok)
    if childOpt.isSome:
      inc i
      path.add tok
      node = childOpt.get
      continue

    if node.commands.len > 0:
      return errorResult("Unknown subcommand: " & tok)

    return finishLeaf(node)
