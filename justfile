set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

nim := "nim"
src_path := "-p:src"

# List available recipes (default).
_:
    @just --list

# Compile the library and both example apps.
build:
    {{nim}} c --hints:off {{src_path}} src/argsbarg.nim
    {{nim}} c --hints:off {{src_path}} examples/nim_file.nim
    {{nim}} c --hints:off {{src_path}} examples/nim_minimal.nim

# Run unit tests under tests/.
test:
    {{nim}} c -r --hints:off {{src_path}} tests/t_parse.nim
    {{nim}} c -r --hints:off {{src_path}} tests/t_completion.nim
    {{nim}} c -r --hints:off {{src_path}} tests/t_completion_bash.nim

# Build and run the nim_file example; pass extra CLI args after the recipe name.
run-example-file *args:
    {{nim}} c --hints:off {{src_path}} examples/nim_file.nim
    ./examples/nim_file {{args}}

# Build and run the nim_minimal example; pass extra CLI args after the recipe name.
run-example-minimal *args:
    {{nim}} c --hints:off {{src_path}} examples/nim_minimal.nim
    ./examples/nim_minimal {{args}}

# Build nim_file and run a small set of CLI and zsh completion checks.
smoke-file:
    just build
    ./examples/nim_file 2>&1 | grep -q "Usage"
    ./examples/nim_file ./README.md | grep -q "argsbarg"
    ./examples/nim_file -h >/dev/null
    ./examples/nim_file stat -h >/dev/null
    ./examples/nim_file stat owner -h >/dev/null
    ./examples/nim_file completion zsh > /tmp/argsbarg_smoke_file.zsh
    zsh -n /tmp/argsbarg_smoke_file.zsh
    ./examples/nim_file completion bash > /tmp/argsbarg_smoke_file.bash
    bash -n /tmp/argsbarg_smoke_file.bash

# Build nim_minimal and run hello, help, and zsh completion syntax checks.
smoke-minimal:
    just build
    ./examples/nim_minimal hello --name world | grep -q world
    ./examples/nim_minimal --name world | grep -q world
    ./examples/nim_minimal -h >/dev/null
    ./examples/nim_minimal completion zsh > /tmp/argsbarg_smoke_minimal.zsh
    zsh -n /tmp/argsbarg_smoke_minimal.zsh
    ./examples/nim_minimal completion bash > /tmp/argsbarg_smoke_minimal.bash
    bash -n /tmp/argsbarg_smoke_minimal.bash

# Full pre-release pass: build, tests, and shell syntax on generated completion scripts.
release-check: build test
    ./examples/nim_file completion zsh > /tmp/argsbarg_release_file.zsh
    zsh -n /tmp/argsbarg_release_file.zsh
    ./examples/nim_file completion bash > /tmp/argsbarg_release_file.bash
    bash -n /tmp/argsbarg_release_file.bash
    ./examples/nim_minimal completion zsh > /tmp/argsbarg_release_minimal.zsh
    zsh -n /tmp/argsbarg_release_minimal.zsh
    ./examples/nim_minimal completion bash > /tmp/argsbarg_release_minimal.bash
    bash -n /tmp/argsbarg_release_minimal.bash

# Publish a new release
release bump:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    cd "$root"
    exec python3 scripts/release.py "{{bump}}"
