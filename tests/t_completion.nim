import std/[options, os, osproc, strutils, unittest]
import argsbarg
import argsbarg/completion_zsh

suite "completionZshScript":
  test "emits nested subcommands and passes zsh -n":
    proc leaf(ctx: CliContext) = discard
    let s = CliSchema(
      commands: @[
        CliCommand(
          arguments: @[],
          commands: @[
            CliCommand(
              arguments: @[],
              commands: @[
                CliCommand(
                  arguments: @[],
                  commands: @[
                    CliCommand(
                      arguments: @[],
                      commands: @[],
                      description: "Leaf.",
                      handler: some(leaf),
                      name: "lookup",
                      options: @[],
                    ),
                  ],
                  description: "Mid.",
                  handler: none(CliHandler),
                  name: "owner",
                  options: @[],
                ),
              ],
              description: "Top stat.",
              handler: none(CliHandler),
              name: "stat",
              options: @[
                CliOption(
                  description: "Verbose output.",
                  isPositional: false,
                  isRepeated: false,
                  kind: cliValueNone,
                  name: "verbose",
                  shortName: 'v',
                ),
                CliOption(
                  description: "Choose a format.",
                  isPositional: false,
                  isRepeated: false,
                  kind: cliValueString,
                  name: "format",
                  shortName: 'f',
                ),
              ],
            ),
          ],
          description: "Root noop.",
          handler: some(leaf),
          name: "noop",
          options: @[],
        ),
      ],
      defaultCommand: none(string),
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
