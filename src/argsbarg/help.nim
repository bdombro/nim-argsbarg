import std/[algorithm, options, strutils]
import schema
import style

## Renders help text for the given path using the merged schema.
proc cliHelpRender*(schema: CliSchema; helpPath: seq[string]): string =
  ## Resolves a direct child command by name from `cmds`.
  proc findChild(cmds: seq[CliCommand]; name: string): Option[CliCommand] =
    for c in cmds:
      if c.name == name:
        return some(c)
    none(CliCommand)


  ## Maps option value kinds to placeholder labels shown in help tables.
  proc optKindLabel(k: CliValueKind): string =
    case k
    of cliValueNone:
      ""
    of cliValueNumber:
      "<number>"
    of cliValueString:
      "<string>"


  ## Builds help lines for non-positional flags on the current scope.
  proc linesForOptions(defs: seq[CliOption]): seq[string] =
    var outl: seq[string] = @[]
    outl.add styleBold("Options:") & "\n"
    outl.add "  " & styleDim(CliHelpShortFlag & ", " & CliHelpLongFlag) &
      "                 Show help for this command.\n"
    for o in defs:
      if o.isPositional:
        continue
      let lab = optKindLabel(o.kind)
      let baseFlag =
        if o.shortName != CliNoShortName:
          "-" & $o.shortName & ", --" & o.name
        else:
          "--" & o.name
      let flag =
        if o.kind == cliValueNone:
          baseFlag
        else:
          baseFlag & " " & lab
      let pad = spaces(max(1, 26 - flag.len))
      outl.add "  " & styleCyan(flag) & pad & styleDim(o.description) & "\n"
    return outl


  ## Builds help lines for positional arguments on the current scope.
  proc linesForPositionals(defs: seq[CliOption]): seq[string] =
    var pos: seq[CliOption] = @[]
    for o in defs:
      if o.isPositional:
        pos.add o
    if pos.len == 0:
      return @[]
    var outl: seq[string] = @[]
    outl.add styleBold("Arguments:") & "\n"
    for o in pos:
      let lab = optKindLabel(o.kind)
      let name = o.name & " " & lab
      let pad = spaces(max(1, 26 - name.len))
      outl.add "  " & styleCyan(name) & pad & styleDim(o.description) & "\n"
    return outl


  ## Builds help lines for subcommands sorted by name.
  proc linesForSubcommands(cmds: seq[CliCommand]; title: string): seq[string] =
    if cmds.len == 0:
      return @[]
    var outl: seq[string] = @[]
    outl.add styleBold(title & ":") & "\n"
    var sorted = cmds
    sorted.sort(proc(a, b: CliCommand): int = cmp(a.name, b.name))
    for c in sorted:
      let pad = spaces(max(1, 28 - c.name.len))
      outl.add "  " & styleCyan(c.name) & pad & styleDim(c.description) & "\n"
    return outl

  if helpPath.len == 0:
    var buf = styleBold(schema.name) & "\n" & schema.description & "\n\n"
    buf.add styleBold("Usage:") & "\n"
    buf.add "  " & schema.name & " <command> [options]\n"
    buf.add "  " & schema.name & " " & CliBuiltinCompletionsZshName & "\n\n"
    for ln in linesForOptions(schema.options):
      buf.add ln
    buf.add "\n"
    for ln in linesForSubcommands(schema.commands, "Commands"):
      buf.add ln
    return buf

  var cmds = schema.commands
  var node: CliCommand
  for seg in helpPath:
    let ch = findChild(cmds, seg)
    if ch.isNone:
      return styleRed("Unknown help path.") & "\n"
    node = ch.get
    cmds = node.commands

  var buf = styleBold(schema.name & " " & helpPath.join(" ")) & "\n"
  buf.add node.description & "\n\n"
  buf.add styleBold("Usage:") & "\n"
  buf.add "  " & schema.name & " " & helpPath.join(" ") & " [options]\n"
  if node.commands.len > 0:
    buf.add "  " & schema.name & " " & helpPath.join(" ") & " <command> [options]\n"
  buf.add "\n"
  for ln in linesForOptions(node.options):
    buf.add ln
  buf.add "\n"
  let posLines = linesForPositionals(node.arguments)
  for ln in posLines:
    buf.add ln
  if posLines.len > 0:
    buf.add "\n"
  for ln in linesForSubcommands(node.commands, "Subcommands"):
    buf.add ln
  buf


## Builds a string of `n` ASCII spaces for column padding in help output.
proc spaces(n: int): string =
  result = newStringOfCap(n)
  for i in 0 ..< n:
    result.add ' '
