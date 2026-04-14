import std/[os, osproc, strutils, unittest]
import argsbarg
import argsbarg/completion_zsh

suite "completionZshScript":
  test "emits nested subcommands and passes zsh -n":
    proc leaf(ctx: CliContext) {.nimcall.} = discard
    let s = CliSchema(
      commands: @[
        cliGroup(
          "noop",
          "Root noop.",
          commands = @[
            cliGroup(
              "stat",
              "Top stat.",
              commands = @[
                cliGroup(
                  "owner",
                  "Mid.",
                  commands = @[
                    cliLeaf("lookup", "Leaf.", leaf),
                  ],
                ),
              ],
              options = @[
                cliOptFlag("verbose", "Verbose output.", 'v'),
                cliOptString("format", "Choose a format.", 'f'),
              ],
            ),
          ],
        ),
      ],
      description: "Test app.",
      name: "tapp_zsh",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionZshScript(m)
    check script.contains("lookup:Leaf.")
    check script.contains("-v")
    let path = getTempDir() / "argsbarg_t_completion.zsh"
    writeFile(path, script)
    let (output, exitCode) = execCmdEx("zsh -n " & path.quoteShell)
    check exitCode == 0 and output.strip.len == 0

  test "consume helpers echo step counts for simulate capture":
    proc leaf(ctx: CliContext) {.nimcall.} = discard
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Leaf.",
          leaf,
          options = @[
            cliOptFlag("verbose", "Verbose.", 'v'),
            cliOptString("format", "Format.", 'f'),
          ],
        ),
      ],
      description: "Echo test app.",
      name: "tapp_echo",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionZshScript(m)
    check script.contains(CliHelpLongFlag & "|" & CliHelpLongFlag & "=*|" & CliHelpShortFlag & ") echo 1 ;;")
    check script.contains("echo 2; return ;;")
    check not script.contains(CliHelpLongFlag & "|" & CliHelpLongFlag & "=*|" & CliHelpShortFlag & ") return 1 ;;")

  test "consume_short emits one line for boolean short flags (no trailing echo 0)":
    proc leaf(ctx: CliContext) {.nimcall.} = discard
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "run",
          "Leaf.",
          leaf,
          options = @[
            cliOptFlag("verbose", "Verbose.", 'v'),
            cliOptString("format", "Format.", 'f'),
          ],
        ),
      ],
      description: "Short-flag regression app.",
      name: "tapp_short1",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionZshScript(m)
    check not script.contains("  esac\n  echo 0\n}")
    check script.contains("        *) break ;;\n")
    let path = getTempDir() / "argsbarg_t_completion_consume_short.zsh"
    writeFile(path, script)
    let inner =
      "source " & path.quoteShell & " 2>/dev/null; _tapp_short1_nac_consume_short 1 -v"
    let (output, exitCode) = execCmdEx("zsh -fc " & inner.quoteShell)
    check exitCode == 0
    check output.strip == "1"
