import argsbarg/[dispatch, errors, help, parse, schema, style, validate]

## Public API surface re-exported for `import argsbarg` consumers.
export errors.ArgsbargSchemaDefect

## Re-exports help rendering for custom integrations.
export help.cliHelpRender

## Re-exports `cliMergeBuiltins` and `cliRun` from the dispatch module.
export dispatch.cliErrWithHelp, dispatch.cliMergeBuiltins, dispatch.cliRun

## Re-exports argv parsing entry point.
export parse.cliParse

## Re-exports the schema types and helpers used to declare CLIs (including `CliCommand` and `CliOption`).
export schema

## Re-exports terminal styling helpers and constants.
export style

## Re-exports individual style wrappers for selective imports.
export style.styleAquaBold, style.styleBlue, style.styleBold, style.styleCyan, style.styleDim,
  style.styleGreen, style.styleGreenBright, style.styleRed, style.styleYellow

## Re-exports schema and parse-result validation helpers.
export validate.cliSchemaValidate, validate.cliValidate
