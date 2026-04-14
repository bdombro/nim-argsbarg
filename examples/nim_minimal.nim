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

## Entry point when this file is compiled as the main module. Uses root fallback so flags can
## appear before ``hello`` (see README: ``fallbackCommand`` / ``fallbackMode``).
when isMainModule:
  cliRun(
    CliSchema(
      commands: @[
        cliLeaf(
          "hello",
          "Print a greeting.",
          helloHandler,
          options = @[
            cliOptString("name", "Name to greet.", 'n'),
            cliOptFlag("verbose", "Print extra logging before the greeting.", 'v'),
          ],
        ),
      ],
      description: "Minimal argsbarg example.",
      fallbackCommand: some("hello"),
      fallbackMode: cliFallbackWhenMissingOrUnknown,
      name: "nim_minimal",
    ),
    commandLineParams(),
  )
