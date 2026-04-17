import std/[options, strutils, tables]
import schema

## Parses argv against a merged schema and returns help, ok, or error outcomes.
proc cliParse*(schema: CliSchema; argv: seq[string]): CliParseResult =
  var i = 0
  var path: seq[string] = @[]
  var opts = initTable[string, string]()

  ## Looks up an option definition by short alias within `defs`.
  proc findOptionDefByShort(defs: seq[CliOption]; shortName: char): Option[CliOption] =
    for o in defs:
      if o.shortName == shortName:
        return some(o)
    none(CliOption)


  ## Recognizes `-h` / `--help` tokens for help branch handling.
  proc isHelpTok(tok: string): bool {.inline.} =
    tok == CliHelpShortFlag or tok == CliHelpLongFlag


  ## Result of scanning argv for flags: either an error string, or a clean stop because the next
  ## token is not a flag, or ``stoppedOnUnknown`` when root parsing should hand the token to the
  ## fallback command instead of rejecting it as an unknown root option.
  type CliConsumeOptsReport = object
    err: Option[string]
    stoppedOnUnknown: bool

  ## Reads consecutive ``--foo`` / ``-f`` tokens using ``defs``. When ``lenientUnknown`` is true,
  ## an unrecognized flag stops consumption without error so a later stage can treat it as part
  ## of the fallback subcommand.
  proc consumeOptions(defs: seq[CliOption]; lenientUnknown: bool): CliConsumeOptsReport =
    type CliLineConsumeKind = enum
      cliLineOk
      cliLineErr
      cliLineLenientStop

    proc consumeLongOption(tok: string): (CliLineConsumeKind, Option[string]) =
      var optName: string
      var optVal: string
      let eq = tok.find('=')
      if eq >= 0:
        optName = tok[2 ..< eq]
        optVal = tok[eq + 1 .. ^1]
      else:
        optName = tok[2 .. ^1]
      let def = findOptionByName(defs, optName)
      if def.isNone:
        if lenientUnknown:
          return (cliLineLenientStop, none(string))
        return (cliLineErr, some("Unknown option: --" & optName))
      if eq < 0:
        if def.get.kind == cliValueNone:
          optVal = "1"
        else:
          inc i
          if i >= argv.len:
            return (cliLineErr, some("Missing value for option: --" & optName))
          optVal = argv[i]
      opts[optName] = optVal
      inc i
      (cliLineOk, none(string))


    proc consumeShortOption(tok: string): (CliLineConsumeKind, Option[string]) =
      if tok.len < 2:
        return (cliLineErr, some("Unexpected option token: " & tok))
      let shorts = tok[1 .. ^1]
      var j = 0
      while j < shorts.len:
        let shortName = shorts[j]
        let def = findOptionDefByShort(defs, shortName)
        if def.isNone:
          if lenientUnknown:
            return (cliLineLenientStop, none(string))
          return (cliLineErr, some("Unknown option: -" & $shortName))
        if def.get.kind == cliValueNone:
          opts[def.get.name] = "1"
          inc j
          continue
        if shorts.len != 1:
          return (
            cliLineErr,
            some(
              "Short option -" & $shortName & " requires a value and cannot be bundled: " & tok,
            ),
          )
        inc i
        if i >= argv.len:
          return (cliLineErr, some("Missing value for option: -" & $shortName))
        opts[def.get.name] = argv[i]
        inc i
        return (cliLineOk, none(string))
      inc i
      (cliLineOk, none(string))

    while i < argv.len:
      let tok = argv[i]
      if isHelpTok(tok):
        break
      if not tok.startsWith("-"):
        break
      if tok.startsWith("--"):
        let (kind, msg) = consumeLongOption(tok)
        case kind
        of cliLineErr:
          return CliConsumeOptsReport(err: msg)
        of cliLineLenientStop:
          return CliConsumeOptsReport(stoppedOnUnknown: true)
        of cliLineOk:
          discard
      else:
        let (kind, msg) = consumeShortOption(tok)
        case kind
        of cliLineErr:
          return CliConsumeOptsReport(err: msg)
        of cliLineLenientStop:
          return CliConsumeOptsReport(stoppedOnUnknown: true)
        of cliLineOk:
          discard
    CliConsumeOptsReport()


  ## Builds a parse result that requests help for path `p`.
  proc helpResult(p: seq[string]; explicit: bool): CliParseResult =
    CliParseResult(kind: cliParseHelp, helpExplicit: explicit, helpPath: p)


  ## Builds a parse result carrying a user-facing error message.
  proc errorResult(m: string): CliParseResult =
    CliParseResult(kind: cliParseError, msg: m, errorHelpPath: path)


  ## Builds a successful parse result with path, options, and positional args.
  proc okResult(p: seq[string]; o: Table[string, string]; a: seq[string]): CliParseResult =
    CliParseResult(kind: cliParseOk, path: p, opts: o, args: a)


  ## Finishes parsing at a leaf command, collecting positional arguments.
  proc finishLeaf(node: CliCommand): CliParseResult =
    var args: seq[string] = @[]
    for p in node.arguments:
      if not p.isPositional:
        continue
      if p.argMax == 1:
        if p.argMin >= 1:
          if i >= argv.len:
            return errorResult("Missing positional argument: " & p.name)
          args.add argv[i]
          inc i
        elif i < argv.len:
          args.add argv[i]
          inc i
        continue
      var count = 0
      if p.argMax == 0:
        while i < argv.len:
          args.add argv[i]
          inc i
          inc count
      else:
        while count < p.argMax and i < argv.len:
          args.add argv[i]
          inc i
          inc count
      if count < p.argMin:
        return errorResult(
          "Expected at least " & $p.argMin & " argument(s) for " & p.name & ", got " & $count,
        )
    if i < argv.len:
      return errorResult("Unexpected extra arguments")
    okResult(path, opts, args)

  let rootLenient = schema.fallbackCommand.isSome and (
    schema.fallbackMode == cliFallbackWhenMissingOrUnknown or
    schema.fallbackMode == cliFallbackWhenUnknown)
  let rootReport = consumeOptions(schema.options, rootLenient)
  if rootReport.err.isSome:
    return errorResult(rootReport.err.get)
  if i < argv.len and isHelpTok(argv[i]):
    return helpResult(@[], true)

  var cmdName: string
  var node: CliCommand
  if i >= argv.len:
    if schema.fallbackCommand.isSome and (
        schema.fallbackMode == cliFallbackWhenMissing or
        schema.fallbackMode == cliFallbackWhenMissingOrUnknown):
      cmdName = schema.fallbackCommand.get
      let picked = findChild(schema.commands, cmdName)
      if picked.isNone:
        return errorResult("Unknown command: " & cmdName)
      node = picked.get
    else:
      return helpResult(@[], false)
  else:
    let peek = argv[i]
    let childPick = findChild(schema.commands, peek)
    if childPick.isSome:
      cmdName = peek
      inc i
      node = childPick.get
    elif schema.fallbackCommand.isSome and (
        schema.fallbackMode == cliFallbackWhenMissingOrUnknown or
        schema.fallbackMode == cliFallbackWhenUnknown):
      cmdName = schema.fallbackCommand.get
      let picked = findChild(schema.commands, cmdName)
      if picked.isNone:
        return errorResult("Unknown command: " & cmdName)
      node = picked.get
    else:
      cmdName = peek
      inc i
      let picked = findChild(schema.commands, cmdName)
      if picked.isNone:
        return errorResult("Unknown command: " & cmdName)
      node = picked.get

  path.add cmdName

  while true:
    let orep = consumeOptions(node.options, false)
    if orep.err.isSome:
      return errorResult(orep.err.get)
    if i < argv.len and isHelpTok(argv[i]):
      return helpResult(path, true)

    if i >= argv.len:
      if node.commands.len > 0:
        return helpResult(path, false)
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
