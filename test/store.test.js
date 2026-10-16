const { test } = require("node:test")
const assert = require("node:assert/strict")
const Store = require("../Store.js")

const HOME = "/home/user"

test("defaultConfig is complete and normalizes cleanly", () => {
  const cfg = Store.normalizeConfig("", HOME)
  assert.equal(cfg.defaultEditor, "omarchy")
  assert.ok(cfg.editors.omarchy)
  assert.ok(cfg.terminal.command)
  assert.deepEqual(cfg.projects, [])
})

test("normalizeConfig parses JSON, overrides and merges editors", () => {
  const cfg = Store.normalizeConfig(JSON.stringify({
    defaultEditor: "nvim",
    discovery: { roots: ["~/dev"], maxDepth: 5 },
    editors: { mine: { label: "Mine", command: "mine", args: ["{path}"], kind: "gui" } },
    actions: [{ name: "Ship", command: "make ship", requires: "make" }]
  }), HOME)
  assert.equal(cfg.defaultEditor, "nvim")
  assert.deepEqual(cfg.discovery.roots, ["~/dev"])
  assert.equal(cfg.discovery.maxDepth, 5)
  assert.ok(cfg.editors.mine)
  assert.ok(cfg.editors.omarchy) // base editor preserved
  assert.equal(cfg.actions[0].name, "Ship")
})

test("normalizeConfig falls back to a valid defaultEditor", () => {
  const cfg = Store.normalizeConfig(JSON.stringify({ defaultEditor: "nope" }), HOME)
  assert.ok(cfg.editors[cfg.defaultEditor])
})

test("expandPath handles ~ and ~/", () => {
  assert.equal(Store.expandPath("~", HOME), HOME)
  assert.equal(Store.expandPath("~/Projects", HOME), HOME + "/Projects")
  assert.equal(Store.expandPath("/abs", HOME), "/abs")
})

test("mergeProjects attaches config metadata and state overrides", () => {
  const config = Store.normalizeConfig(JSON.stringify({
    projects: [{ path: "~/Projects/foo", editor: "nvim", tags: ["a"], pinned: false }]
  }), HOME)
  const state = Store.normalizeState(JSON.stringify({
    editorOverrides: { [HOME + "/Projects/foo"]: "vscode" },
    pinned: { [HOME + "/Projects/foo"]: true }
  }))
  const scanned = [{ name: "foo", path: HOME + "/Projects/foo", git: { branch: "main" }, types: ["go"], tasks: [] }]
  const merged = Store.mergeProjects(scanned, config, state, HOME)
  assert.equal(merged.length, 1)
  assert.equal(merged[0].editorId, "vscode") // state override wins
  assert.equal(merged[0].pinned, true)       // state override wins
  assert.deepEqual(merged[0].tags, ["a"])
})

test("mergeProjects keeps configured projects the scan missed", () => {
  const config = Store.normalizeConfig(JSON.stringify({
    projects: [{ path: "~/gone" }]
  }), HOME)
  const merged = Store.mergeProjects([], config, Store.normalizeState(""), HOME)
  assert.equal(merged.length, 1)
  assert.equal(merged[0].path, HOME + "/gone")
  assert.equal(merged[0].git, null)
})

test("rankProjects pins first, then orders by frecency", () => {
  const now = 1_000_000_000_000
  const projects = [
    { name: "a", path: "/a", pinned: false },
    { name: "b", path: "/b", pinned: true },
    { name: "c", path: "/c", pinned: false }
  ]
  const usage = {
    "/a": { count: 1, last: now - 3600_000 },   // recent
    "/c": { count: 50, last: now - 10000 * 3600_000 } // old
  }
  const ranked = Store.rankProjects(projects, usage, now)
  assert.equal(ranked[0].name, "b") // pinned
  assert.equal(ranked[1].name, "a") // high frecency
  assert.equal(ranked[2].name, "c")
})

test("fuzzyScore matches subsequences and rejects non-matches", () => {
  assert.ok(Store.fuzzyScore("project-manager", "pm") > 0)
  assert.equal(Store.fuzzyScore("abc", "xyz"), 0)
  assert.ok(Store.fuzzyScore("abc", "ABC") > 0) // case-insensitive
})

test("filterProjects ranks name matches above path matches", () => {
  const list = [
    { name: "unrelated", path: "/deep/fooName", editorLabel: "", tags: [], git: null },
    { name: "foo", path: "/foo", editorLabel: "", tags: [], git: null }
  ]
  const out = Store.filterProjects(list, "foo")
  assert.equal(out[0].name, "foo")
})

test("buildRows groups when idle and flattens when filtering", () => {
  const now = Date.now()
  const list = [
    { name: "pin", path: "/pin", pinned: true, tags: [], git: null, types: [] },
    { name: "rec", path: "/rec", pinned: false, tags: [], git: null, types: [] },
    { name: "other", path: "/other", pinned: false, tags: [], git: null, types: [] }
  ]
  const usage = { "/rec": { count: 2, last: now } }
  const grouped = Store.buildRows(list, usage, now, "")
  assert.equal(grouped[0].kind, "header")
  assert.equal(grouped[0].label, "Pinned")
  const labels = grouped.filter(r => r.kind === "header").map(r => r.label)
  assert.deepEqual(labels, ["Pinned", "Recent", "All projects"])
  const flat = Store.buildRows(list, usage, now, "rec")
  assert.ok(flat.every(r => r.kind === "project"))
})

test("highlightHtml wraps matched chars and escapes html", () => {
  assert.equal(Store.highlightHtml("abc", "ac"), "<b>a</b>b<b>c</b>")
  assert.equal(Store.highlightHtml("a<b", ""), "a&lt;b")
})

test("gitSummary shows branch, dirty, ahead and behind", () => {
  assert.equal(Store.gitSummary({ branch: "main", dirty: true, ahead: 2, behind: 1 }), "main* \u21912 \u21931")
  assert.equal(Store.gitSummary(null), "")
})

test("relativeTime formats ages", () => {
  const now = 1_000_000_000_000
  assert.equal(Store.relativeTime(now - 30_000, now), "just now")
  assert.equal(Store.relativeTime(now - 5 * 60_000, now), "5 mins ago")
  assert.equal(Store.relativeTime(now - 3 * 3600_000, now), "3 hours ago")
})

test("remoteToWebUrl converts ssh and git remotes", () => {
  assert.equal(Store.remoteToWebUrl("git@github.com:a/b.git"), "https://github.com/a/b")
  assert.equal(Store.remoteToWebUrl("https://github.com/a/b.git"), "https://github.com/a/b")
  assert.equal(Store.remoteToWebUrl("not-a-url"), "")
})

test("actionsFor includes editor, terminal, files, browser, copy, pin, tasks", () => {
  const cfg = Store.normalizeConfig("", HOME)
  const project = {
    path: "/p", godot: false, pinned: false, types: ["go"],
    git: { branch: "main", remote: "git@github.com:a/b.git", dirty: false, ahead: 0, behind: 0 },
    tasks: [{ name: "test", command: "go test", requires: "go" }]
  }
  const ids = Store.actionsFor(project, cfg, ["xdg-open", "wl-copy", "lazygit"], "").map(a => a.id)
  assert.ok(ids.includes("terminal"))
  assert.ok(ids.includes("files"))
  assert.ok(ids.includes("copy"))
  assert.ok(ids.includes("pin"))
  assert.ok(ids.includes("github"))
  assert.ok(ids.includes("git:lazygit"))
  assert.ok(ids.includes("task:test"))
})

test("actionsFor greys out tasks with missing tools", () => {
  const cfg = Store.normalizeConfig("", HOME)
  const project = { path: "/p", pinned: false, git: null, types: [], tasks: [{ name: "t", command: "x", requires: "nope" }] }
  const task = Store.actionsFor(project, cfg, [], "").find(a => a.id === "task:t")
  assert.equal(task.enabled, false)
})

test("commandFor renders editor args with the project path", () => {
  const cfg = Store.normalizeConfig(JSON.stringify({
    editors: { vscode: { label: "Code", command: "code", args: ["-n", "{path}"], kind: "gui" } }
  }), HOME)
  const out = Store.commandFor({ kind: "editor-gui", editorId: "vscode" }, { path: "/p" }, cfg)
  assert.deepEqual(out.argv, ["setsid", "uwsm-app", "--", "code", "-n", "/p"])
})

test("commandFor builds a shell command for copy", () => {
  const cfg = Store.normalizeConfig("", HOME)
  const out = Store.commandFor({ kind: "copy" }, { path: "/p q" }, cfg)
  assert.equal(out.shell, "printf %s '/p q' | wl-copy")
})

test("cloneCommand rejects junk urls and accepts real ones", () => {
  const cfg = Store.normalizeConfig("", HOME)
  assert.equal(Store.cloneCommand(cfg, HOME, "rm -rf /"), null)
  assert.ok(Store.cloneCommand(cfg, HOME, "https://github.com/a/b.git").argv)
})

test("usage round-trips through parse/record", () => {
  let usage = Store.parseUsage("{}")
  usage = Store.recordUsage(usage, "/a", 1000)
  usage = Store.recordUsage(usage, "/a", 2000)
  assert.equal(usage["/a"].count, 2)
  assert.equal(usage["/a"].last, 2000)
  assert.deepEqual(Store.parseUsage("garbage"), {})
})

test("normalizeState restores editor overrides and pins", () => {
  const state = Store.normalizeState(JSON.stringify({
    editorOverrides: { "/a": "nvim" }, pinned: { "/a": true }, lastOpened: "/a"
  }))
  assert.equal(state.editorOverrides["/a"], "nvim")
  assert.equal(state.pinned["/a"], true)
  assert.equal(state.lastOpened, "/a")
})
