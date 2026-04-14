import std/options
import completion_zsh
import errors
import help
import parse
import schema
import style
import validate

## Looks up an immediate child command by name within `cmds`.
proc findChild(cmds: seq[CliCommand]; name: string): Option[CliCommand] =
  for c in cmds:
    if c.name == name:
      return some(c)
  none(CliCommand)


## Resolves the deepest command along `path` in `merged`, if every segment exists.
proc findLeaf(merged: CliSchema; path: seq[string]): Option[CliCommand] =
  var cmds = merged.commands
  var cur: Option[CliCommand] = none(CliCommand)
  for seg in path:
    let ch = findChild(cmds, seg)
    if ch.isNone:
      return none(CliCommand)
    cur = ch
    cmds = ch.get.commands
  cur


## Returns a merged schema including framework built-ins such as `completion zsh`.
proc cliMergeBuiltins*(schema: CliSchema): CliSchema =
  for c in schema.commands:
    if c.name == CliBuiltinCompletionName:
      raise ArgsbargSchemaDefect.newException(
        "Reserved command name: " & CliBuiltinCompletionName)
  result = schema
  result.commands.add completionZshBuiltinCommand()


## Parses argv, prints help or errors with default styling, and dispatches handlers.
proc cliRun*(schema: CliSchema; argv: seq[string]) =
  let merged = cliMergeBuiltins(schema)
  cliSchemaValidate(merged)
  var pr = cliParse(merged, argv)
  pr = cliValidate(merged, pr)
  case pr.kind
  of cliParseHelp:
    stdout.write(cliHelpRender(merged, pr.helpPath))
    quit(0)
  of cliParseError:
    stderr.writeLine(styleRed(pr.msg))
    quit(1)
  of cliParseOk:
    if pr.path.len == 2 and pr.path[0] == CliBuiltinCompletionName and pr.path[1] == CliBuiltinCompletionZshName:
      let ctx = CliContext(
        appName: merged.name,
        args: pr.args,
        command: pr.path,
        opts: pr.opts,
      )
      completionZshRun(merged, ctx)
      return
    let leafOpt = findLeaf(merged, pr.path)
    if leafOpt.isNone:
      stderr.writeLine(styleRed("Internal dispatch error."))
      quit(1)
    let leaf = leafOpt.get
    if leaf.handler.isNone:
      stderr.writeLine(styleRed("Internal dispatch error: missing handler."))
      quit(1)
    let ctx = CliContext(
      appName: merged.name,
      args: pr.args,
      command: pr.path,
      opts: pr.opts,
    )
    leaf.handler.get()(ctx)
