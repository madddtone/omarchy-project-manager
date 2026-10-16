// Project Manager — scan orchestration helpers. Pure: builds the argv for
// discover.sh and normalizes its JSON output. Unit-testable with node.

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function expandPath(path, home) {
  var s = String(path == null ? "" : path)
  if (s === "~") return home
  if (s.indexOf("~/") === 0) return home + s.substring(1)
  return s
}

function basename(path) {
  var parts = String(path == null ? "" : path).split("/")
  var name = parts[parts.length - 1]
  return name.length > 0 ? name : String(path == null ? "" : path)
}

// argv for `bash discover.sh scan ...`.
function scanArgs(config, scriptPath, home) {
  var cfg = isObject(config) ? config : {}
  var discovery = isObject(cfg.discovery) ? cfg.discovery : {}
  var scan = isObject(cfg.scan) ? cfg.scan : {}
  var args = ["bash", String(scriptPath || ""), "scan"]

  if (discovery.enabled !== false) {
    args.push("--depth", String(discovery.maxDepth || 3))
    args.push("--exclude", (discovery.exclude || []).join(","))
    var roots = discovery.roots || []
    for (var i = 0; i < roots.length; i++) args.push("--root", expandPath(roots[i], home))
  }

  var concurrency = Number(scan.concurrency)
  if (isFinite(concurrency) && concurrency > 0) args.push("--concurrency", String(Math.floor(concurrency)))
  if (scan.untracked === false) args.push("--no-untracked")

  var editors = isObject(cfg.editors) ? cfg.editors : {}
  for (var id in editors) {
    if (editors[id] && editors[id].command) args.push("--editor-command", String(editors[id].command))
  }

  if (isObject(cfg.terminal) && cfg.terminal.command) args.push("--need", String(cfg.terminal.command))
  var actions = Array.isArray(cfg.actions) ? cfg.actions : []
  for (var a = 0; a < actions.length; a++) {
    if (actions[a] && actions[a].requires) args.push("--need", String(actions[a].requires))
  }

  args.push("--")
  var projects = Array.isArray(cfg.projects) ? cfg.projects : []
  for (var j = 0; j < projects.length; j++) {
    if (projects[j] && projects[j].path) args.push(expandPath(projects[j].path, home))
  }
  return args
}

function normalizeGit(git) {
  if (!isObject(git)) return null
  return {
    branch: String(git.branch || ""),
    dirty: !!git.dirty,
    ahead: Number(git.ahead || 0) || 0,
    behind: Number(git.behind || 0) || 0,
    remote: String(git.remote || ""),
    commit: String(git.commit || ""),
    commitAt: Number(git.commitAt || 0) || 0,
    stash: Number(git.stash || 0) || 0
  }
}

function normalizeScanTasks(tasks) {
  var out = []
  if (!Array.isArray(tasks)) return out
  for (var i = 0; i < tasks.length; i++) {
    var t = tasks[i]
    if (!isObject(t) || !t.name || !t.command) continue
    out.push({
      name: String(t.name),
      command: String(t.command),
      requires: String(t.requires || "")
    })
  }
  return out
}

function parseScan(raw) {
  var data
  try {
    data = JSON.parse(String(raw == null ? "" : raw))
  } catch (e) {
    return null
  }
  if (!isObject(data)) return null
  var projects = []
  var list = Array.isArray(data.projects) ? data.projects : []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!isObject(p) || !p.path) continue
    projects.push({
      name: String(p.name || basename(p.path)),
      path: String(p.path),
      git: normalizeGit(p.git),
      godot: p.godot === true,
      types: Array.isArray(p.types) ? p.types.map(String) : [],
      tasks: normalizeScanTasks(p.tasks)
    })
  }
  return {
    projects: projects,
    availableCommands: Array.isArray(data.availableCommands) ? data.availableCommands.map(String) : []
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    isObject: isObject,
    expandPath: expandPath,
    basename: basename,
    scanArgs: scanArgs,
    normalizeGit: normalizeGit,
    normalizeScanTasks: normalizeScanTasks,
    parseScan: parseScan
  }
}
