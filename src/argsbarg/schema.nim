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

## Command-line schema types (single ``type`` section so ``CliContext.schema`` and
## ``CliCommand`` / ``CliSchema`` stay mutually recursive).
type
  ## Declares a single option or positional argument on a command or the application root.
  ## For positionals, ``argMin`` / ``argMax`` bound how many argv words map into ``ctx.args`` for
  ## that slot (``argMax == 0`` means unlimited). For flags, ``argMin`` / ``argMax`` are ignored.
  ## Omitted ``isPositional`` defaults to false; ``shortName`` defaults to ``CliNoShortName``.
  CliOption* = object
    argMax*: int = 1
    argMin*: int = 1
    description*: string
    isPositional*: bool = false
    kind*: CliValueKind
    name*: string
    shortName*: char = CliNoShortName

  ## Controls when ``CliSchema.fallbackCommand`` is applied at the app root.
  CliFallbackMode* = enum
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

  ## Parsed argv values and metadata passed to command handlers.
  CliContext* = object
    appName*: string
    args*: seq[string]
    command*: seq[string]
    opts*: Table[string, string]
    ## Merged schema including builtins; use with ``cliErrWithHelp`` and ``cliHelpRender``.
    schema*: CliSchema

  ## Handler invoked when a leaf command is selected.
  CliHandler* = proc(ctx: CliContext) {.nimcall.}

  ## Declares a command or nested subcommand and optional handler.
  ## Omitted `arguments`, `commands`, `notes`, and `options` default to empty sequences / strings.
  CliCommand* = object
    arguments*: seq[CliOption] = @[]
    commands*: seq[CliCommand] = @[]
    description*: string
    handler*: Option[CliHandler]
    name*: string
    ## Optional long-form text shown at the bottom of this command's help output.
    ## Use ``{app}`` as a placeholder for the application name; it is substituted at render time.
    notes*: string = ""
    options*: seq[CliOption] = @[]

  ## Declares the full CLI surface for an application.
  ## Omitted ``options`` defaults to an empty sequence. ``fallbackCommand`` defaults to unset
  ## (``none``); ``fallbackMode`` defaults to ``cliFallbackWhenMissing``.
  CliSchema* = object
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

## Structured parse outcome including help and error branches. On ``cliParseHelp``,
## ``helpExplicit`` is true when the user passed ``-h`` / ``--help`` (``cliRun`` exits 0); false
## for implicit help (``cliRun`` exits 1). On ``cliParseError``, ``errorHelpPath`` is the command
## prefix for ``cliHelpRender`` (distinct field name from ``helpPath``; Nim disallows reuse
## across variant branches).
type CliParseResult* = object
  case kind*: CliParseKind
  of cliParseError:
    errorHelpPath*: seq[string]
    msg*: string
  of cliParseHelp:
    ## True when ``-h`` / ``--help`` triggered this help result (not implicit routing / empty argv).
    helpExplicit*: bool
    helpPath*: seq[string]
  of cliParseOk:
    args*: seq[string]
    opts*: Table[string, string]
    path*: seq[string]

## Builds a single-word positional slot (``argMax`` is always ``1``).
proc cliArg*(name, description: string; optional: bool = false): CliOption =
  CliOption(
    argMax: 1,
    argMin: if optional: 0 else: 1,
    description: description,
    isPositional: true,
    kind: cliValueString,
    name: name,
  )


## Builds a positional tail that collects ``min``..``max`` argv words into ``ctx.args``.
## Pass ``max = 0`` for no upper limit (only as the last positional on a command).
proc cliArgList*(name, description: string; min: int = 0; max: int = 0): CliOption =
  CliOption(
    argMax: max,
    argMin: min,
    description: description,
    isPositional: true,
    kind: cliValueString,
    name: name,
  )


## Builds a routing command with child subcommands and no dispatch handler.
## Optional ``notes`` is long-form text for ``-h`` on this node; ``{app}`` expands to the app name.
proc cliGroup*(
    name, description: string;
    commands: seq[CliCommand];
    options: seq[CliOption] = @[];
    notes: string = "",
): CliCommand =
  CliCommand(
    commands: commands,
    description: description,
    handler: none(CliHandler),
    name: name,
    notes: notes,
    options: options,
  )


## Builds a leaf command with a required handler and optional flags or positionals.
## Optional ``notes`` is long-form text for ``-h`` on this leaf; ``{app}`` expands to the app name.
proc cliLeaf*(
    name, description: string;
    handler: CliHandler;
    arguments: seq[CliOption] = @[];
    options: seq[CliOption] = @[];
    notes: string = "",
): CliCommand =
  CliCommand(
    arguments: arguments,
    description: description,
    handler: some(handler),
    name: name,
    notes: notes,
    options: options,
  )


## Builds a presence-only flag definition (`cliValueNone`).
proc cliOptFlag*(name, description: string; shortName: char = CliNoShortName): CliOption =
  CliOption(description: description, kind: cliValueNone, name: name, shortName: shortName)


## Builds a floating-valued flag definition (`cliValueNumber`).
proc cliOptNumber*(name, description: string; shortName: char = CliNoShortName): CliOption =
  CliOption(description: description, kind: cliValueNumber, name: name, shortName: shortName)


## Builds a string-valued flag definition (`cliValueString`).
proc cliOptString*(name, description: string; shortName: char = CliNoShortName): CliOption =
  CliOption(description: description, kind: cliValueString, name: name, shortName: shortName)


## Resolves a direct child command by name from `cmds`.
proc findChild*(cmds: seq[CliCommand]; name: string): Option[CliCommand] =
  for c in cmds:
    if c.name == name:
      return some(c)
  none(CliCommand)


## Looks up an option definition by long name within `defs` (first match wins).
proc findOptionByName*(defs: seq[CliOption]; name: string): Option[CliOption] =
  for o in defs:
    if o.name == name:
      return some(o)
  none(CliOption)


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
