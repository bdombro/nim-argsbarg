import std/[options, strutils, tables, unittest]
import argsbarg

suite "cliParse":
  proc makeLeafSchema(): CliSchema =
    CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          options = @[
            cliOptFlag("verbose", "Enable verbose logging.", 'v'),
            cliOptString("format", "Choose an output format.", 'f'),
            cliOptFlag("alpha", "Bundle test boolean A.", 'a'),
            cliOptFlag("beta", "Bundle test boolean B.", 'b'),
            cliOptFlag("gamma", "Bundle test boolean C.", 'c'),
          ],
        ),
      ],
      defaultCommand: none(string),
      description: "Test app.",
      name: "tapp",
      options: @[],
    )

  test "empty argv yields root help when no defaultCommand":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "noop",
          "Do nothing.",
          proc(ctx: CliContext) {.nimcall.} = discard,
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
        cliLeaf(
          "noop",
          "Do nothing.",
          proc(ctx: CliContext) {.nimcall.} = discard,
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

  test "boolean long option is recorded as presence":
    let m = cliMergeBuiltins(makeLeafSchema())
    let pr = cliParse(m, @["run", "--verbose"])
    check pr.kind == cliParseOk
    check pr.opts["verbose"] == "1"

  test "short boolean option resolves to long name":
    let m = cliMergeBuiltins(makeLeafSchema())
    let pr = cliParse(m, @["run", "-v"])
    check pr.kind == cliParseOk
    check pr.opts["verbose"] == "1"

  test "short valued option consumes next argv item":
    let m = cliMergeBuiltins(makeLeafSchema())
    let pr = cliParse(m, @["run", "-f", "json"])
    check pr.kind == cliParseOk
    check pr.opts["format"] == "json"

  test "bundled short booleans are accepted":
    let m = cliMergeBuiltins(makeLeafSchema())
    let pr = cliParse(m, @["run", "-abc"])
    check pr.kind == cliParseOk
    check pr.opts["alpha"] == "1"
    check pr.opts["beta"] == "1"
    check pr.opts["gamma"] == "1"

  test "help output shows short aliases":
    let m = cliMergeBuiltins(makeLeafSchema())
    let rendered = cliHelpRender(m, @["run"])
    check rendered.contains("-v, --verbose")
