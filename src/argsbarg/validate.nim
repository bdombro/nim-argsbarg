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

  ## Validates positional arity ordering and bounds within one command scope.
  proc checkArguments(defs: seq[CliOption]; scope: string) =
    var pos: seq[CliOption] = @[]
    for d in defs:
      if d.isPositional:
        pos.add d
    for idx, d in pos:
      if d.argMin < 0:
        raise ArgsbargSchemaDefect.newException(
          "argMin must be >= 0 for positional " & scope & "/" & d.name)
      if d.argMax < 0:
        raise ArgsbargSchemaDefect.newException(
          "argMax must be >= 0 (use 0 for unlimited) for positional " & scope & "/" & d.name)
      if d.argMax > 0 and d.argMin > d.argMax:
        raise ArgsbargSchemaDefect.newException(
          "argMin must not exceed argMax for positional " & scope & "/" & d.name)
      if idx + 1 < pos.len and d.argMax == 0:
        raise ArgsbargSchemaDefect.newException(
          "Unlimited positional (argMax == 0) must be last in scope " & scope)
    var sawOptional = false
    for d in pos:
      if d.argMin == 0:
        sawOptional = true
      elif sawOptional:
        raise ArgsbargSchemaDefect.newException(
          "Required positional after optional in scope " & scope)

  ## Recursively checks routing vs leaf command handler rules.
  proc walk(cmd: CliCommand) =
    if cmd.commands.len > 0:
      if cmd.handler.isSome:
        raise ArgsbargSchemaDefect.newException(
          "Routing command must not set handler: " & cmd.name)
    else:
      if cmd.handler.isNone:
        raise ArgsbargSchemaDefect.newException(
          "Leaf command requires handler: " & cmd.name)
    checkOptions(cmd.options, cmd.name)
    checkArguments(cmd.arguments, cmd.name)
    checkOptions(cmd.arguments, cmd.name)
    if cmd.commands.len > 0:
      for ch in cmd.commands:
        walk(ch)

  for c in schema.commands:
    walk(c)


## Validates option value shapes for a successful parse result.
proc cliValidate*(schema: CliSchema; pr: CliParseResult): CliParseResult =
  if pr.kind != cliParseOk:
    return pr

  var defs: seq[CliOption] = @[]
  defs.add schema.options
  var cmds = schema.commands
  for seg in pr.path:
    let ch = findChild(cmds, seg)
    if ch.isNone:
      return CliParseResult(
        kind: cliParseError, errorHelpPath: pr.path, msg: "Internal path error")
    defs.add ch.get.options
    defs.add ch.get.arguments
    cmds = ch.get.commands

  for k, v in pr.opts.pairs:
    let d = findOptionByName(defs, k)
    if d.isNone:
      return CliParseResult(
        kind: cliParseError, errorHelpPath: pr.path, msg: "Unknown option key: " & k)
    if d.get.kind == cliValueNumber:
      try:
        discard parseFloat(v)
      except ValueError:
        return CliParseResult(
          kind: cliParseError,
          errorHelpPath: pr.path,
          msg: "Invalid number for option --" & k & ": " & v,
        )
  pr
