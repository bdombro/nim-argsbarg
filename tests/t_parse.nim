import std/[options, unittest]
import argsbarg

suite "cliParse":
  test "empty argv yields root help when no defaultCommand":
    let s = CliSchema(
      commands: @[
        CliCommand(
          arguments: @[],
          commands: @[],
          description: "Do nothing.",
          handler: some(proc(ctx: CliContext) = discard),
          name: "noop",
          options: @[],
        ),
      ],
      defaultCommand: none(string),
      description: "Test app.",
      name: "tapp",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[])
    check pr.kind == cliParseHelp
    check pr.helpPath.len == 0

  test "defaultCommand selects without consuming argv":
    let s = CliSchema(
      commands: @[
        CliCommand(
          arguments: @[],
          commands: @[],
          description: "Do nothing.",
          handler: some(proc(ctx: CliContext) = discard),
          name: "noop",
          options: @[],
        ),
      ],
      defaultCommand: some("noop"),
      description: "Test app.",
      name: "tapp2",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[])
    check pr.kind == cliParseOk
    check pr.path == @["noop"]
