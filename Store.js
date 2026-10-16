// Project Manager — pure logic. No Qt/QML, no I/O, so it is unit-testable with
// plain node. The Service owns processes and files; the Overlay owns the view.

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

function pathKey(path) {
  var s = String(path == null ? "" : path)
  return s.replace(/\/+$/, "") || "/"
}

function shellQuote(value) {
  return "'" + String(value == null ? "" : value).replace(/'/g, "'\\''") + "'"
}

// --------------------------------------------------------------- config

function defaultConfig() {
  return {
    version: 1,
    defaultEditor: "omarchy",
    scale: 0,
    tasksInTerminal: true,
    terminal: { command: "xdg-terminal-exec", args: ["--dir={path}"] },
    scan: { concurrency: 0, untracked: true, refreshMinutes: 10 },
    discovery: {
      enabled: true,
      roots: ["~/Projects"],
      maxDepth: 3,
      exclude: [
        "node_modules", ".git", ".venv", "venv", "__pycache__",
        "dist", "build", "target", "vendor", ".cache", ".next",
        ".turbo", "coverage"
      ]
    },
    editors: {
      omarchy: { label: "Default editor", command: "omarchy-launch-editor", args: ["{path}"], kind: "direct" },
      vscode: { label: "VS Code", command: "code", args: ["{path}"], kind: "gui" },
      zed: { label: "Zed", command: "zed", args: ["{path}"], kind: "gui" },
      cursor: { label: "Cursor", command: "cursor", args: ["{path}"], kind: "gui" },
      nvim: { label: "Neovim", command: "nvim", args: ["{path}"], kind: "terminal" },
      godot: { label: "Godot", command: "godot", args: ["--path", "{path}", "--editor"], kind: "gui" }
    },
    actions: [],
    templates: [],
    projects: []
  }
}

function normalizeEditor(editor, id) {
  if (!isObject(editor)) return { id: id, label: id, command: "", args: ["{path}"], kind: "gui" }
  var kind = "gui"
  if (editor.kind === "terminal") kind = "terminal"
  else if (editor.kind === "direct") kind = "direct"
  return {
    id: id,
    label: String(editor.label || id),
    command: String(editor.command || ""),
    args: Array.isArray(editor.args) ? editor.args.map(String) : ["{path}"],
    kind: kind
  }
}

function mergeEditors(base, over) {
  var out = {}
  var k
  for (k in base) out[k] = normalizeEditor(base[k], k)
  if (isObject(over)) for (k in over) out[k] = normalizeEditor(over[k], k)
  return out
}

function mergeDiscovery(base, over) {
  if (!isObject(over)) {
    return { enabled: base.enabled, roots: base.roots.slice(), maxDepth: base.maxDepth, exclude: base.exclude.slice() }
  }
  return {
    enabled: over.enabled === undefined ? base.enabled : !!over.enabled,
    roots: Array.isArray(over.roots) ? over.roots.map(String) : base.roots.slice(),
    maxDepth: isFinite(Number(over.maxDepth)) ? Math.max(1, Math.floor(Number(over.maxDepth))) : base.maxDepth,
    exclude: Array.isArray(over.exclude) ? over.exclude.map(String) : base.exclude.slice()
  }
}

function mergeScan(base, over) {
  if (!isObject(over)) return { concurrency: base.concurrency, untracked: base.untracked, refreshMinutes: base.refreshMinutes }
  var concurrency = Number(over.concurrency)
  var refresh = Number(over.refreshMinutes)
  return {
    concurrency: isFinite(concurrency) && concurrency > 0 ? Math.floor(concurrency) : base.concurrency,
    untracked: over.untracked === undefined ? base.untracked : !!over.untracked,
    refreshMinutes: isFinite(refresh) && refresh >= 0 ? refresh : base.refreshMinutes
  }
}

function mergeTerminal(base, over) {
  if (!isObject(over)) return { command: base.command, args: base.args.slice() }
  return {
    command: String(over.command || base.command),
    args: Array.isArray(over.args) ? over.args.map(String) : base.args.slice()
  }
}

function normalizeTasks(tasks) {
  var out = []
  var i, t
  if (isObject(tasks)) {
    for (t in tasks) out.push({ name: t, command: String(tasks[t]), requires: "" })
  } else if (Array.isArray(tasks)) {
    for (i = 0; i < tasks.length; i++) {
      var item = tasks[i]
      if (isObject(item) && item.name)
        out.push({ name: String(item.name), command: String(item.command || ""), requires: String(item.requires || "") })
      else if (typeof item === "string") out.push({ name: item, command: "", requires: "" })
    }
  }
  return out
}

function normalizeGlobalActions(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length; i++) {
    var a = list[i]
    if (!isObject(a) || !a.command || !a.name) continue
    out.push({ name: String(a.name), command: String(a.command), requires: String(a.requires || "") })
  }
  return out
}

function normalizeProjects(list, home) {
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!isObject(p) || !p.path) continue
    var path = expandPath(String(p.path), home)
    out.push({
      name: String(p.name || basename(path)),
      path: path,
      editor: p.editor ? String(p.editor) : "",
      tags: Array.isArray(p.tags) ? p.tags.map(String) : [],
      tasks: normalizeTasks(p.tasks),
      pinned: !!p.pinned
    })
  }
  return out
}

function normalizeConfig(raw, home) {
  var base = defaultConfig()
  var parsed = raw
  if (typeof raw === "string") {
    parsed = null
    var text = String(raw).trim()
    if (text.length > 0) {
      try { parsed = JSON.parse(text) } catch (e) { parsed = null }
    }
  }
  if (!isObject(parsed)) parsed = {}

  var config = {
    version: 1,
    defaultEditor: base.defaultEditor,
    scale: 0,
    tasksInTerminal: parsed.tasksInTerminal === undefined ? base.tasksInTerminal : !!parsed.tasksInTerminal,
    terminal: mergeTerminal(base.terminal, parsed.terminal),
    scan: mergeScan(base.scan, parsed.scan),
    discovery: mergeDiscovery(base.discovery, parsed.discovery),
    editors: mergeEditors(base.editors, parsed.editors),
    actions: normalizeGlobalActions(parsed.actions),
    templates: Array.isArray(parsed.templates) ? parsed.templates : [],
    projects: normalizeProjects(parsed.projects, home)
  }

  var requestedScale = Number(parsed.scale)
  if (isFinite(requestedScale) && requestedScale > 0) config.scale = requestedScale

  if (typeof parsed.defaultEditor === "string" && config.editors[parsed.defaultEditor])
    config.defaultEditor = parsed.defaultEditor
  if (!config.editors[config.defaultEditor]) {
    var keys = Object.keys(config.editors)
    config.defaultEditor = keys.length > 0 ? keys[0] : "vscode"
  }
  return config
}

// ---------------------------------------------------------------- state

function defaultState() {
  return { version: 1, editorOverrides: {}, pinned: {}, lastOpened: "", filter: "", scale: 0 }
}

function normalizeState(raw) {
  var parsed = raw
  if (typeof raw === "string") {
    parsed = null
    var text = String(raw).trim()
    if (text.length > 0) { try { parsed = JSON.parse(text) } catch (e) { parsed = null } }
  }
  if (!isObject(parsed)) parsed = {}
  var base = defaultState()
  var overrides = {}
  if (isObject(parsed.editorOverrides)) {
    for (var k in parsed.editorOverrides) {
      if (parsed.editorOverrides[k]) overrides[k] = String(parsed.editorOverrides[k])
    }
  }
  var pinned = {}
  if (isObject(parsed.pinned)) {
    for (var p in parsed.pinned) pinned[p] = !!parsed.pinned[p]
  }
  var scale = Number(parsed.scale)
  return {
    version: 1,
    editorOverrides: overrides,
    pinned: pinned,
    lastOpened: typeof parsed.lastOpened === "string" ? parsed.lastOpened : base.lastOpened,
    filter: typeof parsed.filter === "string" ? parsed.filter : base.filter,
    scale: isFinite(scale) && scale > 0 ? scale : base.scale
  }
}

// --------------------------------------------------------------- merge

function mergeTasks(auto, configured) {
  var out = []
  var seen = {}
  var i
  var conf = Array.isArray(configured) ? configured : []
  for (i = 0; i < conf.length; i++) {
    var c = conf[i]
    if (!c || !c.name) continue
    seen[String(c.name).toLowerCase()] = true
    out.push({ name: c.name, command: c.command || "", requires: c.requires || "", source: "config" })
  }
  var au = Array.isArray(auto) ? auto : []
  for (i = 0; i < au.length; i++) {
    var a = au[i]
    if (!a || !a.name || seen[String(a.name).toLowerCase()]) continue
    seen[String(a.name).toLowerCase()] = true
    out.push({ name: a.name, command: a.command || "", requires: a.requires || "", source: "auto" })
  }
  return out
}

function buildProject(path, name, git, meta, config, state, godot, types, autoTasks) {
  var explicitEditor = meta && meta.editor && config.editors[meta.editor] ? meta.editor : ""
  var override = state && state.editorOverrides ? state.editorOverrides[path] : ""
  if (override && config.editors[override]) explicitEditor = override

  var labelId = explicitEditor
  if (!labelId && godot && config.editors.godot) labelId = "godot"
  if (!labelId) labelId = config.defaultEditor
  var editor = config.editors[labelId]

  var pinned = meta ? !!meta.pinned : false
  if (state && state.pinned && Object.prototype.hasOwnProperty.call(state.pinned, path))
    pinned = !!state.pinned[path]

  return {
    name: String(name || basename(path)),
    path: path,
    editor: explicitEditor,
    editorId: labelId,
    editorLabel: editor ? editor.label : labelId,
    godot: !!godot,
    types: Array.isArray(types) ? types.slice() : [],
    tags: meta && Array.isArray(meta.tags) ? meta.tags.slice() : [],
    tasks: mergeTasks(autoTasks, meta && meta.tasks),
    pinned: pinned,
    git: git || null
  }
}

function mergeProjects(scanned, config, state, home) {
  var explicit = config.projects || []
  var byPath = {}
  var i
  for (i = 0; i < explicit.length; i++) byPath[pathKey(explicit[i].path)] = explicit[i]

  var out = []
  var used = {}
  var list = Array.isArray(scanned) ? scanned : []
  for (i = 0; i < list.length; i++) {
    var s = list[i]
    var key = pathKey(s.path)
    used[key] = true
    out.push(buildProject(s.path, s.name, s.git, byPath[key], config, state, s.godot, s.types, s.tasks))
  }

  for (i = 0; i < explicit.length; i++) {
    var key2 = pathKey(explicit[i].path)
    if (used[key2]) continue
    out.push(buildProject(explicit[i].path, explicit[i].name, null, explicit[i], config, state, false, [], []))
  }
  return out
}

// ------------------------------------------------------------ ranking

function frecencyScore(entry, now) {
  if (!isObject(entry)) return 0
  var count = Number(entry.count || 0)
  var last = Number(entry.last || 0)
  if (!count || !last) return 0
  var hours = Math.max(0, (Number(now || 0) - last) / 3600000)
  var recency = 1 / (1 + hours / 24)
  return count * recency
}

function rankProjects(projects, usage, now) {
  var list = Array.isArray(projects) ? projects.slice() : []
  var u = isObject(usage) ? usage : {}
  list.sort(function (a, b) {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    var sa = frecencyScore(u[a.path], now)
    var sb = frecencyScore(u[b.path], now)
    if (Math.abs(sa - sb) > 1e-9) return sb - sa
    return String(a.name).localeCompare(String(b.name))
  })
  return list
}

// Fuzzy subsequence score. 0 means "not a subsequence". Contiguous and
// word-boundary matches score highest.
function fuzzyScore(text, query) {
  var t = String(text == null ? "" : text).toLowerCase()
  var q = String(query == null ? "" : query).toLowerCase()
  if (!q || !t) return 0
  var ti = 0, score = 0, streak = 0
  for (var qi = 0; qi < q.length; qi++) {
    var ch = q.charAt(qi)
    var found = -1
    for (var j = ti; j < t.length; j++) {
      if (t.charAt(j) === ch) { found = j; break }
    }
    if (found < 0) return 0
    if (found === ti) { streak++; score += 3 + streak } else { streak = 0; score += 1 }
    if (found === 0 || /[ \/_.-]/.test(t.charAt(found - 1))) score += 4
    ti = found + 1
  }
  if (t.indexOf(q) >= 0) score += 25
  score -= (t.length - q.length) * 0.05
  return score > 0 ? score : 0.001
}

function projectMatchScore(p, query, typeLabels) {
  var fields = [
    [p.name, 3],
    [(p.tags || []).join(" "), 2],
    [p.path, 1],
    [p.editorLabel, 1],
    [p.git ? p.git.branch : "", 1],
    [(typeLabels || []).join(" "), 1]
  ]
  var best = 0
  for (var i = 0; i < fields.length; i++) {
    var s = fuzzyScore(fields[i][0], query) * fields[i][1]
    if (s > best) best = s
  }
  return best
}

function filterProjects(projects, query, typeLabelsFor) {
  var list = Array.isArray(projects) ? projects : []
  var q = String(query == null ? "" : query).trim()
  if (!q) return list.slice()
  var scored = []
  for (var i = 0; i < list.length; i++) {
    var labels = typeof typeLabelsFor === "function" ? typeLabelsFor(list[i]) : null
    var s = projectMatchScore(list[i], q, labels)
    if (s > 0) scored.push({ p: list[i], s: s })
  }
  scored.sort(function (a, b) {
    if (Math.abs(a.s - b.s) > 1e-9) return b.s - a.s
    return String(a.p.name).localeCompare(String(b.p.name))
  })
  var out = []
  for (var k = 0; k < scored.length; k++) out.push(scored[k].p)
  return out
}

// Build the display rows for a query. With an empty query the ranked list is
// grouped into Pinned / Recent / All with headers; while filtering it stays a
// flat, score-ordered list.
function buildRows(projects, usage, now, query, typeLabelsFor) {
  var q = String(query == null ? "" : query).trim()
  var list = Array.isArray(projects) ? projects : []

  function row(p) {
    var r = projectRow(p)
    r.kind = "project"
    return r
  }

  if (q) {
    var filtered = filterProjects(list, q, typeLabelsFor)
    var out = []
    for (var i = 0; i < filtered.length; i++) out.push(row(filtered[i]))
    return out
  }

  var u = isObject(usage) ? usage : {}
  var pinned = [], recent = [], rest = []
  for (var j = 0; j < list.length; j++) {
    var p = list[j]
    if (p.pinned) pinned.push(p)
    else if (frecencyScore(u[p.path], now) > 0) recent.push(p)
    else rest.push(p)
  }

  var rows = []
  function pushGroup(label, group) {
    if (group.length === 0) return
    rows.push({ kind: "header", label: label, count: group.length })
    for (var k = 0; k < group.length; k++) rows.push(row(group[k]))
  }
  pushGroup("Pinned", pinned)
  pushGroup("Recent", recent)
  pushGroup("All projects", rest)
  return rows
}

function escapeHtml(text) {
  return String(text == null ? "" : text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function highlightHtml(text, query) {
  var t = String(text == null ? "" : text)
  var q = String(query == null ? "" : query).trim().toLowerCase()
  if (!q) return escapeHtml(t)
  var tl = t.toLowerCase()
  var positions = []
  var ti = 0
  for (var qi = 0; qi < q.length; qi++) {
    var found = -1
    for (var j = ti; j < tl.length; j++) {
      if (tl.charAt(j) === q.charAt(qi)) { found = j; break }
    }
    if (found < 0) return escapeHtml(t)
    positions.push(found)
    ti = found + 1
  }
  var mark = {}
  for (var k = 0; k < positions.length; k++) mark[positions[k]] = true
  var out = ""
  var open = false
  for (var x = 0; x < t.length; x++) {
    var isMark = !!mark[x]
    if (isMark && !open) { out += "<b>"; open = true }
    else if (!isMark && open) { out += "</b>"; open = false }
    out += escapeHtml(t.charAt(x))
  }
  if (open) out += "</b>"
  return out
}

// ------------------------------------------------------------ formatting

function gitSummary(git) {
  if (!git) return ""
  var branch = git.branch && git.branch !== "(detached)" ? git.branch : "detached"
  var s = branch
  if (git.dirty) s += "*"
  if (Number(git.ahead) > 0) s += " \u2191" + git.ahead
  if (Number(git.behind) > 0) s += " \u2193" + git.behind
  return s
}

function relativeTime(ms, now) {
  var t = Number(ms || 0)
  if (!t) return ""
  var secs = Math.max(0, (Number(now || Date.now()) - t) / 1000)
  if (secs < 60) return "just now"
  var mins = Math.floor(secs / 60)
  if (mins < 60) return mins + (mins === 1 ? " min ago" : " mins ago")
  var hours = Math.floor(mins / 60)
  if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago")
  var days = Math.floor(hours / 24)
  if (days < 30) return days + (days === 1 ? " day ago" : " days ago")
  var months = Math.floor(days / 30)
  if (months < 12) return months + (months === 1 ? " month ago" : " months ago")
  return Math.floor(months / 12) + "y ago"
}

function remoteToWebUrl(remote) {
  var r = String(remote == null ? "" : remote).trim()
  if (!r) return ""
  r = r.replace(/\.git$/, "")
  var m = r.match(/^git@([^:]+):(.+)$/)
  if (m) return "https://" + m[1] + "/" + m[2]
  m = r.match(/^ssh:\/\/git@([^/]+)\/(.+)$/)
  if (m) return "https://" + m[1] + "/" + m[2]
  m = r.match(/^git:\/\/([^/]+)\/(.+)$/)
  if (m) return "https://" + m[1] + "/" + m[2]
  if (r.indexOf("http://") === 0 || r.indexOf("https://") === 0) return r
  return ""
}

function projectRow(project) {
  var git = project.git
  return {
    name: project.name,
    path: project.path,
    editorLabel: project.editorLabel,
    editorId: project.editorId,
    icon: project.icon || "",
    typeLabel: project.typeLabel || "",
    types: project.types || [],
    tags: project.tags || [],
    gitText: gitSummary(git),
    branch: git ? git.branch : "",
    dirty: !!(git && git.dirty),
    hasGit: !!git,
    hasRemote: !!(git && git.remote),
    stash: git ? Number(git.stash || 0) : 0,
    commit: git ? String(git.commit || "") : "",
    commitAt: git ? Number(git.commitAt || 0) : 0,
    pinned: !!project.pinned,
    project: project
  }
}

// ------------------------------------------------------------- actions

function commandAvailable(cmd, available) {
  var c = String(cmd == null ? "" : cmd)
  if (!c) return false
  var list = Array.isArray(available) ? available : []
  if (list.indexOf(c) >= 0) return true
  var base = c.split("/").pop()
  return list.indexOf(base) >= 0
}

function availableEditors(config, available) {
  var out = []
  var editors = config.editors || {}
  for (var id in editors) {
    if (editors[id].command && commandAvailable(editors[id].command, available)) out.push(id)
  }
  return out
}

function actionsFor(project, config, available, effectiveEditorId) {
  var actions = []
  var editorId = effectiveEditorId && config.editors[effectiveEditorId] ? effectiveEditorId : ""
  if (!editorId && project.godot && config.editors.godot
      && commandAvailable(config.editors.godot.command, available)) editorId = "godot"
  if (!editorId) editorId = config.defaultEditor
  var editor = config.editors[editorId] || config.editors[config.defaultEditor]

  if (editor) {
    var actionKind = "editor-gui"
    if (editor.kind === "terminal") actionKind = "editor-terminal"
    else if (editor.kind === "direct") actionKind = "editor-direct"
    actions.push({
      id: "editor:" + editorId,
      kind: actionKind,
      label: "Open in " + editor.label,
      hint: "Enter",
      enabled: commandAvailable(editor.command, available),
      editorId: editorId
    })
  }

  actions.push({ id: "terminal", kind: "terminal", label: "Open terminal here", hint: "\u21e7Enter", enabled: true })
  actions.push({ id: "files", kind: "files", label: "Open file manager", hint: "\u2325Enter", enabled: commandAvailable("xdg-open", available) })

  var url = project.git ? remoteToWebUrl(project.git.remote) : ""
  actions.push({
    id: "github", kind: "github",
    label: url ? "Open repository in browser" : "No repository remote",
    hint: "Ctrl G", enabled: !!url, url: url
  })

  actions.push({ id: "copy", kind: "copy", label: "Copy project path", hint: "Ctrl Y", enabled: commandAvailable("wl-copy", available) })
  actions.push({
    id: "pin", kind: "pin",
    label: project.pinned ? "Unpin project" : "Pin project",
    hint: "Ctrl P", enabled: true
  })

  if (project.git) {
    actions.push({
      id: "git:lazygit", kind: "terminal-cmd", label: "Open in lazygit",
      hint: "Ctrl \u21e7G", enabled: commandAvailable("lazygit", available), command: "lazygit"
    })
  }

  var globalActions = config.actions || []
  for (var g = 0; g < globalActions.length; g++) {
    var ga = globalActions[g]
    actions.push({
      id: "global:" + ga.name, kind: "global", label: ga.name,
      hint: "", enabled: !ga.requires || commandAvailable(ga.requires, available),
      command: ga.command, requires: ga.requires
    })
  }

  var tasks = project.tasks || []
  for (var i = 0; i < tasks.length; i++) {
    var t = tasks[i]
    var ok = !t.requires || commandAvailable(t.requires, available)
    actions.push({
      id: "task:" + t.name, kind: "task", label: "Run task: " + t.name,
      hint: i < 9 ? "Ctrl " + (i + 1) : "", enabled: ok,
      command: t.command, requires: t.requires || ""
    })
  }
  return actions
}

// argv for a terminal rooted at `dir`, running `command` under bash and
// holding the window open so output stays readable. `command` empty just
// opens a shell in the directory.
function terminalArgv(dir, command, appId, config) {
  var terminal = (config && config.terminal) || { command: "xdg-terminal-exec", args: ["--dir={path}"] }
  var rendered = (terminal.args || ["--dir={path}"]).map(function (a) {
    return String(a).replace(/\{path\}/g, String(dir == null ? "" : dir))
  })
  var argv = ["setsid", "uwsm-app", "--", String(terminal.command || "xdg-terminal-exec")].concat(rendered)
  if (appId) argv.push("--app-id=" + appId)
  var cmd = String(command == null ? "" : command)
  if (cmd) {
    var hold = "; st=$?; printf '\\n[exit %s] ' \"$st\"; read -r _"
    argv.push("-e", "bash", "-lc", cmd + hold)
  }
  return { argv: argv }
}

function commandFor(action, project, config) {
  if (!action) return null
  var path = project ? project.path : ""

  if (action.kind === "editor-gui" || action.kind === "editor-terminal" || action.kind === "editor-direct") {
    var editor = config.editors[action.editorId] || config.editors[config.defaultEditor]
    if (!editor) return null
    var args = editor.args || ["{path}"]
    var rendered = []
    for (var i = 0; i < args.length; i++) rendered.push(String(args[i]).replace("{path}", path))
    var cmd = [editor.command].concat(rendered)
    if (editor.kind === "terminal")
      return terminalArgv(path, shellQuote(cmd[0]) + " " + cmd.slice(1).map(shellQuote).join(" "), "kalel.project-manager.editor", config)
    if (editor.kind === "direct") return { argv: cmd }
    return { argv: ["setsid", "uwsm-app", "--"].concat(cmd) }
  }

  if (action.kind === "terminal") return terminalArgv(path, "", "kalel.project-manager.terminal", config)
  if (action.kind === "files") return { argv: ["setsid", "uwsm-app", "--", "xdg-open", path] }
  if (action.kind === "github") {
    if (!action.url) return null
    return { argv: ["setsid", "uwsm-app", "--", "omarchy-launch-browser", action.url] }
  }
  if (action.kind === "copy") return { shell: "printf %s " + shellQuote(path) + " | wl-copy" }
  if (action.kind === "pin") return null // handled by the overlay

  if (action.kind === "terminal-cmd" || action.kind === "global") {
    if (!action.command) return null
    var rendered2 = String(action.command).replace(/\{path\}/g, path)
    return terminalArgv(path, "cd " + shellQuote(path) + " && " + rendered2, "kalel.project-manager.task", config)
  }

  if (action.kind === "task") {
    if (!action.command) return null
    var c = "cd " + shellQuote(path) + " && " + action.command
    if (config && config.tasksInTerminal === false) return { shell: c }
    return terminalArgv(path, c, "kalel.project-manager.task", config)
  }
  return null
}

// -------------------------------------------------------- clone / root

function defaultRoot(config, home) {
  var roots = (config && config.discovery && config.discovery.roots) || []
  if (roots.length > 0) return expandPath(roots[0], home)
  return expandPath("~/Projects", home)
}

function sanitizeProjectName(name) {
  var n = String(name == null ? "" : name).trim().replace(/^[-]+/, "")
  if (!n || n.indexOf("/") >= 0 || n === "." || n === "..") return ""
  return n
}

function cloneCommand(config, home, url) {
  var u = String(url == null ? "" : url).trim()
  if (!/^(https?:\/\/|git@|ssh:\/\/|git:\/\/|file:\/\/|\/)/.test(u)) return null
  var root = defaultRoot(config, home)
  return terminalArgv(root, "git clone " + shellQuote(u), "kalel.project-manager.clone", config)
}

// ---------------------------------------------------------------- usage

function parseUsage(raw) {
  try {
    var data = JSON.parse(String(raw == null ? "" : raw))
    if (!isObject(data)) return {}
    var out = {}
    for (var k in data) {
      if (!isObject(data[k])) continue
      out[k] = { count: Number(data[k].count || 0) || 0, last: Number(data[k].last || 0) || 0 }
    }
    return out
  } catch (e) {
    return {}
  }
}

function recordUsage(usage, path, now) {
  var out = {}
  for (var k in usage) out[k] = usage[k]
  var entry = out[path] || { count: 0, last: 0 }
  out[path] = { count: (Number(entry.count || 0) || 0) + 1, last: Number(now || 0) }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    isObject: isObject,
    expandPath: expandPath,
    basename: basename,
    pathKey: pathKey,
    shellQuote: shellQuote,
    defaultConfig: defaultConfig,
    normalizeConfig: normalizeConfig,
    normalizeEditor: normalizeEditor,
    mergeEditors: mergeEditors,
    defaultState: defaultState,
    normalizeState: normalizeState,
    mergeProjects: mergeProjects,
    rankProjects: rankProjects,
    frecencyScore: frecencyScore,
    filterProjects: filterProjects,
    buildRows: buildRows,
    projectRow: projectRow,
    gitSummary: gitSummary,
    relativeTime: relativeTime,
    remoteToWebUrl: remoteToWebUrl,
    fuzzyScore: fuzzyScore,
    projectMatchScore: projectMatchScore,
    highlightHtml: highlightHtml,
    escapeHtml: escapeHtml,
    commandAvailable: commandAvailable,
    availableEditors: availableEditors,
    actionsFor: actionsFor,
    commandFor: commandFor,
    terminalArgv: terminalArgv,
    defaultRoot: defaultRoot,
    sanitizeProjectName: sanitizeProjectName,
    cloneCommand: cloneCommand,
    parseUsage: parseUsage,
    recordUsage: recordUsage
  }
}
