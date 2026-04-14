import std/[options, strutils, tables]
import errors
import schema

## Checks a merged schema for mistakes (reserved names, bad fallbacks, duplicate short flags, …)
## before argv parsing or dispatch.
proc cliSchemaValidate*(schema: CliSchema) {.raises: [ArgsbargSchemaDefect].} =
  if schema.fallbackCommand.isNone and (
      schema.fallbackMode == cliFallbackWhenMissingOrUnknown or
      schema.fallbackMode == cliFallbackWhenUnknown):
    raise ArgsbargSchemaDefect.newException(
      "this fallbackMode requires fallbackCommand")

  if schema.fallbackCommand.isSome:
    var found = false
    let want = schema.fallbackCommand.get
    for c in schema.commands:
      if c.name == want:
        found = true
        break
    if not found:
      raise ArgsbargSchemaDefect.newException(
        "fallbackCommand not found in commands: " & want)

  ## Validates short aliases within a single option scope.
  proc checkOptions(defs: seq[CliOption]; scope: string) =
    var seenShorts = initTable[char, string]()
    for d in defs:
      if d.shortName == CliNoShortName:
        continue
      if d.isPositional:
        raise ArgsbargSchemaDefect.newException(
          "Positional arguments must not define short aliases: " & scope & "/" & d.name)
      if d.shortName == 'h':
        raise ArgsbargSchemaDefect.newException(
          "Short alias -h is reserved for help: " & scope & "/" & d.name)
      if seenShorts.hasKey(d.shortName):
        let prev = seenShorts.getOrDefault(d.shortName)
        raise ArgsbargSchemaDefect.newException(
          "Duplicate short alias -" & $d.shortName & " in scope " & scope &
          " for options " & prev & " and " & d.name)
      seenShorts[d.shortName] = d.name

  ## Recursively checks routing vs leaf command handler rules.
  proc walk(cmd: CliCommand) =
    if cmd.commands.len > 0:
      if cmd.handler.isSome:
        raise ArgsbargSchemaDefect.newException(
          "Routing command must not set handler: " & cmd.name)
      checkOptions(cmd.options, cmd.name)
      checkOptions(cmd.arguments, cmd.name)
      for ch in cmd.commands:
        walk(ch)
    else:
      if cmd.handler.isNone:
        raise ArgsbargSchemaDefect.newException(
          "Leaf command requires handler: " & cmd.name)
      checkOptions(cmd.options, cmd.name)
      checkOptions(cmd.arguments, cmd.name)

  for c in schema.commands:
    walk(c)


## Validates option value shapes for a successful parse result.
proc cliValidate*(schema: CliSchema; pr: CliParseResult): CliParseResult =
  if pr.kind != cliParseOk:
    return pr

  ## Resolves a direct child command by name from `cmds`.
  proc findChild(cmds: seq[CliCommand]; name: string): Option[CliCommand] =
    for c in cmds:
      if c.name == name:
        return some(c)
    none(CliCommand)


  var defs: seq[CliOption] = @[]
  defs.add schema.options
  var cmds = schema.commands
  for seg in pr.path:
    let ch = findChild(cmds, seg)
    if ch.isNone:
      return CliParseResult(kind: cliParseError, msg: "Internal path error")
    defs.add ch.get.options
    defs.add ch.get.arguments
    cmds = ch.get.commands

  ## Finds a merged option definition by name across the current command path.
  proc findDef(name: string): Option[CliOption] =
    for d in defs:
      if d.name == name:
        return some(d)
    none(CliOption)

  for k, v in pr.opts.pairs:
    let d = findDef(k)
    if d.isNone:
      return CliParseResult(kind: cliParseError, msg: "Unknown option key: " & k)
    if d.get.kind == cliValueNumber:
      try:
        discard parseFloat(v)
      except ValueError:
        return CliParseResult(
          kind: cliParseError,
          msg: "Invalid number for option --" & k & ": " & v,
        )
  pr
