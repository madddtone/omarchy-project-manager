// Project Manager — project-type metadata. Pure data + tiny helpers, no Qt,
// so it can be unit-tested with plain node. The `id` values must stay in sync
// with the `detect_types` function in discover.sh.

var TYPES = {
  godot:    { label: "Godot",    icon: "\ue65f" },
  rust:     { label: "Rust",     icon: "\ue7a8" },
  go:       { label: "Go",       icon: "\ue626" },
  zig:      { label: "Zig",      icon: "\ue6a9" },
  node:     { label: "Node",     icon: "\ue718" },
  deno:     { label: "Deno",     icon: "\ue7c0" },
  bun:      { label: "Bun",      icon: "\ue76f" },
  python:   { label: "Python",   icon: "\ue73c" },
  ruby:     { label: "Ruby",     icon: "\ue739" },
  php:      { label: "PHP",      icon: "\ue73d" },
  java:     { label: "Java",     icon: "\ue738" },
  kotlin:   { label: "Kotlin",   icon: "\ue634" },
  gradle:   { label: "Gradle",   icon: "\ue7b9" },
  dotnet:   { label: "C# / .NET", icon: "\ue77f" },
  swift:    { label: "Swift",    icon: "\ue755" },
  elixir:   { label: "Elixir",   icon: "\ue62d" },
  haskell:  { label: "Haskell",  icon: "\ue777" },
  dart:     { label: "Dart",     icon: "\ue798" },
  lua:      { label: "Lua",      icon: "\ue620" },
  nix:      { label: "Nix",      icon: "\uf313" },
  cmake:    { label: "CMake",    icon: "\ue794" },
  meson:    { label: "Meson",    icon: "\uf085" },
  terraform:{ label: "Terraform", icon: "\ue69a" },
  docker:   { label: "Docker",   icon: "\uf308" },
  make:     { label: "Make",     icon: "\ue673" },
  just:     { label: "Just",     icon: "\uf0ad" },
  shell:    { label: "Shell",    icon: "\uf489" }
}

// When several markers match, the earlier one wins for the single icon/label
// shown in a row. Ordered most- to least-specific.
var PRIORITY = [
  "godot", "rust", "go", "zig", "deno", "bun", "node", "python",
  "ruby", "php", "java", "kotlin", "gradle", "dotnet", "swift",
  "elixir", "haskell", "dart", "lua", "nix", "cmake", "meson",
  "terraform", "docker", "make", "just", "shell"
]

function known(id) {
  return Object.prototype.hasOwnProperty.call(TYPES, String(id))
}

function primaryType(types) {
  if (!Array.isArray(types)) return ""
  for (var i = 0; i < PRIORITY.length; i++) {
    if (types.indexOf(PRIORITY[i]) !== -1) return PRIORITY[i]
  }
  for (var j = 0; j < types.length; j++) {
    if (known(types[j])) return types[j]
  }
  return ""
}

function typeIcon(types) {
  var t = primaryType(types)
  return t ? TYPES[t].icon : ""
}

function typeLabel(types) {
  var t = primaryType(types)
  return t ? TYPES[t].label : ""
}

// Human-readable list of every recognised type, in priority order.
function typeLabels(types) {
  if (!Array.isArray(types)) return []
  var out = []
  for (var i = 0; i < PRIORITY.length; i++) {
    if (types.indexOf(PRIORITY[i]) !== -1) out.push(TYPES[PRIORITY[i]].label)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    TYPES: TYPES,
    PRIORITY: PRIORITY,
    known: known,
    primaryType: primaryType,
    typeIcon: typeIcon,
    typeLabel: typeLabel,
    typeLabels: typeLabels
  }
}
