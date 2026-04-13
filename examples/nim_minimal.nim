import std/[os, options]
import argsbarg

## Default greeting name when `--name` is omitted.
const helloNameDefault = "world"

proc helloHandler(ctx: CliContext)

## Schema for the `nim_minimal` example (single `hello` command).
let appSchema = CliSchema(
  commands: @[
    CliCommand(
      arguments: @[],
      commands: @[],
      description: "Print a greeting.",
      handler: some(helloHandler),
      name: "hello",
      options: @[
        CliOption(
          description: "Name to greet.",
          isPositional: false,
          isRepeated: false,
          kind: cliValueString,
          name: "name",
        ),
      ],
    ),
  ],
  defaultCommand: none(string),
  description: "Minimal argsbarg example.",
  name: "nim_minimal",
  options: @[],
)

## Prints a greeting using the optional `--name` value.
proc helloHandler(ctx: CliContext) =
  let nameOpt = ctx.optString("name")
  let name =
    if nameOpt.isSome:
      nameOpt.get
    else:
      helloNameDefault
  echo styleGreen("hello"), " ", name

## Entry point when this file is compiled as the main module.
when isMainModule:
  cliRun(appSchema, commandLineParams())
