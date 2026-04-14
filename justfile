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
    ./examples/nim_file 2>&1 | grep -q "Usage:"
    ./examples/nim_file ./README.md | grep -q "argsbarg"
    ./examples/nim_file -h >/dev/null
    ./examples/nim_file stat -h >/dev/null
    ./examples/nim_file stat owner -h >/dev/null
    ./examples/nim_file completions-zsh --print > /tmp/argsbarg_smoke_file.zsh
    zsh -n /tmp/argsbarg_smoke_file.zsh

# Build nim_minimal and run hello, help, and zsh completion syntax checks.
smoke-minimal:
    just build
    ./examples/nim_minimal hello --name world | grep -q world
    ./examples/nim_minimal --name world | grep -q world
    ./examples/nim_minimal -h >/dev/null
    ./examples/nim_minimal completions-zsh --print > /tmp/argsbarg_smoke_minimal.zsh
    zsh -n /tmp/argsbarg_smoke_minimal.zsh

# Full pre-release pass: build, tests, and zsh -n on generated completion scripts.
release-check: build test
    ./examples/nim_file completions-zsh --print > /tmp/argsbarg_release_file.zsh
    zsh -n /tmp/argsbarg_release_file.zsh
    ./examples/nim_minimal completions-zsh --print > /tmp/argsbarg_release_minimal.zsh
    zsh -n /tmp/argsbarg_release_minimal.zsh

# Bump SemVer in argsbarg.nimble, release-check, commit, tag vX.Y.Z, push. Arg: major | minor | patch.
release bump:
    #!/usr/bin/env bash
    set -euo pipefail
    bump="{{bump}}"
    case "$bump" in
      major|minor|patch) ;;
      *)
        echo "error: bump must be major, minor, or patch (got: ${bump})" >&2
        echo "usage: just release major|minor|patch" >&2
        exit 1
        ;;
    esac
    export BUMP_KIND="$bump"
    root="$(git rev-parse --show-toplevel)"
    cd "$root"
    if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
      echo "error: tracked files have uncommitted changes; commit or stash first." >&2
      exit 1
    fi
    new_ver="$(python3 - <<'PY'
    import os
    import re
    from pathlib import Path
    path = Path("argsbarg.nimble")
    text = path.read_text()
    m = re.search(r'^version = "(\d+)\.(\d+)\.(\d+)"', text, re.M)
    if not m:
        raise SystemExit("error: could not parse version from argsbarg.nimble")
    major, minor, patch = map(int, m.groups())
    kind = os.environ["BUMP_KIND"]
    if kind == "major":
        new_ver = f"{major + 1}.0.0"
    elif kind == "minor":
        new_ver = f"{major}.{minor + 1}.0"
    elif kind == "patch":
        new_ver = f"{major}.{minor}.{patch + 1}"
    else:
        raise SystemExit(f"error: invalid BUMP_KIND {kind!r}")
    path.write_text(
        re.sub(
            r'^version = "\d+\.\d+\.\d+"',
            f'version = "{new_ver}"',
            text,
            count=1,
            flags=re.M,
        )
    )
    print(new_ver)
    PY
    )"
    just release-check
    git add argsbarg.nimble
    git commit -m "Bump version to ${new_ver}."
    git tag -a "v${new_ver}" -m "Release v${new_ver}."
    git push origin HEAD
    git push origin "refs/tags/v${new_ver}"
    
    echo "Clearing local caches (to ensure local apps pick up the new version)"
    rm -rf ~/.nimble/pkgs2/argsbarg-* 2>/dev/null
    rm -rf ~/.nimble/pkgcache/githubcom_bdombronimargsbarg* 2>/dev/null
    rm -rf ~/.cache/gor ~/.cache/nimr 2>/dev/null
