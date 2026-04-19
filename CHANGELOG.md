# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- README: header image ([`logo.png`](logo.png)) and shields.io badges for the [GitHub
  repository](https://github.com/bdombro/nim-argsbarg), MIT license, Nim ≥ 2.0, and Unix (POSIX)
  targets.

## [2.0.0]

### Added

- `cliArg` — single-word positional; optional `optional = true` for zero or one argv word.
- `cliArgList` — positional tail with `min` (default `0`) and `max` (default `0`); `max = 0`
  means unlimited (only valid as the last positional on a command).
- `cliErrWithHelp` — print an error and full help for a command path, then exit 1 (handler UX
  matching parse-time errors).
- `CliContext.schema` — merged schema (including builtins) available inside every handler.
- Optional `notes` parameter on `cliLeaf` and `cliGroup` (same as `CliCommand.notes`).

### Changed

- `cliRun` exits 1 for implicit help (empty argv, routing node without a subcommand); exits 0
  only when argv contained an explicit `-h` / `--help` flag. `CliParseResult` on `cliParseHelp`
  now exposes `helpExplicit: bool`.
- Parse and validation errors print the full help for the failing subcommand on stderr.
  Error results expose ``errorHelpPath`` (same semantics as ``helpPath`` on help results;
  distinct name because Nim variant objects cannot reuse a field name across branches).
- `CliOption`: replaced `isRepeated` with `argMin` and `argMax` (defaults `1`; ignored for flags).
- Help labels for positionals use `<name>`, `[name]`, `<name...>`, `[name...]` from min/max.

### Removed

- `cliOptPositional` — use `cliArg` / `cliArgList` instead.

[Unreleased]: https://github.com/bdombro/nim-argsbarg/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/bdombro/nim-argsbarg/releases/tag/v2.0.0
