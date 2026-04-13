import std/[os, options]
import argsbarg

## Default greeting name when `--name` is omitted.
const helloNameDefault = "world"

## Prints a greeting using the optional `--name` value.
proc helloHandler(ctx: CliContext) =
  let nameOpt = ctx.optString("name")
  let name =
    if nameOpt.isSome:
      nameOpt.get
    else:
      helloNameDefault
  if ctx.optFlag("verbose"):
    echo "verbose mode enabled"
  echo styleGreen("hello"), " ", name
  

## Schema for the `nim_minimal` example (single `hello` command).
let appSchema = CliSchema(
  commands: @[
    CliCommand(
      description: "Print a greeting.",
      handler: some(helloHandler),
      name: "hello",
      options: @[
        CliOption(
          description: "Name to greet.",
          kind: cliValueString,
          name: "name",
          shortName: 'n',
        ),
        CliOption(
          description: "Print extra logging before the greeting.",
          kind: cliValueNone,
          name: "verbose",
          shortName: 'v',
        ),
      ],
    ),
  ],
  description: "Minimal argsbarg example.",
  name: "nim_minimal",
)

## Entry point when this file is compiled as the main module.
when isMainModule:
  cliRun(appSchema, commandLineParams())
