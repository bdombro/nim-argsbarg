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
      description: "Test app.",
      name: "tapp",
      options: @[],
    )

  test "empty argv yields root help when no fallbackCommand":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "noop",
          "Do nothing.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      name: "tapp",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[])
    check pr.kind == cliParseHelp
    check pr.helpPath.len == 0

  test "fallbackCommand selects without consuming argv":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "noop",
          "Do nothing.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("noop"),
      name: "tapp2",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[])
    check pr.kind == cliParseOk
    check pr.path == @["noop"]

  test "cliFallbackWhenMissingOrUnknown routes leading flags to fallback command":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          options = @[
            cliOptFlag("verbose", "Verbose.", 'v'),
          ],
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("run"),
      fallbackMode: cliFallbackWhenMissingOrUnknown,
      name: "tappImplicit",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @["-v"])
    check pr.kind == cliParseOk
    check pr.path == @["run"]
    check pr.opts["verbose"] == "1"

  test "cliFallbackWhenMissingOrUnknown routes unknown token as fallback command arg":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[
            cliOptPositional("path", "Input path."),
          ],
        ),
        cliLeaf(
          "other",
          "Other command.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("run"),
      fallbackMode: cliFallbackWhenMissingOrUnknown,
      name: "tappImplicit2",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @["file.txt"])
    check pr.kind == cliParseOk
    check pr.path == @["run"]
    check pr.args == @["file.txt"]

  test "cliFallbackWhenMissingOrUnknown does not shadow a sibling command name":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
        cliLeaf(
          "other",
          "Other command.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("run"),
      fallbackMode: cliFallbackWhenMissingOrUnknown,
      name: "tappImplicit3",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @["other"])
    check pr.kind == cliParseOk
    check pr.path == @["other"]

  test "cliFallbackWhenMissingOrUnknown still dispatches completions-zsh":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("run"),
      fallbackMode: cliFallbackWhenMissingOrUnknown,
      name: "tappImplicit4",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[CliBuiltinCompletionsZshName])
    check pr.kind == cliParseOk
    check pr.path == @[CliBuiltinCompletionsZshName]

  test "cliFallbackWhenMissingOrUnknown consumes known root flags before fallback command":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[
            cliOptPositional("path", "Input path."),
          ],
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("run"),
      fallbackMode: cliFallbackWhenMissingOrUnknown,
      name: "tappImplicit5",
      options: @[
        cliOptString("mode", "Output mode."),
      ],
    )
    let pr = cliParse(s, @["--mode", "json", "file.txt"])
    check pr.kind == cliParseOk
    check pr.path == @["run"]
    check pr.opts["mode"] == "json"
    check pr.args == @["file.txt"]

  test "cliFallbackWhenUnknown yields root help on empty argv":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "read",
          "Read a file.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[
            cliOptPositional("path", "Path."),
          ],
        ),
        cliLeaf(
          "stat",
          "Stat.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("read"),
      fallbackMode: cliFallbackWhenUnknown,
      name: "tappUnknownEmpty",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[])
    check pr.kind == cliParseHelp
    check pr.helpPath.len == 0

  test "cliFallbackWhenUnknown routes unknown top-level token to fallback command":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "read",
          "Read a file.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[
            cliOptPositional("path", "Path."),
          ],
        ),
        cliLeaf(
          "stat",
          "Stat.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("read"),
      fallbackMode: cliFallbackWhenUnknown,
      name: "tappUnknownPath",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @["secret.txt"])
    check pr.kind == cliParseOk
    check pr.path == @["read"]
    check pr.args == @["secret.txt"]

  test "cliFallbackWhenUnknown still dispatches completions-zsh":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      fallbackCommand: some("run"),
      fallbackMode: cliFallbackWhenUnknown,
      name: "tappUnknownZsh",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[CliBuiltinCompletionsZshName])
    check pr.kind == cliParseOk
    check pr.path == @[CliBuiltinCompletionsZshName]

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
