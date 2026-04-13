import std/[options, strutils, tables]

## Name of the zsh completion install command injected for every application.
const CliBuiltinCompletionsZshName* = "completions-zsh"

## Long help flag token.
const CliHelpLongFlag* = "--help"

## Short help flag token.
const CliHelpShortFlag* = "-h"

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
type CliOption* = object
  description*: string
  isPositional*: bool
  isRepeated*: bool
  kind*: CliValueKind
  name*: string

## Declares a command or nested subcommand and optional handler.
type CliCommand* = object
  arguments*: seq[CliOption]
  commands*: seq[CliCommand]
  description*: string
  handler*: Option[CliHandler]
  name*: string
  options*: seq[CliOption]

## Declares the full CLI surface for an application.
type CliSchema* = object
  commands*: seq[CliCommand]
  defaultCommand*: Option[string]
  description*: string
  name*: string
  options*: seq[CliOption]

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
