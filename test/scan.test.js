const { test } = require("node:test")
const assert = require("node:assert/strict")
const Scan = require("../Scan.js")

test("scanArgs includes roots, depth, exclude and editor commands", () => {
  const cfg = {
    discovery: { enabled: true, roots: ["~/Projects", "/opt/dev"], maxDepth: 4, exclude: ["node_modules"] },
    scan: { concurrency: 8, untracked: true },
    terminal: { command: "foot" },
    actions: [{ name: "x", command: "y", requires: "make" }],
    editors: { vscode: { command: "code" } },
    projects: [{ path: "~/Projects/foo" }]
  }
  const args = Scan.scanArgs(cfg, "/p/discover.sh", "/home/u")
  assert.deepEqual(args.slice(0, 3), ["bash", "/p/discover.sh", "scan"])
  assert.ok(args.includes("--root") && args.includes("/home/u/Projects"))
  assert.ok(args.includes("--depth") && args[args.indexOf("--depth") + 1] === "4")
  assert.ok(args.includes("--concurrency") && args[args.indexOf("--concurrency") + 1] === "8")
  assert.ok(args.includes("--editor-command") && args.includes("code"))
  assert.ok(args.includes("--need") && args.includes("make") && args.includes("foot"))
  assert.ok(args.includes("--"))
  assert.ok(args.includes("/home/u/Projects/foo"))
})

test("scanArgs adds --no-untracked when disabled and omits roots when discovery off", () => {
  const cfg = { discovery: { enabled: false, roots: ["~/x"] }, scan: { untracked: false }, editors: {}, projects: [] }
  const args = Scan.scanArgs(cfg, "/p", "/h")
  assert.ok(args.includes("--no-untracked"))
  assert.equal(args.includes("--root"), false)
})

test("parseScan normalizes projects and git", () => {
  const raw = JSON.stringify({
    projects: [
      { name: "a", path: "/a", git: { branch: "main", dirty: true, ahead: 1, behind: 0, remote: "r", commit: "s", commitAt: 5, stash: 2 }, types: ["go"], tasks: [{ name: "t", command: "c", requires: "go" }] },
      { path: "/b" },
      { name: "drop" } // no path -> ignored
    ],
    availableCommands: ["git", "code"]
  })
  const out = Scan.parseScan(raw)
  assert.equal(out.projects.length, 2)
  assert.equal(out.projects[0].git.dirty, true)
  assert.equal(out.projects[0].git.stash, 2)
  assert.equal(out.projects[1].name, "b")
  assert.deepEqual(out.availableCommands, ["git", "code"])
})

test("parseScan returns null on malformed input", () => {
  assert.equal(Scan.parseScan("{not json"), null)
  assert.equal(Scan.parseScan(""), null)
})
