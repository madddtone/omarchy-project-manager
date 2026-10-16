import QtQuick
import Quickshell
import Quickshell.Io
import "Store.js" as Store
import "Scan.js" as Scan
import "Types.js" as Types

// Shared state hub for the Project Manager plugin. One instance runs as the
// plugin's `service`; the overlay and the bar widget both read from it, so a
// scan happens once and the bar badge stays in sync with the list.
Item {
  id: service

  property string home: Quickshell.env("HOME")
  readonly property string scriptPath: {
    var u = Qt.resolvedUrl("discover.sh").toString()
    u = u.replace(/^file:\/\//, "")
    try { u = decodeURIComponent(u) } catch (e) {}
    return u
  }

  property string configPath: service.home + "/.config/omarchy/project-manager.json"
  property string stateDir: service.home + "/.local/state/omarchy/project-manager"
  property string statePath: service.stateDir + "/state.json"
  property string usagePath: service.stateDir + "/usage.json"
  property string cachePath: service.stateDir + "/cache.json"

  property var config: Store.defaultConfig()
  // Named savedState: QQuickItem already reserves `state`.
  property var savedState: Store.defaultState()
  property var usage: ({})
  property var scanned: []
  property var availableCommands: []
  property var projects: []
  property bool scanning: false
  property bool scannedOnce: false
  property bool ready: false
  property string statusText: ""
  property double lastScanMs: 0

  readonly property int dirtyCount: {
    var n = 0
    for (var i = 0; i < service.projects.length; i++) {
      if (service.projects[i].git && service.projects[i].git.dirty) n++
    }
    return n
  }

  function expand(p) { return Store.expandPath(p, service.home) }
  function typeLabelsForRow(project) { return project.typeLabels || project.types || [] }

  // ------------------------------------------------------------- rebuild

  function rebuild() {
    var merged = Store.mergeProjects(service.scanned, service.config, service.savedState, service.home)
    // Decorate with the display type label so search can match on it.
    for (var i = 0; i < merged.length; i++) {
      merged[i].icon = Types.typeIcon(merged[i].types)
      merged[i].typeLabel = Types.typeLabel(merged[i].types)
      merged[i].typeLabels = Types.typeLabels(merged[i].types)
    }
    service.projects = Store.rankProjects(merged, service.usage, Date.now())
  }

  // ---------------------------------------------------------------- scan

  function runScan() {
    if (scanProc.running) return
    scanProc.command = Scan.scanArgs(service.config, service.scriptPath, service.home)
    service.scanning = true
    service.statusText = "Scanning projects…"
    scanProc.running = true
  }

  function onScanFinished(raw) {
    var result = Scan.parseScan(raw)
    service.scanning = false
    if (!result) {
      service.statusText = "Scan failed"
      return
    }
    service.scanned = result.projects
    service.availableCommands = result.availableCommands
    service.scannedOnce = true
    service.statusText = ""
    service.lastScanMs = Date.now()
    service.rebuild()
    cacheFile.setText(raw)
  }

  // ------------------------------------------------------------ loaders

  function loadConfig(raw) {
    service.config = Store.normalizeConfig(raw, service.home)
    service.ready = true
    service.rebuild()
    service.runScan()
  }

  function loadState(raw) {
    service.savedState = Store.normalizeState(raw)
    service.rebuild()
  }

  function loadUsage(raw) {
    service.usage = Store.parseUsage(raw)
    service.rebuild()
  }

  function loadCache(raw) {
    if (service.scannedOnce) return
    var result = Scan.parseScan(raw)
    if (!result) return
    service.scanned = result.projects
    service.availableCommands = result.availableCommands
    service.scannedOnce = true
    service.rebuild()
  }

  // --------------------------------------------------------------- state

  function writeState() {
    stateFile.setText(JSON.stringify(service.savedState, null, 2) + "\n")
  }

  function setEditorOverride(path, editorId) {
    var next = Object.assign({}, service.savedState)
    var overrides = Object.assign({}, service.savedState.editorOverrides)
    if (editorId) overrides[path] = editorId
    else delete overrides[path]
    next.editorOverrides = overrides
    service.savedState = next
    service.writeState()
    service.rebuild()
  }

  function isPinned(path) {
    return service.savedState.pinned && service.savedState.pinned[path] === true
  }

  function togglePin(path) {
    var next = Object.assign({}, service.savedState)
    var pinned = Object.assign({}, service.savedState.pinned)
    pinned[path] = !pinned[path]
    next.pinned = pinned
    service.savedState = next
    service.writeState()
    service.rebuild()
  }

  function setLastOpened(path) {
    var next = Object.assign({}, service.savedState)
    next.lastOpened = path
    service.savedState = next
    service.writeState()
  }

  function recordUsage(path) {
    service.usage = Store.recordUsage(service.usage, path, Date.now())
    usageFile.setText(JSON.stringify(service.usage, null, 2) + "\n")
    service.rebuild()
  }

  function availableEditors() { return Store.availableEditors(service.config, service.availableCommands) }

  Component.onCompleted: initProc.running = true

  Process { id: initProc; command: ["mkdir", "-p", service.stateDir] }

  FileView {
    id: configFile
    path: service.configPath
    watchChanges: true
    printErrors: false
    onLoaded: service.loadConfig(text())
    onLoadFailed: service.loadConfig("")
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: service.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadState(text())
    onLoadFailed: service.loadState("")
    onFileChanged: reload()
  }

  FileView {
    id: usageFile
    path: service.usagePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadUsage(text())
    onLoadFailed: service.loadUsage("{}")
    onFileChanged: reload()
  }

  FileView {
    id: cacheFile
    path: service.cachePath
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadCache(text())
    onLoadFailed: service.loadCache("")
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.onScanFinished(text)
    }
    stderr: SplitParser {
      onRead: function (line) { console.log("project-manager: " + line) }
    }
    onExited: service.scanning = false
  }

  Timer {
    id: refreshTimer
    interval: Math.max(1, service.config.scan.refreshMinutes) * 60000
    repeat: true
    running: service.config.scan.refreshMinutes > 0
    onTriggered: service.runScan()
  }
}
