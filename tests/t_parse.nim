import std/[os, options, strutils, tables, unittest]
import argsbarg

## Helper to strip ANSI escape sequences from strings.
proc stripAnsi(s: string): string =
  var i = 0
  while i < s.len:
    if s[i] == '\e' and i + 1 < s.len and s[i + 1] == '[':
      i += 2
      while i < s.len and s[i] != 'm':
        inc i
      if i < s.len:
        inc i
    else:
      result.add s[i]
      inc i

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
    check pr.helpExplicit == false
    check pr.helpPath.len == 0

  test "explicit -h sets helpExplicit true":
    let m = cliMergeBuiltins(makeLeafSchema())
    let prRoot = cliParse(m, @["-h"])
    check prRoot.kind == cliParseHelp
    check prRoot.helpExplicit == true
    check prRoot.helpPath.len == 0
    let prCmd = cliParse(m, @["run", "-h"])
    check prCmd.kind == cliParseHelp
    check prCmd.helpExplicit == true
    check prCmd.helpPath == @["run"]

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
            cliArg("path", "Input path."),
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

  test "cliFallbackWhenMissingOrUnknown still dispatches completion bash":
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
      name: "tappImplicitBash",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[CliBuiltinCompletionName, CliBuiltinCompletionBashName])
    check pr.kind == cliParseOk
    check pr.path == @[CliBuiltinCompletionName, CliBuiltinCompletionBashName]

  test "cliFallbackWhenMissingOrUnknown still dispatches completion zsh":
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
    let pr = cliParse(m, @[CliBuiltinCompletionName, CliBuiltinCompletionZshName])
    check pr.kind == cliParseOk
    check pr.path == @[CliBuiltinCompletionName, CliBuiltinCompletionZshName]

  test "cliFallbackWhenMissingOrUnknown consumes known root flags before fallback command":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[
            cliArg("path", "Input path."),
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
            cliArg("path", "Path."),
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
    check pr.helpExplicit == false
    check pr.helpPath.len == 0

  test "cliFallbackWhenUnknown routes unknown top-level token to fallback command":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "read",
          "Read a file.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[
            cliArg("path", "Path."),
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

  test "cliFallbackWhenUnknown still dispatches completion bash":
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
      name: "tappUnknownBash",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @[CliBuiltinCompletionName, CliBuiltinCompletionBashName])
    check pr.kind == cliParseOk
    check pr.path == @[CliBuiltinCompletionName, CliBuiltinCompletionBashName]

  test "cliFallbackWhenUnknown still dispatches completion zsh":
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
    let pr = cliParse(m, @[CliBuiltinCompletionName, CliBuiltinCompletionZshName])
    check pr.kind == cliParseOk
    check pr.path == @[CliBuiltinCompletionName, CliBuiltinCompletionZshName]

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
    let cleanRendered = stripAnsi(rendered)
    check cleanRendered.contains("--verbose, -v")

  test "help output uses boxed sections and wraps descriptions":
    let oldColumns = getEnv("COLUMNS")
    putEnv("COLUMNS", "60")
    defer:
      if oldColumns.len == 0:
        delEnv("COLUMNS")
      else:
        putEnv("COLUMNS", oldColumns)

    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run the app with a command description that is intentionally long enough to wrap inside the commands box.",
          proc(ctx: CliContext) {.nimcall.} = discard,
        ),
      ],
      description: "Test app.",
      name: "tapp",
      options: @[
        cliOptFlag(
          "quiet",
          "Quiet mode with a description long enough to wrap inside the options box for this layout test.",
          'q',
        ),
      ],
    )

    let rendered = cliHelpRender(cliMergeBuiltins(s), @[])
    let cleanRendered = stripAnsi(rendered)
    let lines = rendered.splitLines()

    var usageHeaderFound = false
    var optionsHeaderFound = false
    var commandsHeaderFound = false
    for line in lines:
      let cleanLine = stripAnsi(line)
      if cleanLine.startsWith("╭") and cleanLine.contains("Usage"):
        usageHeaderFound = true
      if cleanLine.startsWith("╭") and cleanLine.contains("Options"):
        optionsHeaderFound = true
      if cleanLine.startsWith("╭") and cleanLine.contains("Commands"):
        commandsHeaderFound = true

    check usageHeaderFound
    check optionsHeaderFound
    check commandsHeaderFound
    check cleanRendered.contains("[OPTIONS]")
    check cleanRendered.contains("--help, -h")
    check cleanRendered.contains("--quiet, -q")
    check cleanRendered.contains("run")
    check cleanRendered.contains("Run the app with a command description")

    var quietLineIndex = -1
    for i, line in lines:
      if stripAnsi(line).contains("--quiet, -q"):
        quietLineIndex = i
        break

    check quietLineIndex >= 0
    check quietLineIndex + 1 < lines.len
    check stripAnsi(lines[quietLineIndex + 1]).startsWith("│ ")
    check lines[quietLineIndex + 1].contains("wrap inside the options box")

  test "cliArg optional accepts zero or one word":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "greet",
          "Greet.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[cliArg("name", "Name.", optional = true)],
        ),
      ],
      description: "Test app.",
      name: "tappOptArg",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr0 = cliParse(m, @["greet"])
    check pr0.kind == cliParseOk
    check pr0.args.len == 0
    let pr1 = cliParse(m, @["greet", "Ada"])
    check pr1.kind == cliParseOk
    check pr1.args == @["Ada"]
    check cliParse(m, @["greet", "Ada", "Bob"]).kind == cliParseError

  test "cliArgList min=1 rejects empty tail":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[cliArgList("files", "Files.", min = 1)],
        ),
      ],
      description: "Test app.",
      name: "tappArgListMin",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    check cliParse(m, @["run"]).kind == cliParseError
    check cliParse(m, @["run", "a"]).kind == cliParseOk
    check cliParse(m, @["run", "a"]).args == @["a"]

  test "cliArgList max=2 rejects a third word":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[cliArgList("files", "Files.", min = 0, max = 2)],
        ),
      ],
      description: "Test app.",
      name: "tappArgListMax",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let prEmpty = cliParse(m, @["run"])
    check prEmpty.kind == cliParseOk
    check prEmpty.args.len == 0
    check cliParse(m, @["run", "a", "b"]).kind == cliParseOk
    check cliParse(m, @["run", "a", "b"]).args == @["a", "b"]
    let prExtra = cliParse(m, @["run", "a", "b", "c"])
    check prExtra.kind == cliParseError
    check prExtra.errorHelpPath == @["run"]

  test "parse errors set errorHelpPath for cliHelpRender":
    let mRoot = cliMergeBuiltins(makeLeafSchema())
    let errRoot = cliParse(mRoot, @["--not-defined"])
    check errRoot.kind == cliParseError
    check errRoot.errorHelpPath.len == 0

    let s = CliSchema(
      commands: @[
        cliLeaf(
          "greet",
          "Greet.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[cliArg("name", "Name.", optional = true)],
        ),
        cliLeaf(
          "run",
          "Run.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[cliArgList("files", "Files.", min = 1)],
        ),
      ],
      description: "T.",
      name: "tappHelpPath",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let errGreet = cliParse(m, @["greet", "a", "b"])
    check errGreet.kind == cliParseError
    check errGreet.errorHelpPath == @["greet"]

    let errRun = cliParse(m, @["run"])
    check errRun.kind == cliParseError
    check errRun.errorHelpPath == @["run"]

  test "cliValidate errors preserve errorHelpPath":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Run.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          options = @[cliOptNumber("count", "How many.", 'n')],
        ),
      ],
      description: "T.",
      name: "tappValHelpPath",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let pr = cliParse(m, @["run", "--count=not-a-number"])
    check pr.kind == cliParseOk
    let pr2 = cliValidate(m, pr)
    check pr2.kind == cliParseError
    check pr2.errorHelpPath == @["run"]

  test "help positional label shows optional brackets":
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "x",
          "X.",
          proc(ctx: CliContext) {.nimcall.} = discard,
          arguments = @[cliArg("n", "N.", optional = true)],
        ),
      ],
      description: "D.",
      name: "tappHelpPos",
      options: @[],
    )
    let clean = stripAnsi(cliHelpRender(cliMergeBuiltins(s), @["x"]))
    check clean.contains("[n]")
