import std/[os, options]
import argsbarg

## Non-zero exit status for handler validation failures.
const cliExitErr = 1

## Prints a yellow notice that `path` was not found on disk.
proc missingPathLine(path: string) =
  echo styleYellow("missing: ") & path

## Prints `msg` to stderr and exits with `cliExitErr`.
proc quitErr(msg: string) =
  stderr.writeLine styleRed(msg)
  quit(cliExitErr)

## Prints file contents for the path in `ctx.args`.
proc readHandler(ctx: CliContext) =
  if ctx.args.len == 0:
    quitErr("read: missing path")
  let path = ctx.args[0]
  if not fileExists(path):
    quitErr("read: not found: " & path)
  stdout.write readFile(path)

## Removes each path listed in `ctx.args`.
proc rmHandler(ctx: CliContext) =
  for path in ctx.args:
    if fileExists(path):
      removeFile(path)
      echo styleGreen("removed: ") & path
    else:
      missingPathLine(path)

## Prints owner lookup demo output for the resolved paths.
proc statOwnerLookupHandler(ctx: CliContext) =
  let userName = ctx.optString("user-name")
  let numeric = ctx.optNumber("numeric")
  for path in ctx.args:
    if not fileExists(path):
      missingPathLine(path)
      continue
    let info = getFileInfo(path, followSymlink = true)
    echo styleCyan("file: ") & path
    if userName.isSome:
      echo styleDim("  filter user: ") & userName.get
    if numeric.isSome:
      echo styleDim("  numeric hint: ") & $numeric.get
    echo styleDim("  size: ") & $info.size

## Creates empty files or updates timestamps for each path in `ctx.args`.
proc touchHandler(ctx: CliContext) =
  for path in ctx.args:
    writeFile(path, "")
    echo styleGreen("touched: ") & path

## Writes `content` to the first path in `ctx.args`.
proc writeHandler(ctx: CliContext) =
  if ctx.args.len == 0:
    quitErr("write: missing path")
  let path = ctx.args[0]
  let content = ctx.optString("content").get("")
  writeFile(path, content)
  echo styleGreen("wrote: ") & path

## Root CLI schema for the `nim_file` example binary.
let appSchema = CliSchema(
  commands: @[
    CliCommand(
      arguments: @[],
      commands: @[],
      description: "Remove files.",
      handler: some(rmHandler),
      name: "rm",
      options: @[],
    ),
    CliCommand(
      arguments: @[
        CliOption(
          description: "File to read.",
          isPositional: true,
          isRepeated: false,
          kind: cliValueString,
          name: "path",
        ),
      ],
      commands: @[],
      description: "Print file contents.",
      handler: some(readHandler),
      name: "read",
      options: @[],
    ),
    CliCommand(
      arguments: @[],
      commands: @[
        CliCommand(
          arguments: @[],
          commands: @[
            CliCommand(
              arguments: @[
                CliOption(
                  description: "One or more file paths.",
                  isPositional: true,
                  isRepeated: true,
                  kind: cliValueString,
                  name: "files",
                ),
              ],
              commands: @[],
              description: "Look up owner details for the selected files.",
              handler: some(statOwnerLookupHandler),
              name: "lookup",
              options: @[
                CliOption(
                  description: "Filter by an explicit user name.",
                  isPositional: false,
                  isRepeated: false,
                  kind: cliValueString,
                  name: "user-name",
                ),
              ],
            ),
          ],
          description: "Inspect owner-related metadata.",
          handler: none(CliHandler),
          name: "owner",
          options: @[
            CliOption(
              description: "Resolve the owner id numerically.",
              isPositional: false,
              isRepeated: false,
              kind: cliValueNumber,
              name: "numeric",
            ),
          ],
        ),
      ],
      description: "File metadata and nested ownership inspection.",
      handler: none(CliHandler),
      name: "stat",
      options: @[
        CliOption(
          description: "Choose the output format (color,json).",
          isPositional: false,
          isRepeated: false,
          kind: cliValueString,
          name: "format",
        ),
      ],
    ),
    CliCommand(
      arguments: @[
        CliOption(
          description: "Paths to touch.",
          isPositional: true,
          isRepeated: true,
          kind: cliValueString,
          name: "paths",
        ),
      ],
      commands: @[],
      description: "Create or update file timestamps.",
      handler: some(touchHandler),
      name: "touch",
      options: @[],
    ),
    CliCommand(
      arguments: @[
        CliOption(
          description: "File to write.",
          isPositional: true,
          isRepeated: false,
          kind: cliValueString,
          name: "path",
        ),
      ],
      commands: @[],
      description: "Write content to a file.",
      handler: some(writeHandler),
      name: "write",
      options: @[
        CliOption(
          description: "Content to write.",
          isPositional: false,
          isRepeated: false,
          kind: cliValueString,
          name: "content",
        ),
      ],
    ),
  ],
  defaultCommand: none(string),
  description: "Small file utilities from the command line.",
  name: "nim_file",
  options: @[
    CliOption(
      description: "Select the output color mode example value.",
      isPositional: false,
      isRepeated: false,
      kind: cliValueString,
      name: "color-mode",
    ),
  ],
)

## Entry point when this file is compiled as the main module.
when isMainModule:
  cliRun(appSchema, commandLineParams())
