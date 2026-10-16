const { test } = require("node:test")
const assert = require("node:assert/strict")
const Templates = require("../Templates.js")

test("allTemplates returns the built-ins", () => {
  const ids = Templates.allTemplates([]).map(t => t.id)
  assert.ok(ids.includes("node"))
  assert.ok(ids.includes("rust"))
  assert.ok(ids.includes("generic"))
})

test("allTemplates merges user templates and skips duplicate ids", () => {
  const list = Templates.allTemplates([
    { id: "custom", label: "Custom", files: { "a.txt": "hi" } },
    { id: "node", label: "Shadowed" }
  ])
  const custom = list.find(t => t.id === "custom")
  assert.ok(custom)
  assert.equal(list.find(t => t.id === "node").label, "Node") // built-in kept
})

test("sanitizeName rejects traversal and empties", () => {
  assert.equal(Templates.sanitizeName(""), "")
  assert.equal(Templates.sanitizeName("../x"), "")
  assert.equal(Templates.sanitizeName(".hidden"), "hidden")
  assert.equal(Templates.sanitizeName("my-app"), "my-app")
})

test("scaffoldScript writes files, runs commands and git-inits", () => {
  const t = Templates.templateById("node", [])
  const script = Templates.scaffoldScript(t, "/home/u/Projects/my-app", "my-app")
  assert.match(script, /mkdir -p '\/home\/u\/Projects\/my-app'/)
  assert.match(script, /base64 -d > '\/home\/u\/Projects\/my-app\/package\.json'/)
  assert.match(script, /git -C '\/home\/u\/Projects\/my-app' init -q/)
  // The name is substituted into the package.json payload (base64).
  const decoded = Buffer.from(
    script.match(/printf %s '([^']+)' \| base64 -d > '[^']*package\.json'/)[1], "base64"
  ).toString("utf8")
  assert.match(decoded, /"name": "my-app"/)
})

test("scaffoldScript runs post commands for the rust template", () => {
  const t = Templates.templateById("rust", [])
  const script = Templates.scaffoldScript(t, "/tmp/x", "x")
  assert.match(script, /cd '\/tmp\/x' && cargo init --name "x" \./)
})

test("scaffoldScript returns empty for bad input", () => {
  assert.equal(Templates.scaffoldScript(null, "/tmp/x", "x"), "")
  assert.equal(Templates.scaffoldScript(Templates.templateById("node", []), "/tmp/x", "../evil"), "")
})
