import std/[os, options]
import argsbarg

## Prints a yellow notice that `path` was not found on disk.
proc missingPathLine(path: string) =
  echo styleYellow("missing: ") & path

## Prints file contents for the path in `ctx.args`.
proc readHandler(ctx: CliContext) =
  let path = ctx.args[0]
  if not fileExists(path):
    cliErrWithHelp(ctx.schema, ctx.command, "read: not found: " & path)
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
  let path = ctx.args[0]
  let content = ctx.optString("content").get("")
  writeFile(path, content)
  echo styleGreen("wrote: ") & path

## Runs the demo CLI. Empty argv shows app-wide help; a bare path (first token is not a known
## command) runs ``read`` on that path; ``stat``, ``rm``, and the rest stay explicit.
when isMainModule:
  cliRun(
    CliSchema(
      commands: @[
        cliLeaf("rm", "Remove files.", rmHandler),
        cliLeaf(
          "read",
          "Print file contents.",
          readHandler,
          arguments = @[
            cliArg("path", "File to read."),
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
                    cliArgList("files", "One or more file paths.", min = 1),
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
            cliArgList("paths", "Paths to touch.", min = 1),
          ],
        ),
        cliLeaf(
          "write",
          "Write content to a file.",
          writeHandler,
          arguments = @[
            cliArg("path", "File to write."),
          ],
          options = @[
            cliOptString("content", "Content to write."),
          ],
        ),
      ],
      description:
        "Small file utilities: read, write, touch, rm, nested stat; bare paths use read.",
      fallbackCommand: some("read"),
      fallbackMode: cliFallbackWhenUnknown,
      name: "nim_file",
      options: @[
        cliOptString("color-mode", "Select the output color mode example value."),
      ],
    ),
    commandLineParams(),
  )
