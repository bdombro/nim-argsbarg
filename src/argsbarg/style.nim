## ANSI sequence for bold emphasis.
const AnsiBold* = "\e[1m"

## ANSI sequence for cyan headings.
const AnsiCyan* = "\e[36m"

## ANSI sequence for dim secondary text.
const AnsiDim* = "\e[2m"

## ANSI sequence for green success text.
const AnsiGreen* = "\e[32m"

## ANSI sequence for red error text.
const AnsiRed* = "\e[31m"

## ANSI reset sequence for styled terminal output.
const AnsiReset* = "\e[0m"

## ANSI sequence for yellow warning text.
const AnsiYellow* = "\e[33m"

## Wraps text in bold styling.
proc styleBold*(s: string): string =
  AnsiBold & s & AnsiReset


## Wraps text in cyan styling.
proc styleCyan*(s: string): string =
  AnsiCyan & s & AnsiReset


## Wraps text in dim styling.
proc styleDim*(s: string): string =
  AnsiDim & s & AnsiReset


## Wraps text in green styling.
proc styleGreen*(s: string): string =
  AnsiGreen & s & AnsiReset


## Wraps text in red styling.
proc styleRed*(s: string): string =
  AnsiRed & s & AnsiReset


## Wraps text in yellow styling.
proc styleYellow*(s: string): string =
  AnsiYellow & s & AnsiReset
