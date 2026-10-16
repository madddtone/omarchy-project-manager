// Project Manager — new-project scaffold templates. Pure: produces a shell
// script string that the Service runs. No Qt, unit-testable with node.
//
// A template is { id, label, description, requires, files, commands, gitInit }.
//   files    - map of relative path -> file contents ({name} is substituted)
//   commands - shell lines run inside the new directory, after files are written
//   requires - a command that must exist for the template to be offered

function shellQuote(value) {
  return "'" + String(value == null ? "" : value).replace(/'/g, "'\\''") + "'"
}

function render(text, name) {
  return String(text == null ? "" : text).replace(/\{name\}/g, name)
}

var BUILTIN = [
  {
    id: "generic",
    label: "Generic",
    description: "A README, a .gitignore, and a fresh git repo.",
    requires: "",
    gitInit: true,
    files: {
      "README.md": "# {name}\n",
      ".gitignore": "*.log\n.DS_Store\n"
    },
    commands: []
  },
  {
    id: "node",
    label: "Node",
    description: "package.json, index.js, and a node .gitignore.",
    requires: "node",
    gitInit: true,
    files: {
      "package.json": "{\n  \"name\": \"{name}\",\n  \"version\": \"0.1.0\",\n  \"private\": true,\n  \"type\": \"module\",\n  \"main\": \"index.js\",\n  \"scripts\": {\n    \"start\": \"node index.js\"\n  }\n}\n",
      "index.js": "console.log(\"hello from {name}\")\n",
      ".gitignore": "node_modules/\n*.log\n",
      "README.md": "# {name}\n"
    },
    commands: []
  },
  {
    id: "python",
    label: "Python",
    description: "pyproject.toml, a main.py, and a venv .gitignore.",
    requires: "python",
    gitInit: true,
    files: {
      "pyproject.toml": "[project]\nname = \"{name}\"\nversion = \"0.1.0\"\nrequires-python = \">=3.10\"\n",
      "main.py": "def main():\n    print(\"hello from {name}\")\n\n\nif __name__ == \"__main__\":\n    main()\n",
      ".gitignore": ".venv/\n__pycache__/\n*.pyc\n",
      "README.md": "# {name}\n"
    },
    commands: []
  },
  {
    id: "rust",
    label: "Rust",
    description: "Initialise a Cargo binary crate.",
    requires: "cargo",
    gitInit: true,
    files: {},
    commands: ["cargo init --name \"{name}\" ."]
  },
  {
    id: "go",
    label: "Go",
    description: "go.mod and a main.go.",
    requires: "go",
    gitInit: true,
    files: {
      "main.go": "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hello from {name}\")\n}\n",
      ".gitignore": "/{name}\n",
      "README.md": "# {name}\n"
    },
    commands: ["go mod init \"{name}\""]
  },
  {
    id: "static",
    label: "Static site",
    description: "index.html, style.css, and a small script.",
    requires: "",
    gitInit: true,
    files: {
      "index.html": "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>{name}</title>\n  <link rel=\"stylesheet\" href=\"style.css\">\n</head>\n<body>\n  <h1>{name}</h1>\n  <script src=\"script.js\"></script>\n</body>\n</html>\n",
      "style.css": "body {\n  font-family: system-ui, sans-serif;\n  margin: 2rem;\n}\n",
      "script.js": "console.log(\"hello from {name}\")\n",
      ".gitignore": "*.log\n"
    },
    commands: []
  }
]

function sanitizeName(name) {
  var n = String(name == null ? "" : name).trim().replace(/^[-.]+/, "")
  if (!n || n.indexOf("/") >= 0 || n === "." || n === "..") return ""
  return n
}

function normalizeUserTemplate(item, index) {
  if (item === null || typeof item !== "object" || Array.isArray(item)) return null
  var id = String(item.id || item.label || "").trim()
  if (!id) id = "template-" + index
  var files = {}
  if (item.files !== null && typeof item.files === "object" && !Array.isArray(item.files)) {
    for (var k in item.files) files[String(k)] = String(item.files[k])
  }
  var commands = []
  if (Array.isArray(item.commands)) commands = item.commands.map(String)
  return {
    id: id,
    label: String(item.label || id),
    description: String(item.description || ""),
    requires: String(item.requires || ""),
    gitInit: item.gitInit === undefined ? true : !!item.gitInit,
    files: files,
    commands: commands
  }
}

function allTemplates(userTemplates) {
  var out = []
  var seen = {}
  var i
  for (i = 0; i < BUILTIN.length; i++) {
    out.push(BUILTIN[i])
    seen[BUILTIN[i].id] = true
  }
  var list = Array.isArray(userTemplates) ? userTemplates : []
  for (i = 0; i < list.length; i++) {
    var t = normalizeUserTemplate(list[i], i)
    if (!t || seen[t.id]) continue
    seen[t.id] = true
    out.push(t)
  }
  return out
}

function templateById(id, userTemplates) {
  var list = allTemplates(userTemplates)
  var key = String(id == null ? "" : id)
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === key) return list[i]
  }
  return null
}

// Build a single shell script that creates `dir`, writes every file (base64,
// so arbitrary contents are safe), runs the post-commands, and optionally
// git-inits. Returns "" for an unknown template or an invalid name.
function scaffoldScript(template, dir, name) {
  var t = template
  if (!t || !t.id) return ""
  var n = sanitizeName(name)
  if (!n) return ""
  var d = String(dir == null ? "" : dir)
  if (!d) return ""

  var lines = ["set -e", "mkdir -p " + shellQuote(d)]

  for (var rel in t.files) {
    var target = d.replace(/\/+$/, "") + "/" + rel
    var slash = target.lastIndexOf("/")
    if (slash > 0) lines.push("mkdir -p " + shellQuote(target.slice(0, slash)))
    var content = Buffer.from(render(t.files[rel], n), "utf8").toString("base64")
    lines.push("printf %s " + shellQuote(content) + " | base64 -d > " + shellQuote(target))
  }

  var cmds = Array.isArray(t.commands) ? t.commands : []
  for (var i = 0; i < cmds.length; i++) {
    var cmd = render(cmds[i], n).trim()
    if (cmd) lines.push("(cd " + shellQuote(d) + " && " + cmd + ")")
  }

  if (t.gitInit) lines.push("git -C " + shellQuote(d) + " init -q")

  return lines.join("\n") + "\n"
}

if (typeof module !== "undefined") {
  module.exports = {
    BUILTIN: BUILTIN,
    sanitizeName: sanitizeName,
    allTemplates: allTemplates,
    templateById: templateById,
    normalizeUserTemplate: normalizeUserTemplate,
    scaffoldScript: scaffoldScript,
    shellQuote: shellQuote
  }
}
