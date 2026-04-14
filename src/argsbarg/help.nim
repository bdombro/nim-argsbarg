import std/[algorithm, options, strutils, terminal, unicode]
import schema
import style

type HelpRow = object
  label: string
  description: string


## Returns the visible width of a string after stripping ANSI escape sequences.
proc visibleWidth(s: string): int =
  var i = 0
  while i < s.len:
    if s[i] == '\e' and i + 1 < s.len and s[i + 1] == '[':
      i += 2
      while i < s.len and s[i] != 'm':
        inc i
      if i < s.len:
        inc i
    else:
      inc result
      inc i, runeLenAt(s, i)


## Builds a string of a repeated substring.
proc repeatGlyph(glyph: string; n: int): string =
  result = newStringOfCap(max(0, n))
  for _ in 0 ..< max(0, n):
    result.add glyph


## Builds a string of `n` ASCII spaces for column padding in help output.
proc spaces(n: int): string =
  repeatGlyph(" ", n)


## Pads a string to the requested visible width.
proc padVisible(s: string; width: int): string =
  s & spaces(max(0, width - visibleWidth(s)))


## Chooses the terminal width used for help rendering.
proc helpWidth(): int =
  max(40, terminalWidth())


## Wraps prose into lines that fit within the requested width.
proc wrapText(text: string; width: int): seq[string] =
  let available = max(1, width)
  let normalized = text.strip
  if normalized.len == 0:
    return @[""]

  for paragraph in normalized.split('\n'):
    let words = strutils.splitWhitespace(paragraph)
    if words.len == 0:
      result.add ""
      continue

    var line = words[0]
    for i in 1 ..< words.len:
      let word = words[i]
      if line.len + 1 + word.len <= available:
        line.add ' '
        line.add word
      else:
        result.add line
        line = word

      while line.len > available:
        result.add line[0 ..< available]
        line = line[available .. ^1]

    result.add line


## Maps option value kinds to placeholder labels shown in help tables.
proc optKindLabel(k: CliValueKind): string =
  case k
  of cliValueNone:
    ""
  of cliValueNumber:
    "<number>"
  of cliValueString:
    "<string>"


## Builds a help-table label for an option or positional argument.
proc optionLabel(o: CliOption): string =
  let kind = optKindLabel(o.kind)
  let kindPart = if kind.len == 0: "" else: " " & kind
  if o.isPositional:
    result = o.name & kindPart
    if o.isRepeated:
      result.add "..."
  else:
    result = "--" & o.name & kindPart
    if o.shortName != CliNoShortName:
      result.add ", -" & $o.shortName


## Styles an option label with aqua+bold for long option and neon green for short option.
proc styledOptionLabel(label: string): string =
  let parts = label.split(", ")
  if parts.len == 2:
    return styleAquaBold(parts[0] & ",") & " " & styleGreenBright(parts[1])
  else:
    return styleAquaBold(label)

## Builds the usage lines shown inside the Usage box.
proc usageLines(appName: string; helpPath: seq[string]; hasCommands: bool; hasArgs: bool): seq[string] =
  let fullPath =
    if helpPath.len == 0:
      appName
    else:
      appName & " " & helpPath.join(" ")
  let usageOptions = styleAquaBold("[OPTIONS]")
  let usageCommand = styleAquaBold("COMMAND")
  let usageArgs = styleAquaBold("[ARGS]...")

  if helpPath.len == 0:
    if hasCommands:
      result.add fullPath & " " & usageOptions & " " & usageCommand & " " & usageArgs
    else:
      result.add fullPath & " " & usageOptions
    return result

  result.add fullPath & " " & usageOptions & (if hasArgs: " " & usageArgs else: "")
  if hasCommands:
    result.add fullPath & " " & usageCommand & " " & usageArgs


## Builds help rows for non-positional flags on the current scope.
proc rowsForOptions(defs: seq[CliOption]): seq[HelpRow] =
  result.add HelpRow(label: "--help, -h", description: "Show help for this command.")
  for o in defs:
    if o.isPositional:
      continue
    result.add HelpRow(label: optionLabel(o), description: o.description)


## Builds help rows for positional arguments on the current scope.
proc rowsForPositionals(defs: seq[CliOption]): seq[HelpRow] =
  for o in defs:
    if o.isPositional:
      result.add HelpRow(label: optionLabel(o), description: o.description)


## Builds help rows for subcommands sorted by name.
proc rowsForSubcommands(cmds: seq[CliCommand]): seq[HelpRow] =
  var sorted = cmds
  sorted.sort(proc(a, b: CliCommand): int = cmp(a.name, b.name))
  for c in sorted:
    result.add HelpRow(label: c.name, description: c.description)


## Builds a section box with a title and plain body lines.
proc renderTextBox(title: string; lines: seq[string]): seq[string] =
  if lines.len == 0:
    return @[]

  let titleLead = styleGray("─ ") & styleBold(styleGray(title)) & styleGray(" ")
  var contentWidth = visibleWidth(titleLead) + 1
  for line in lines:
    contentWidth = max(contentWidth, visibleWidth(line))

  let borderWidth = contentWidth + 2
  let headerFill = max(1, borderWidth - visibleWidth(titleLead))
  result.add styleGray("╭") & titleLead & styleGray(repeatGlyph("─", headerFill) & "╮")
  for line in lines:
    result.add styleGray("│") & " " & padVisible(line, contentWidth) & " " & styleGray("│")
  result.add styleGray("╰" & repeatGlyph("─", borderWidth) & "╯")


## Builds a section box with a label/description table.
proc renderTableBox(title: string; rows: seq[HelpRow]): seq[string] =
  if rows.len == 0:
    return @[]

  var labelWidth = 0
  for row in rows:
    labelWidth = max(labelWidth, visibleWidth(row.label))

  let minimumContentWidth = max(visibleWidth("─ " & title & " ") + 1, labelWidth + 2 + 18)
  var contentWidth = max(helpWidth() - 2, minimumContentWidth)
  let descWidth = max(1, contentWidth - labelWidth - 2)

  var bodyLines: seq[string] = @[]
  for row in rows:
    let wrapped = wrapText(row.description, descWidth)
    let styledLabel = styledOptionLabel(row.label)
    let firstLine = styledLabel & spaces(labelWidth - visibleWidth(row.label)) &
      "  " & styleWhite(wrapped[0])
    bodyLines.add firstLine
    for idx in 1 ..< wrapped.len:
      bodyLines.add styleGray(spaces(labelWidth)) & "  " & styleWhite(wrapped[idx])

  let titleLead = styleGray("─ ") & styleBold(styleGray(title)) & styleGray(" ")
  contentWidth = max(contentWidth, visibleWidth(titleLead) + 1)
  for line in bodyLines:
    contentWidth = max(contentWidth, visibleWidth(line))
  contentWidth = min(contentWidth, helpWidth() - 4)

  let borderWidth = contentWidth + 2
  let headerFill = max(1, borderWidth - visibleWidth(titleLead))
  result.add styleGray("╭") & titleLead & styleGray(repeatGlyph("─", headerFill) & "╮")
  for line in bodyLines:
    result.add styleGray("│") & " " & padVisible(line, contentWidth) & " " & styleGray("│")
  result.add styleGray("╰" & repeatGlyph("─", borderWidth) & "╯")

## Renders help text for the given path using the merged schema.
proc cliHelpRender*(schema: CliSchema; helpPath: seq[string]): string =
  ## Resolves a direct child command by name from `cmds`.
  proc findChild(cmds: seq[CliCommand]; name: string): Option[CliCommand] =
    for c in cmds:
      if c.name == name:
        return some(c)
    none(CliCommand)
  if helpPath.len == 0:
    var lines: seq[string] = @[]
    lines.add ""
    if schema.description.len > 0:
      lines.add styleWhite(schema.description)
      lines.add ""
    lines.add renderTextBox("Usage", usageLines(schema.name, helpPath, schema.commands.len > 0, false)).join("\n")
    let optionBox = renderTableBox("Options", rowsForOptions(schema.options))
    if optionBox.len > 0:
      lines.add ""
      lines.add optionBox.join("\n")
    if schema.commands.len > 0:
      lines.add ""
      lines.add renderTableBox("Commands", rowsForSubcommands(schema.commands)).join("\n")
    return lines.join("\n") & "\n\n"

  var cmds = schema.commands
  var node: CliCommand
  for seg in helpPath:
    let ch = findChild(cmds, seg)
    if ch.isNone:
      return styleRed("Unknown help path.") & "\n"
    node = ch.get
    cmds = node.commands

  var lines: seq[string] = @[]
  lines.add ""
  lines.add renderTextBox("Usage", usageLines(schema.name, helpPath, node.commands.len > 0, node.arguments.len > 0)).join("\n")

  let optionBox = renderTableBox("Options", rowsForOptions(node.options))
  if optionBox.len > 0:
    lines.add ""
    lines.add optionBox.join("\n")

  let positionalBox = renderTableBox("Arguments", rowsForPositionals(node.arguments))
  if positionalBox.len > 0:
    lines.add ""
    lines.add positionalBox.join("\n")

  let subcommandBox = renderTableBox("Subcommands", rowsForSubcommands(node.commands))
  if subcommandBox.len > 0:
    lines.add ""
    lines.add subcommandBox.join("\n")

  lines.join("\n") & "\n\n"
