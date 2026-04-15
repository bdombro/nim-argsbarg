import std/[os, osproc, strutils, unittest]
import argsbarg
import argsbarg/completion_bash

suite "completionBash":
  test "emits nested subcommands and passes bash -n":
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
      name: "tapp_bash",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionBashScript(m)
    check script.contains("'lookup'")
    check script.contains("'--verbose'")
    let path = getTempDir() / "argsbarg_t_completion_bash.sh"
    writeFile(path, script)
    let (output, exitCode) = execCmdEx("bash -n " & path.quoteShell)
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
      name: "tapp_echo_bash",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionBashScript(m)
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
      name: "tapp_short_bash",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionBashScript(m)
    check not script.contains("  esac\n  echo 0\n}")
    check script.contains("        *) echo 0; return ;;")
    let path = getTempDir() / "argsbarg_t_completion_bash_consume_short.sh"
    writeFile(path, script)
    let inner =
      "source " & path.quoteShell & " 2>/dev/null; _tapp_short_bash_nac_consume_short 1 -v"
    let (output, exitCode) = execCmdEx("bash -c " & inner.quoteShell)
    check exitCode == 0
    check output.strip == "1"

  test "simulate prints only scope id line":
    proc leaf(ctx: CliContext) {.nimcall.} = discard
    let s = CliSchema(
      commands: @[
        cliLeaf(
          "hello",
          "Leaf.",
          leaf,
          options = @[cliOptFlag("verbose", "Verbose.", 'v')],
        ),
      ],
      description: "Simulate stdout app.",
      name: "tapp_sim_bash",
      options: @[],
    )
    let m = cliMergeBuiltins(s)
    let script = completionBashScript(m)
    let path = getTempDir() / "argsbarg_t_completion_bash_simulate.sh"
    writeFile(path, script)
    let inner =
      "source " & path.quoteShell &
      " 2>/dev/null; words=(tapp_sim_bash hello \"\"); cword=3;" &
      " out=$(_tapp_sim_bash_nac_simulate); printf 'sid=%s' \"$out\""
    let (output, exitCode) = execCmdEx("bash -c " & inner.quoteShell)
    check exitCode == 0
    check output.strip == "sid=1"
