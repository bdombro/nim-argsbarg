import std/[options, syncio]
import completion_bash
import completion_zsh
import errors
import help
import parse
import schema
import style
import validate

## Builds the runtime context passed to command handlers and completion runners.
proc contextFor(merged: CliSchema; pr: CliParseResult): CliContext =
  CliContext(
    appName: merged.name,
    args: pr.args,
    command: pr.path,
    opts: pr.opts,
    schema: merged,
  )


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


## True when `pr` targets the injected `completion bash` leaf.
proc isBuiltinCompletionBash(pr: CliParseResult): bool {.inline.} =
  pr.path.len == 2 and pr.path[0] == CliBuiltinCompletionName and
    pr.path[1] == CliBuiltinCompletionBashName


## True when `pr` targets the injected `completion zsh` leaf.
proc isBuiltinCompletionZsh(pr: CliParseResult): bool {.inline.} =
  pr.path.len == 2 and pr.path[0] == CliBuiltinCompletionName and
    pr.path[1] == CliBuiltinCompletionZshName


## Prints ``msg`` in red, then the full help for ``helpPath``, then exits with status 1.
## Call from handlers when user input is invalid: pass ``ctx.schema`` and ``ctx.command``.
proc cliErrWithHelp*(schema: CliSchema; helpPath: seq[string]; msg: string) {.noreturn.} =
  stderr.writeLine(styleRed(msg))
  stderr.write(cliHelpRender(schema, helpPath))
  quit(1)


## Returns a merged schema including framework built-ins such as `completion zsh`.
proc cliMergeBuiltins*(schema: CliSchema): CliSchema =
  for c in schema.commands:
    if c.name == CliBuiltinCompletionName:
      raise ArgsbargSchemaDefect.newException(
        "Reserved command name: " & CliBuiltinCompletionName)
  result = schema
  result.commands.add cliGroup(
    CliBuiltinCompletionName,
    "Generate the autocompletion script for shells.",
    commands = @[
      completionBashBuiltinCommand(),
      completionZshBuiltinLeaf(),
    ],
  )


## Parses argv, prints help or errors with default styling, and dispatches handlers.
proc cliRun*(schema: CliSchema; argv: seq[string]) =
  let merged = cliMergeBuiltins(schema)
  cliSchemaValidate(merged)
  var pr = cliParse(merged, argv)
  pr = cliValidate(merged, pr)
  case pr.kind
  of cliParseHelp:
    stdout.write(cliHelpRender(merged, pr.helpPath))
    quit(if pr.helpExplicit: 0 else: 1)
  of cliParseError:
    stderr.writeLine(styleRed(pr.msg))
    stderr.write(cliHelpRender(merged, pr.errorHelpPath))
    quit(1)
  of cliParseOk:
    if isBuiltinCompletionBash(pr):
      completionBashRun(merged, contextFor(merged, pr))
      return
    if isBuiltinCompletionZsh(pr):
      completionZshRun(merged, contextFor(merged, pr))
      return
    let leafOpt = findLeaf(merged, pr.path)
    if leafOpt.isNone:
      stderr.writeLine(styleRed("Internal dispatch error."))
      quit(1)
    let leaf = leafOpt.get
    if leaf.handler.isNone:
      stderr.writeLine(styleRed("Internal dispatch error: missing handler."))
      quit(1)
    leaf.handler.get()(contextFor(merged, pr))
