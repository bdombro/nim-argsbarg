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
    cliLeaf("rm", "Remove files.", rmHandler),
    cliLeaf(
      "read",
      "Print file contents.",
      readHandler,
      arguments = @[
        cliOptPositional("path", "File to read."),
      ],
    ),
    cliGroup(
      "stat",
      "File metadata and nested ownership inspection.",
      commands = @[
        cliGroup(
          "owner",
          "Inspect owner-related metadata.",
          commands = @[
            cliLeaf(
              "lookup",
              "Look up owner details for the selected files.",
              statOwnerLookupHandler,
              arguments = @[
                cliOptPositional("files", "One or more file paths.", isRepeated = true),
              ],
              options = @[
                cliOptString("user-name", "Filter by an explicit user name."),
              ],
            ),
          ],
          options = @[
            cliOptNumber("numeric", "Resolve the owner id numerically."),
          ],
        ),
      ],
      options = @[
        cliOptString("format", "Choose the output format (color,json)."),
      ],
    ),
    cliLeaf(
      "touch",
      "Create or update file timestamps.",
      touchHandler,
      arguments = @[
        cliOptPositional("paths", "Paths to touch.", isRepeated = true),
      ],
    ),
    cliLeaf(
      "write",
      "Write content to a file.",
      writeHandler,
      arguments = @[
        cliOptPositional("path", "File to write."),
      ],
      options = @[
        cliOptString("content", "Content to write."),
      ],
    ),
  ],
  description: "Small file utilities from the command line.",
  name: "nim_file",
  options: @[
    cliOptString("color-mode", "Select the output color mode example value."),
  ],
)

## Entry point when this file is compiled as the main module.
when isMainModule:
  cliRun(appSchema, commandLineParams())
