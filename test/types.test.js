const { test } = require("node:test")
const assert = require("node:assert/strict")
const Types = require("../Types.js")

test("primaryType honours priority order", () => {
  assert.equal(Types.primaryType(["node", "rust"]), "rust")
  assert.equal(Types.primaryType(["node", "docker"]), "node")
  assert.equal(Types.primaryType([]), "")
})

test("typeIcon and typeLabel resolve a known type", () => {
  assert.equal(Types.typeLabel(["go"]), "Go")
  assert.ok(Types.typeIcon(["go"]).length > 0)
  assert.equal(Types.typeLabel(["mystery"]), "")
})

test("typeLabels lists every recognised type in priority order", () => {
  assert.deepEqual(Types.typeLabels(["make", "go"]), ["Go", "Make"])
  assert.deepEqual(Types.typeLabels(["unknown"]), [])
})

test("PRIORITY only references known types", () => {
  for (const id of Types.PRIORITY) assert.ok(Types.known(id), id + " should be known")
})
