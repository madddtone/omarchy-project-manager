#!/bin/bash

# Omarchy Project Manager — discovery helper.
#
# Walks the configured roots for git repositories and Godot projects, gathers
# git metadata for both discovered and explicitly configured projects, detects
# project types, generates tasks, and reports which external commands exist.
# Git/type/task work for each candidate runs in parallel.
#
# Emits one JSON object on stdout:
#   { "projects": [ { "name", "path", "godot", "types": [...],
#                     "tasks": [ {name,command,requires} ],
#                     "git": {branch,dirty,ahead,behind,remote,commit,commitAt,stash}|null } ],
#     "availableCommands": [ ... ] }
#
# usage:
#   discover.sh scan [--depth N] [--exclude a,b,c] [--root DIR]... \
#     [--editor-command CMD]... [--need CMD]... [--concurrency N] \
#     [--no-untracked] [-- PROJECT_PATH...]

set -uo pipefail

depth=3
exclude_csv="node_modules,.git,.venv,venv,__pycache__,dist,build,target,vendor,.cache,.next,.turbo,coverage"
concurrency=0
untracked=1
roots=()
editors=()
needs=()
explicit=()

while (($#)); do
  case "$1" in
  --depth) depth="${2:-3}"; shift 2 ;;
  --exclude) exclude_csv="${2:-}"; shift 2 ;;
  --root) roots+=("${2:-}"); shift 2 ;;
  --editor-command) editors+=("${2:-}"); shift 2 ;;
  --need) needs+=("${2:-}"); shift 2 ;;
  --concurrency) concurrency="${2:-0}"; shift 2 ;;
  --no-untracked) untracked=0; shift ;;
  --) shift; explicit=("$@"); break ;;
  *) shift ;;
  esac
done

[[ $depth =~ ^[0-9]+$ ]] || depth=3
[[ $concurrency =~ ^[0-9]+$ ]] || concurrency=0
((concurrency > 0)) || concurrency=$(nproc 2>/dev/null || echo 4)
((concurrency > 0)) || concurrency=4

expand() {
  local p="${1:-}"
  p="${p/#\~/$HOME}"
  printf '%s\n' "$p"
}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
out="$tmp/projects.jsonl"
: >"$out"

declare -A seen=()
declare -A names=()

add_project() {
  local raw="$1" path real
  path=$(expand "$raw")
  [[ -d $path ]] || return 0
  real=$(realpath -m -- "$path" 2>/dev/null) || return 0
  [[ -n ${seen[$real]:-} ]] && return 0
  seen[$real]=1
  names[$real]="$(basename "$path")"
}

for p in "${explicit[@]:-}"; do
  [[ -n $p ]] || continue
  add_project "$p"
done

IFS=',' read -r -a excludes <<<"$exclude_csv"

discover_root() {
  local root
  root=$(expand "${1:-}")
  [[ -d $root ]] || return 0

  local -a prunable=('(')
  local e added=0
  for e in "${excludes[@]}"; do
    e="${e#"${e%%[![:space:]]*}"}"
    e="${e%"${e##*[![:space:]]}"}"
    [[ -n $e ]] || continue
    prunable+=(-name "$e" -o)
    added=1
  done
  if ((added)); then
    local last=$((${#prunable[@]} - 1))
    unset "prunable[$last]"
    prunable+=(')' -prune -o)
  else
    prunable=()
  fi

  local d
  while IFS= read -r d; do
    [[ -d $d/.git || -f $d/project.godot ]] || continue
    add_project "$d"
  done < <(find "$root" -maxdepth "$depth" -type d "${prunable[@]}" -type d -print 2>/dev/null)
}

if ((${#roots[@]})); then
  for r in "${roots[@]}"; do
    discover_root "$r"
  done
fi

# ---------------------------------------------------------------- worker

cat >"$tmp/worker" <<'WORKER'
#!/bin/bash
# One candidate: emit a single JSON line. Invoked concurrently.
set -uo pipefail
d="${1:-}"
[[ -n $d ]] || exit 0
out="$WORKER_OUT"
untracked="${WORKER_UNTRACKED:-1}"

has() { [[ -e "$d/$1" ]]; }
has_glob() { compgen -G "$d/$1" >/dev/null 2>&1; }

git_json() {
  local p="$d" o branch ahead behind dirty remote commit commit_at stash
  if ! git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'null'
    return 0
  fi
  local uf="normal"
  ((untracked)) || uf="no"
  o=$(git -C "$p" status --porcelain=v2 --branch --untracked-files="$uf" 2>/dev/null || true)
  branch=$(sed -n 's/^# branch.head //p' <<<"$o" | head -n1)
  ahead=$(sed -n 's/^# branch.ab +\([0-9]*\) -.*/\1/p' <<<"$o" | head -n1)
  behind=$(sed -n 's/^# branch.ab .*-\([0-9]*\)$/\1/p' <<<"$o" | head -n1)
  dirty=0
  grep -qv '^#' <<<"$o" && dirty=1
  remote=$(git -C "$p" config --get remote.origin.url 2>/dev/null || true)
  commit=$(git -C "$p" log -1 --pretty=%s 2>/dev/null || true)
  commit_at=$(git -C "$p" log -1 --pretty=%ct 2>/dev/null || true)
  stash=$(git -C "$p" stash list 2>/dev/null | wc -l | tr -d ' ')
  [[ $commit_at =~ ^[0-9]+$ ]] || commit_at=0
  [[ $stash =~ ^[0-9]+$ ]] || stash=0
  jq -cn \
    --arg branch "${branch:-}" \
    --argjson dirty "$dirty" \
    --argjson ahead "${ahead:-0}" \
    --argjson behind "${behind:-0}" \
    --arg remote "${remote:-}" \
    --arg commit "${commit:-}" \
    --argjson commitAt "$((${commit_at} * 1000))" \
    --argjson stash "$stash" \
    '{branch:$branch, dirty:($dirty == 1), ahead:$ahead, behind:$behind, remote:$remote, commit:$commit, commitAt:$commitAt, stash:$stash}'
}

declare -a TASK_OBJS=()
task() {
  TASK_OBJS+=("$(jq -cn --arg n "$1" --arg c "$2" --arg r "${3:-}" '{name:$n, command:$c, requires:$r}')")
}

detect_types() {
  local o=()
  has project.godot && o+=(godot)
  has Cargo.toml && o+=(rust)
  has go.mod && o+=(go)
  has build.zig && o+=(zig)
  { has deno.json || has deno.jsonc || has deno.lock; } && o+=(deno)
  { has bun.lockb || has bun.lock; } && o+=(bun)
  has package.json && o+=(node)
  { has pyproject.toml || has uv.lock || has requirements.txt || has setup.py; } && o+=(python)
  { has flake.nix || has default.nix; } && o+=(nix)
  has CMakeLists.txt && o+=(cmake)
  has meson.build && o+=(meson)
  has Gemfile && o+=(ruby)
  has composer.json && o+=(php)
  { has pom.xml || has build.gradle || has gradlew || has_glob '*.java'; } && o+=(java)
  { has build.gradle.kts || has settings.gradle.kts; } && o+=(kotlin)
  has build.gradle && o+=(gradle)
  { has_glob '*.csproj' || has_glob '*.sln' || has_glob '*.fsproj'; } && o+=(dotnet)
  has Package.swift && o+=(swift)
  has mix.exs && o+=(elixir)
  { has stack.yaml || has_glob '*.cabal'; } && o+=(haskell)
  has pubspec.yaml && o+=(dart)
  { has_glob '*.rockspec' || has .luarc.json; } && o+=(lua)
  { has main.tf || has_glob '*.tf'; } && o+=(terraform)
  { has Dockerfile || has docker-compose.yml || has docker-compose.yaml || has compose.yml || has compose.yaml; } && o+=(docker)
  if ((${#o[@]} == 0)); then
    has Makefile && o+=(make)
    { has justfile || has Justfile || has .justfile; } && o+=(just)
    has_glob '*.sh' && o+=(shell)
  fi
  if ((${#o[@]})); then printf '%s\n' "${o[@]}" | jq -R . | jq -sc .; else printf '[]'; fi
}

node_tasks() {
  local pm=npm scripts s i=0
  has bun.lockb && pm=bun
  has pnpm-lock.yaml && pm=pnpm
  has yarn.lock && pm=yarn
  task "Install dependencies" "$pm install" "$pm"
  [[ -f $d/package.json ]] || return 0
  scripts=$(jq -r '.scripts // {} | keys[]' "$d/package.json" 2>/dev/null || true)
  [[ -n $scripts ]] || return 0
  local ordered=() prio="dev start build test lint format typecheck check serve watch preview"
  for s in $prio; do grep -qxF "$s" <<<"$scripts" && ordered+=("$s"); done
  while IFS= read -r s; do
    [[ -n $s ]] || continue
    [[ " ${ordered[*]:-} " == *" $s "* ]] && continue
    ordered+=("$s")
  done <<<"$scripts"
  for s in "${ordered[@]}"; do
    ((i >= 9)) && break
    task "$pm run $s" "$pm run $s" "$pm"
    ((i++))
  done
}

make_tasks() {
  local t i=0
  task "make (default)" "make" make
  while IFS= read -r t; do
    [[ -n $t ]] || continue
    ((i >= 6)) && break
    task "make $t" "make $t" make
    ((i++))
  done < <(grep -oE '^[a-zA-Z0-9][a-zA-Z0-9_.-]*:' "$d/Makefile" 2>/dev/null | sed 's/:$//' | sort -u)
}

just_tasks() {
  local f t i=0
  for f in justfile Justfile .justfile; do [[ -f $d/$f ]] && break; done
  [[ -f ${d:-}/$f ]] || return 0
  while IFS= read -r t; do
    [[ -n $t ]] || continue
    ((i >= 8)) && break
    task "just $t" "just $t" just
    ((i++))
  done < <(grep -oE '^[a-zA-Z_][a-zA-Z0-9_-]*' "$d/$f" 2>/dev/null | sort -u)
}

detect_tasks() {
  local t
  TASK_OBJS=()
  for t in $(detect_types | jq -r '.[]' 2>/dev/null); do
    case "$t" in
    node) node_tasks ;;
    make) make_tasks ;;
    just) just_tasks ;;
    rust)
      task "cargo build" "cargo build" cargo
      task "cargo run" "cargo run" cargo
      task "cargo test" "cargo test" cargo
      task "cargo clippy" "cargo clippy" cargo
      ;;
    go)
      task "go build" "go build ./..." go
      task "go run" "go run ." go
      task "go test" "go test ./..." go
      ;;
    python)
      if has uv.lock || has pyproject.toml; then task "uv run pytest" "uv run pytest" uv
      else task "pytest" "pytest" pytest; fi
      ;;
    nix)
      task "nix develop" "nix develop" nix
      task "nix build" "nix build" nix
      ;;
    cmake) task "CMake build" "cmake -S . -B build && cmake --build build" cmake ;;
    meson) task "meson build" "meson setup build && meson compile -C build" meson ;;
    ruby) task "bundle install" "bundle install" bundle ;;
    php) task "composer install" "composer install" composer ;;
    java)
      if has pom.xml; then task "mvn package" "mvn package" mvn
      else task "gradle build" "./gradlew build" ./gradlew; fi
      ;;
    gradle) task "gradle build" "./gradlew build" ./gradlew ;;
    kotlin) task "gradle build" "./gradlew build" ./gradlew ;;
    dotnet)
      task "dotnet build" "dotnet build" dotnet
      task "dotnet test" "dotnet test" dotnet
      ;;
    elixir)
      task "mix deps.get" "mix deps.get" mix
      task "mix test" "mix test" mix
      ;;
    dart)
      task "dart pub get" "dart pub get" dart
      ;;
    haskell)
      if has stack.yaml; then task "stack build" "stack build" stack
      else task "cabal build" "cabal build" cabal; fi
      ;;
    esac
  done
  if ((${#TASK_OBJS[@]})); then printf '%s\n' "${TASK_OBJS[@]}" | jq -s .; else printf '[]'; fi
}

git=$(git_json)
godot=false
[[ -f $d/project.godot ]] && godot=true
types=$(detect_types)
tasks=$(detect_tasks)
jq -cn --arg name "$(basename "$d")" --arg path "$d" --argjson git "$git" --argjson godot "$godot" \
  --argjson types "$types" --argjson tasks "$tasks" \
  '{name:$name, path:$path, git:$git, godot:$godot, types:$types, tasks:$tasks}' >>"$out"
WORKER
chmod +x "$tmp/worker"

export WORKER_OUT="$out"
export WORKER_UNTRACKED="$untracked"

if ((${#seen[@]})); then
  printf '%s\n' "${!seen[@]}" | sort | tr '\n' '\0' \
    | xargs -0 -r -P "$concurrency" -n1 bash "$tmp/worker" 2>/dev/null
fi

# ------------------------------------------------------ available commands

declare -a NEEDS=()
add_need() { [[ -n ${1:-} ]] && NEEDS+=("$1"); }

for c in "${editors[@]:-}" "${needs[@]:-}" git lazygit wl-copy xdg-open xdg-terminal-exec omarchy-launch-browser; do
  add_need "$c"
done

# Commands required by generated tasks (cargo, npm, pytest, ...).
while IFS= read -r c; do add_need "$c"; done \
  < <(jq -r '.tasks[]?.requires // empty' "$out" 2>/dev/null | sort -u)

avail=()
add_avail() {
  local c="${1:-}" base existing
  [[ -n $c ]] || return 0
  if [[ $c == */* ]]; then
    [[ -x $c ]] || return 0
  else
    command -v "$c" >/dev/null 2>&1 || return 0
  fi
  for existing in "${avail[@]:-}"; do [[ $existing == "$c" ]] && return 0; done
  avail+=("$c")
}
for c in "${NEEDS[@]:-}"; do add_avail "$c"; done

if ((${#avail[@]})); then
  avail_json=$(printf '%s\n' "${avail[@]}" | jq -R . | jq -s .)
else
  avail_json='[]'
fi

jq -s --argjson available "$avail_json" \
  '{projects: ., availableCommands: $available}' "$out"
