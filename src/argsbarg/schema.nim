import std/[options, strutils, tables]

## Name of the bash completion subcommand injected under `completion`.
const CliBuiltinCompletionBashName* = "bash"

## Name of the completion command injected for every application.
const CliBuiltinCompletionName* = "completion"

## Name of the zsh completion subcommand injected under `completion`.
const CliBuiltinCompletionZshName* = "zsh"

## Long help flag token.
const CliHelpLongFlag* = "--help"

## Short help flag token.
const CliHelpShortFlag* = "-h"

## Marker for options that do not declare a short alias.
const CliNoShortName* = '\0'

## Long flag for printing the zsh completion script to stdout instead of installing it.
const CliPrintLongFlag* = "--print"

## Supported option value kinds for schema validation and help rendering.
type CliValueKind* = enum
  cliValueNone
  cliValueNumber
  cliValueString

## Discriminator for parse outcomes used by `cliParse`.
type CliParseKind* = enum
  cliParseError
  cliParseHelp
  cliParseOk

## Parsed argv values and metadata passed to command handlers.
type CliContext* = object
  appName*: string
  args*: seq[string]
  command*: seq[string]
  opts*: Table[string, string]

## Handler invoked when a leaf command is selected.
type CliHandler* = proc(ctx: CliContext) {.nimcall.}

## Declares a single option or positional argument on a command or the application root.
## Omitted `isPositional` / `isRepeated` default to false; `shortName` defaults to `CliNoShortName`.
type CliOption* = object
  description*: string
  isPositional*: bool = false
  isRepeated*: bool = false
  kind*: CliValueKind
  shortName*: char = CliNoShortName
  name*: string

## Declares a command or nested subcommand and optional handler.
## Omitted `arguments`, `commands`, and `options` default to empty sequences.
type CliCommand* = object
  arguments*: seq[CliOption] = @[]
  commands*: seq[CliCommand] = @[]
  description*: string
  handler*: Option[CliHandler]
  name*: string
  options*: seq[CliOption] = @[]

## Controls when ``CliSchema.fallbackCommand`` is applied at the app root.
type CliFallbackMode* = enum
  ## Pick ``fallbackCommand`` only when the user never typed a top-level command word (after any
  ## root flags). If you leave ``fallbackCommand`` unset, an empty argv still shows normal root
  ## help—this value is for apps that want ``myapp`` alone to run one subcommand without changing
  ## ``myapp -h`` or ``myapp othercmd``.
  cliFallbackWhenMissing
  ## Same as ``cliFallbackWhenMissing``, and also: if the next word is not a known top-level
  ## command, behave as if ``fallbackCommand`` were written first. Use this for tools where users
  ## often pass flags or paths before the verb. Real subcommand names (including ``completion``)
  ## always win over the fallback.
  cliFallbackWhenMissingOrUnknown
  ## Never pick ``fallbackCommand`` on an empty invocation: root help still prints. If the first
  ## command-level token exists but is not a known top-level command, route like
  ## ``cliFallbackWhenMissingOrUnknown``. For ``myapp`` vs ``myapp ./file`` (implicit ``read``).
  cliFallbackWhenUnknown

## Declares the full CLI surface for an application.
## Omitted ``options`` defaults to an empty sequence. ``fallbackCommand`` defaults to unset
## (``none``); ``fallbackMode`` defaults to ``cliFallbackWhenMissing``.
type CliSchema* = object
  commands*: seq[CliCommand]
  description*: string
  ## Optional top-level command name. When routing rules say to use it, that command runs instead
  ## of stopping at the app root. Must match a child of ``commands``. Leave unset if ``app`` with
  ## no args should print the usual root help listing every command.
  fallbackCommand*: Option[string] = none(string)
  ## See ``CliFallbackMode``. ``cliFallbackWhenMissingOrUnknown`` and ``cliFallbackWhenUnknown``
  ## require ``fallbackCommand`` to be set.
  fallbackMode*: CliFallbackMode = cliFallbackWhenMissing
  name*: string
  options*: seq[CliOption] = @[]

## Structured parse outcome including help and error branches.
type CliParseResult* = object
  case kind*: CliParseKind
  of cliParseError:
    msg*: string
  of cliParseHelp:
    helpPath*: seq[string]
  of cliParseOk:
    args*: seq[string]
    opts*: Table[string, string]
    path*: seq[string]

## Builds a routing command with child subcommands and no dispatch handler.
proc cliGroup*(
    name, description: string;
    commands: seq[CliCommand];
    options: seq[CliOption] = @[],
): CliCommand =
  CliCommand(
    commands: commands,
    description: description,
    handler: none(CliHandler),
    name: name,
    options: options,
  )


## Builds a leaf command with a required handler and optional flags or positionals.
proc cliLeaf*(
    name, description: string;
    handler: CliHandler;
    arguments: seq[CliOption] = @[];
    options: seq[CliOption] = @[],
): CliCommand =
  CliCommand(
    arguments: arguments,
    description: description,
    handler: some(handler),
    name: name,
    options: options,
  )


## Builds a presence-only flag definition (`cliValueNone`).
proc cliOptFlag*(name, description: string; shortName: char = CliNoShortName): CliOption =
  CliOption(description: description, kind: cliValueNone, name: name, shortName: shortName)


## Builds a floating-valued flag definition (`cliValueNumber`).
proc cliOptNumber*(name, description: string; shortName: char = CliNoShortName): CliOption =
  CliOption(description: description, kind: cliValueNumber, name: name, shortName: shortName)


## Builds a string positional slot (`cliValueString`, `isPositional` true).
proc cliOptPositional*(name, description: string; isRepeated: bool = false): CliOption =
  CliOption(
    description: description,
    isPositional: true,
    isRepeated: isRepeated,
    kind: cliValueString,
    name: name,
  )


## Builds a string-valued flag definition (`cliValueString`).
proc cliOptString*(name, description: string; shortName: char = CliNoShortName): CliOption =
  CliOption(description: description, kind: cliValueString, name: name, shortName: shortName)


## Returns whether a presence-only option was supplied on the context.
proc optFlag*(ctx: CliContext; name: string): bool {.inline.} =
  name in ctx.opts


## Returns a coerced floating option value when present and parseable.
proc optNumber*(ctx: CliContext; name: string): Option[float] =
  if name notin ctx.opts:
    return none(float)
  let raw = ctx.opts[name]
  try:
    result = some(parseFloat(raw))
  except ValueError:
    result = none(float)


## Returns a string option value when the key exists on the context.
proc optString*(ctx: CliContext; name: string): Option[string] =
  if name notin ctx.opts:
    return none(string)
  result = some(ctx.opts[name])
