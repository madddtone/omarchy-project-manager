import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Store.js" as Store
import "Templates.js" as Templates

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property string home: Quickshell.env("HOME")

  // Injected by the shell (plugin kind "service"). A Loader provides a local
  // fallback so the overlay still works if opened standalone.
  property var service: null
  Loader {
    id: fallbackService
    active: root.service === null || root.service === undefined
    source: "Service.qml"
  }
  readonly property var svc: (root.service && root.service.rebuild)
    ? root.service
    : fallbackService.item

  property bool opened: false
  property var targetScreen: null
  property string filterText: ""
  property int selectedIndex: 0
  property int actionIndex: 0
  property string focusArea: "projects"
  property bool cursorActive: false
  property double now: Date.now()

  // "list" = browse; "prompt" = text entry or a choice list.
  property string mode: "list"
  property string promptKind: ""   // clone | name | template
  property string promptTitle: ""
  property string promptText: ""
  property var promptTemplates: []
  property int promptChoice: 0
  property string pendingName: ""

  property var rows: []
  property var actions: []

  // ---------------------------------------------------------------- theme

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, root.sp(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  property color urgent: Color.urgent

  readonly property real uiScale: {
    var s = root.svc ? root.svc.config.scale : 0
    if (typeof s === "number" && s > 0) return Math.min(3, s)
    var h = panel.screen ? panel.screen.height : 0
    return h > 0 ? Math.max(1, Math.min(1.6, h / 1080)) : 1
  }
  readonly property int fTitle: Math.max(1, Math.round(Style.font.title * uiScale))
  readonly property int fHeading: Math.max(1, Math.round(Style.font.heading * uiScale))
  readonly property int fBody: Math.max(1, Math.round(Style.font.body * uiScale))
  readonly property int fCaption: Math.max(1, Math.round(Style.font.caption * uiScale))
  readonly property int fDisplay: Math.max(1, Math.round(Style.font.displayLarge * uiScale))
  readonly property int sXs: Math.max(1, Math.round(Style.spacing.xs * uiScale))
  readonly property int sSm: Math.max(1, Math.round(Style.spacing.sm * uiScale))
  readonly property int sMd: Math.max(1, Math.round(Style.spacing.md * uiScale))
  readonly property int sPanelPad: Math.max(1, Math.round(Style.spacing.panelPadding * uiScale))
  readonly property int sControlY: Math.max(1, Math.round(Style.spacing.controlPaddingY * uiScale))

  function sp(px) {
    var v = Number(px) * uiScale * Style.effectiveSpacingScale
    return v <= 0 ? 0 : Math.max(1, Math.round(v))
  }

  property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Math.max(1, Math.round(Style.cornerRadius * uiScale))
  property int contentMargin: root.sPanelPad
  property int headerHeight: Math.max(root.sp(34), root.fTitle + root.sControlY * 2)
  property int contentSpacing: root.sMd
  property int cardWidth: Math.min(root.sp(1040), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(root.sp(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(root.sp(56), root.fTitle + root.fCaption + root.sXs + root.sControlY * 2)
  property int headerRowHeight: Math.max(root.sp(26), root.fCaption + root.sControlY)
  property int actionRowHeight: Math.max(root.sp(34), root.fBody + root.sControlY * 2)
  property int footerHeight: Math.max(root.sp(18), root.fCaption + root.sp(4))

  readonly property var currentProject: {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length) return null
    var r = root.rows[root.selectedIndex]
    return (r && r.kind === "project") ? r.project : null
  }
  readonly property bool hasLazygitAction: {
    for (var i = 0; i < root.actions.length; i++) if (root.actions[i].id === "git:lazygit") return true
    return false
  }

  // -------------------------------------------------------------- opening

  function focusedScreen() {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    if (name) {
      for (var i = 0; i < screens.length; i++) if (String(screens[i].name) === name) return screens[i]
    }
    return screens[0]
  }

  function open(payloadJson) {
    root.targetScreen = root.focusedScreen()
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.actionIndex = 0
    root.focusArea = "projects"
    root.cursorActive = true
    root.mode = "list"
    root.now = Date.now()
    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (payload && typeof payload.filter === "string") root.filterText = payload.filter
      } catch (e) {}
    }
    root.rebuildRows()
    if (root.svc && !root.svc.scannedOnce && !root.svc.scanning) root.svc.runScan()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.mode = "list"
    root.promptKind = ""
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---------------------------------------------------------------- model

  function rebuildRows() {
    if (!root.svc) { root.rows = []; rowModel.clear(); return }
    var t = Date.now()
    root.rows = Store.buildRows(root.svc.projects, root.svc.usage, t, root.filterText,
      function (p) { return p.typeLabels || [] })
    rowModel.clear()
    for (var i = 0; i < root.rows.length; i++) {
      var r = root.rows[i]
      var isP = r.kind === "project"
      rowModel.append({
        kind: r.kind,
        headerLabel: r.kind === "header" ? r.label : "",
        name: isP ? r.name : "",
        path: isP ? r.path : "",
        icon: isP ? r.icon : "",
        typeLabel: isP ? r.typeLabel : "",
        gitText: isP ? r.gitText : "",
        dirty: isP ? r.dirty : false,
        hasGit: isP ? r.hasGit : false,
        pinned: isP ? r.pinned : false,
        rowIndex: i
      })
    }
    root.ensureSelection()
    root.rebuildActions()
  }

  function ensureSelection() {
    var n = root.rows.length
    if (n === 0) { root.selectedIndex = 0; return }
    if (root.selectedIndex >= 0 && root.selectedIndex < n
        && root.rows[root.selectedIndex] && root.rows[root.selectedIndex].kind === "project") return
    for (var i = 0; i < n; i++) {
      if (root.rows[i].kind === "project") { root.selectedIndex = i; return }
    }
    root.selectedIndex = 0
  }

  function rebuildActions() {
    var project = root.currentProject
    if (!project || !root.svc) { root.actions = []; root.actionIndex = 0; return }
    var effective = root.svc.savedState.editorOverrides[project.path] || project.editor
    root.actions = Store.actionsFor(project, root.svc.config, root.svc.availableCommands, effective)
    if (root.actionIndex >= root.actions.length) root.actionIndex = Math.max(0, root.actions.length - 1)
    if (root.actionIndex < 0) root.actionIndex = 0
  }

  // ----------------------------------------------------------- navigation

  function moveSelection(delta) {
    var n = root.rows.length
    if (n === 0) return
    root.disarmPointer()
    root.focusArea = "projects"
    var i = root.selectedIndex
    for (var s = 0; s < n; s++) {
      i = (i + delta + n) % n
      if (root.rows[i].kind === "project") {
        root.selectedIndex = i
        root.cursorActive = true
        root.rebuildActions()
        resultList.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  function selectAbsolute(index) {
    if (index < 0 || index >= root.rows.length) return
    if (root.rows[index].kind !== "project") return
    root.disarmPointer()
    root.focusArea = "projects"
    root.cursorActive = true
    root.selectedIndex = index
    root.rebuildActions()
    resultList.positionViewAtIndex(index, ListView.Contain)
  }

  function firstProjectIndex() {
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].kind === "project") return i
    return 0
  }
  function lastProjectIndex() {
    for (var i = root.rows.length - 1; i >= 0; i--) if (root.rows[i].kind === "project") return i
    return 0
  }

  function selectAction(delta) {
    if (root.actions.length === 0) return
    root.focusArea = "actions"
    root.actionIndex = (root.actionIndex + delta + root.actions.length) % root.actions.length
    actionList.positionViewAtIndex(root.actionIndex, ListView.Contain)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildRows()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function disarmPointer() { pointerGate.reset() }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (root.rows[index] && root.rows[index].kind !== "project") return
    root.cursorActive = true
    root.focusArea = "projects"
    root.selectedIndex = index
    root.rebuildActions()
  }

  // ------------------------------------------------------------- actions

  function runAction(action) {
    if (!action || action.enabled === false || !root.svc) return
    var project = root.currentProject
    if (!project) return

    if (action.kind === "pin") {
      root.svc.togglePin(project.path)
      root.rebuildRows()
      return
    }

    var command = Store.commandFor(action, project, root.svc.config)
    if (!command) return

    root.svc.recordUsage(project.path)
    root.svc.setLastOpened(project.path)
    root.opened = false
    root.mode = "list"

    if (command.argv) Quickshell.execDetached(command.argv)
    else if (command.shell) Quickshell.execDetached(["bash", "-lc", command.shell])
  }

  function runFirstAction() { if (root.actions.length > 0) root.runAction(root.actions[0]) }

  function runActionOfKind(kind) {
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].kind === kind && root.actions[i].enabled !== false) { root.runAction(root.actions[i]); return }
    }
  }

  function runActionById(id) {
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].id === id && root.actions[i].enabled !== false) { root.runAction(root.actions[i]); return }
    }
  }

  function runTaskByIndex(n) {
    var count = 0
    for (var i = 0; i < root.actions.length; i++) {
      if (root.actions[i].kind === "task") {
        if (count === n) { root.runAction(root.actions[i]); return }
        count++
      }
    }
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.rows.length) return
    if (root.rows[index].kind !== "project") return
    root.selectedIndex = index
    root.rebuildActions()
    root.runFirstAction()
  }

  function cycleEditor() {
    var project = root.currentProject
    if (!project || !root.svc) return
    var ids = root.svc.availableEditors()
    if (ids.length === 0) return
    var current = root.svc.savedState.editorOverrides[project.path] || project.editor
    var index = ids.indexOf(current)
    var next = ids[(index + 1) % ids.length]
    root.svc.setEditorOverride(project.path, next)
    root.rebuildActions()
  }

  // ------------------------------------------------------------- prompts

  function openTextPrompt(kind, title, seed) {
    root.mode = "prompt"
    root.promptKind = kind
    root.promptTitle = title
    root.promptText = seed || ""
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function openTemplatePrompt(name) {
    root.pendingName = name
    root.promptKind = "template"
    root.promptTitle = "New project: " + name
    var list = Templates.allTemplates(root.svc ? root.svc.config.templates : [])
    var filtered = []
    for (var i = 0; i < list.length; i++) {
      var req = list[i].requires
      if (!req || Store.commandAvailable(req, root.svc.availableCommands)) filtered.push(list[i])
    }
    root.promptTemplates = filtered
    root.promptChoice = 0
    root.mode = "prompt"
  }

  function closePrompt() {
    root.mode = "list"
    root.promptKind = ""
    root.promptText = ""
  }

  function acceptPrompt() {
    if (!root.svc) return
    var kind = root.promptKind
    if (kind === "clone") {
      var url = root.promptText.trim()
      if (!url) return
      var clone = Store.cloneCommand(root.svc.config, root.svc.home, url)
      if (!clone) { root.svc.statusText = "Invalid repository URL"; return }
      Quickshell.execDetached(clone.argv)
      root.closePrompt()
      root.close()
      root.rescanSoon()
      return
    }
    if (kind === "name") {
      var name = Templates.sanitizeName(root.promptText)
      if (!name) { root.svc.statusText = "Invalid project name"; return }
      root.openTemplatePrompt(name)
      return
    }
    if (kind === "template") {
      var tpl = root.promptTemplates[root.promptChoice]
      if (!tpl) return
      var dir = Store.defaultRoot(root.svc.config, root.svc.home).replace(/\/+$/, "") + "/" + root.pendingName
      var script = Templates.scaffoldScript(tpl, dir, root.pendingName)
      if (!script) { root.svc.statusText = "Could not scaffold project"; return }
      Quickshell.execDetached(["bash", "-lc", script])
      root.svc.setLastOpened(dir)
      root.closePrompt()
      root.close()
      root.rescanSoon()
      return
    }
  }

  function chooseTemplate(delta) {
    if (root.promptTemplates.length === 0) return
    root.promptChoice = (root.promptChoice + delta + root.promptTemplates.length) % root.promptTemplates.length
  }

  function rescanSoon() { rescanTimer.restart() }

  Connections {
    target: root.svc
    function onProjectsChanged() { if (root.opened) root.rebuildRows() }
    function onAvailableCommandsChanged() { if (root.opened) root.rebuildActions() }
  }

  ListModel { id: rowModel }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  Timer { id: rescanTimer; interval: 1800; repeat: false; onTriggered: if (root.svc) root.svc.runScan() }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kalel-project-manager"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem

        Keys.onPressed: function (event) {
          var ctrl = event.modifiers & Qt.ControlModifier
          var alt = event.modifiers & Qt.AltModifier
          var meta = event.modifiers & Qt.MetaModifier
          var shift = event.modifiers & Qt.ShiftModifier

          if (root.mode === "prompt") {
            if (root.promptKind === "template") {
              if (event.key === Qt.Key_Escape) root.closePrompt()
              else if (event.key === Qt.Key_Up) root.chooseTemplate(-1)
              else if (event.key === Qt.Key_Down) root.chooseTemplate(1)
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.acceptPrompt()
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Escape) root.closePrompt()
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.acceptPrompt()
            else if (event.key === Qt.Key_Backspace) root.promptText = root.promptText.slice(0, -1)
            else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127 && !(ctrl || alt || meta)) {
              root.promptText = root.promptText + event.text
            }
            event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.focusArea === "actions") { root.focusArea = "projects"; root.actionIndex = 0 }
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right) {
            if (root.actions.length > 0) root.focusArea = "actions"
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left) {
            root.focusArea = "projects"
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            if (root.focusArea === "actions") root.selectAction(-1); else root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            if (root.focusArea === "actions") root.selectAction(1); else root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            if (root.focusArea === "actions") root.selectAction(-3); else root.moveSelection(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            if (root.focusArea === "actions") root.selectAction(3); else root.moveSelection(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            if (root.focusArea === "actions") { root.actionIndex = 0; actionList.positionViewAtIndex(0, ListView.Beginning) }
            else root.selectAbsolute(root.firstProjectIndex())
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            if (root.focusArea === "actions") { root.actionIndex = root.actions.length - 1; actionList.positionViewAtIndex(root.actionIndex, ListView.End) }
            else root.selectAbsolute(root.lastProjectIndex())
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (ctrl) root.runActionOfKind("github")
            else if (shift) root.runActionOfKind("terminal")
            else if (alt) root.runActionOfKind("files")
            else if (root.focusArea === "actions") root.runAction(root.actions[root.actionIndex])
            else root.runFirstAction()
            event.accepted = true
          } else if (event.key === Qt.Key_R && ctrl) {
            if (root.svc) root.svc.runScan()
            event.accepted = true
          } else if (event.key === Qt.Key_N && ctrl) {
            root.openTextPrompt("name", "New project name", "")
            event.accepted = true
          } else if (event.key === Qt.Key_L && ctrl) {
            root.openTextPrompt("clone", "Clone repository URL", "")
            event.accepted = true
          } else if (event.key === Qt.Key_P && ctrl) {
            var proj = root.currentProject
            if (proj && root.svc) { root.svc.togglePin(proj.path); root.rebuildRows() }
            event.accepted = true
          } else if (event.key === Qt.Key_G && ctrl && shift) {
            root.runActionById("git:lazygit")
            event.accepted = true
          } else if (event.key === Qt.Key_G && ctrl) {
            root.runActionOfKind("github")
            event.accepted = true
          } else if (event.key === Qt.Key_Y && ctrl) {
            root.runActionOfKind("copy")
            event.accepted = true
          } else if (event.key === Qt.Key_E && ctrl) {
            root.cycleEditor()
            event.accepted = true
          } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.runTaskByIndex(event.key - Qt.Key_1)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127 && !(ctrl || alt || meta)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // ---------------------------------------------------------- header
        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: statusLabel.left
            anchors.rightMargin: root.sp(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search projects…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: root.fHeading
            elide: Text.ElideRight
          }

          Text {
            id: statusLabel
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.svc && root.svc.statusText.length > 0) return root.svc.statusText
              var n = rowModel.count
              return n + (n === 1 ? " project" : " projects")
            }
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: root.fCaption
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

          Row {
            anchors.fill: parent
            spacing: 0

            // --------------------------------------------------- project list
            Item {
              width: parent.width * 0.52
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: rowModel
                clip: true
                spacing: root.sp(3)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string kind
                  required property string headerLabel
                  required property string name
                  required property string path
                  required property string icon
                  required property string typeLabel
                  required property string gitText
                  required property bool dirty
                  required property bool hasGit
                  required property bool pinned
                  required property int rowIndex

                  readonly property bool isHeader: kind === "header"
                  readonly property bool hasCursor: !isHeader && root.cursorActive
                    && root.focusArea === "projects" && index === root.selectedIndex

                  width: ListView.view.width
                  height: isHeader ? root.headerRowHeight : root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  // Section header
                  Text {
                    visible: row.isHeader
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: root.sp(8)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.sp(2)
                    text: row.headerLabel.toUpperCase()
                    color: root.foreground
                    opacity: 0.42
                    font.family: root.fontFamily
                    font.pixelSize: root.fCaption
                    font.letterSpacing: 0.5
                  }

                  Row {
                    visible: !row.isHeader
                    anchors.fill: parent
                    anchors.leftMargin: root.sp(12)
                    anchors.rightMargin: root.sp(12)
                    anchors.topMargin: root.sp(8)
                    anchors.bottomMargin: root.sp(8)
                    spacing: root.sp(10)

                    Text {
                      id: rowIcon
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: row.icon !== "" ? row.icon : (row.pinned ? "\uf08d" : "\uf07b")
                      color: row.hasCursor ? root.selectedText : root.accent
                      opacity: row.hasCursor ? 1 : 0.7
                      font.family: root.fontFamily
                      font.pixelSize: root.fTitle
                    }

                    Column {
                      width: parent.width - rowIcon.width - parent.spacing * 2 - gitInfo.width
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: root.sp(1)

                      Text {
                        textFormat: Text.StyledText
                        width: parent.width
                        text: Store.highlightHtml(row.name, root.filterText)
                        color: row.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fTitle
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: row.path
                        color: root.foreground
                        opacity: 0.55
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                        elide: Text.ElideMiddle
                      }
                    }

                    Column {
                      id: gitInfo
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: root.sp(1)

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        visible: row.pinned
                        text: "\uf08d"
                        color: row.hasCursor ? root.selectedText : root.accent
                        opacity: 0.8
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        text: row.gitText
                        color: row.dirty ? root.urgent : root.foreground
                        opacity: row.dirty ? 0.95 : 0.7
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        text: row.typeLabel
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !row.isHeader
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function (mouse) { root.selectFromPointer(row.index, row, mouse) }
                    onClicked: {
                      if (row.isHeader) return
                      root.cursorActive = true
                      root.focusArea = "projects"
                      root.selectedIndex = row.index
                      root.rebuildActions()
                    }
                    onDoubleClicked: root.activateIndex(row.index)
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: root.sp(8)
                visible: rowModel.count === 0

                Text {
                  text: "󰉋"
                  color: root.selectedText
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: root.fDisplay
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.filterText
                    ? "No matches for “" + root.filterText + "”"
                    : (root.svc && root.svc.scanning ? "Scanning…" : "No projects found")
                  color: root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: root.fTitle
                  horizontalAlignment: Text.AlignHCenter
                  width: parent.width
                }
              }
            }

            // ------------------------------------------------ detail / actions
            Item {
              width: parent.width * 0.48
              height: parent.height
              clip: true

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Column {
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                anchors.rightMargin: root.contentMargin
                spacing: root.sSm

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: root.mode === "prompt"
                    ? root.promptTitle
                    : (root.currentProject ? root.currentProject.name : "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: root.fHeading
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list"
                  text: root.currentProject ? root.currentProject.path : ""
                  color: root.foreground
                  opacity: 0.6
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideMiddle
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject && root.currentProject.git
                  text: {
                    if (!root.currentProject || !root.currentProject.git) return ""
                    var g = root.currentProject.git
                    var s = "\uf126  " + Store.gitSummary(g)
                    if (g.stash > 0) s += "  ·  " + g.stash + " stash"
                    return s
                  }
                  color: root.currentProject && root.currentProject.git && root.currentProject.git.dirty
                    ? root.urgent : root.foreground
                  opacity: 0.85
                  font.family: root.fontFamily
                  font.pixelSize: root.fBody
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject && root.currentProject.git
                    && root.currentProject.git.commit !== ""
                  text: {
                    if (!root.currentProject || !root.currentProject.git) return ""
                    var g = root.currentProject.git
                    var age = Store.relativeTime(g.commitAt, root.now)
                    return g.commit + (age ? "  ·  " + age : "")
                  }
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject && root.currentProject.tags.length > 0
                  text: root.currentProject ? root.currentProject.tags.join("  ·  ") : ""
                  color: root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list" && root.currentProject !== null
                  text: {
                    if (!root.currentProject) return ""
                    var parts = []
                    var tl = root.currentProject.typeLabels || []
                    if (tl.length) parts.push(tl.join(", "))
                    if (root.currentProject.editorLabel) parts.push(root.currentProject.editorLabel)
                    return parts.join("  ·  ")
                  }
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                  elide: Text.ElideRight
                }

                Item { width: 1; height: root.sSm }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  visible: root.mode === "list"
                  text: "Actions"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: root.fCaption
                }

                ListView {
                  id: actionList
                  width: parent.width
                  height: Math.max(0, parent.height - y - root.sp(6))
                  visible: root.mode === "list"
                  model: root.actions
                  clip: true
                  spacing: root.sp(3)
                  boundsBehavior: Flickable.StopAtBounds

                  delegate: Rectangle {
                    id: actionRow
                    required property int index
                    required property var modelData

                    readonly property bool hasCursor: root.focusArea === "actions" && index === root.actionIndex
                    readonly property bool isEnabled: modelData.enabled !== false

                    width: ListView.view.width
                    height: root.actionRowHeight
                    radius: root.cornerRadius
                    color: hasCursor ? root.selectedBackground : "transparent"

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: root.sp(10)
                      anchors.rightMargin: root.sp(10)
                      spacing: root.sp(8)

                      Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - hintText.width - parent.spacing
                        text: actionRow.modelData.label
                        color: actionRow.isEnabled
                          ? (actionRow.hasCursor ? root.selectedText : root.foreground)
                          : root.foreground
                        opacity: actionRow.isEnabled ? 1 : 0.35
                        font.family: root.fontFamily
                        font.pixelSize: root.fBody
                        elide: Text.ElideRight
                      }

                      Text {
                        id: hintText
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.modelData.hint || ""
                        color: root.foreground
                        opacity: actionRow.isEnabled ? 0.45 : 0.2
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: actionRow.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onEntered: { root.focusArea = "actions"; root.actionIndex = actionRow.index }
                      onClicked: {
                        root.focusArea = "actions"
                        root.actionIndex = actionRow.index
                        root.runAction(actionRow.modelData)
                      }
                    }
                  }
                }

                // Prompt body: text entry (clone / name)
                Item {
                  width: parent.width
                  height: Math.max(0, parent.height - y - root.sp(6))
                  visible: root.mode === "prompt" && root.promptKind !== "template"

                  Rectangle {
                    id: promptBox
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.actionRowHeight
                    radius: root.cornerRadius
                    color: Util.alpha(root.foreground, 0.08)
                    border.width: Style.normalBorderWidth
                    border.color: Util.alpha(root.border, 0.5)

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.leftMargin: root.sp(10)
                      anchors.right: parent.right
                      anchors.rightMargin: root.sp(10)
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.promptText.length > 0 ? root.promptText : "Type and press Enter…"
                      color: root.foreground
                      opacity: root.promptText.length > 0 ? 1 : 0.4
                      font.family: root.fontFamily
                      font.pixelSize: root.fBody
                      elide: Text.ElideRight
                    }
                  }
                }

                // Prompt body: template chooser
                ListView {
                  id: templateList
                  width: parent.width
                  height: Math.max(0, parent.height - y - root.sp(6))
                  visible: root.mode === "prompt" && root.promptKind === "template"
                  model: root.promptTemplates
                  clip: true
                  spacing: root.sp(3)
                  boundsBehavior: Flickable.StopAtBounds

                  delegate: Rectangle {
                    id: tplRow
                    required property int index
                    required property var modelData
                    readonly property bool hasCursor: index === root.promptChoice

                    width: ListView.view.width
                    height: root.rowHeight
                    radius: root.cornerRadius
                    color: hasCursor ? root.selectedBackground : "transparent"

                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.leftMargin: root.sp(10)
                      anchors.rightMargin: root.sp(10)
                      spacing: root.sp(1)

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: tplRow.modelData.label
                        color: tplRow.hasCursor ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: root.fBody
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: tplRow.modelData.description
                        color: root.foreground
                        opacity: 0.5
                        font.family: root.fontFamily
                        font.pixelSize: root.fCaption
                        elide: Text.ElideRight
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.promptChoice = tplRow.index
                      onClicked: { root.promptChoice = tplRow.index; root.acceptPrompt() }
                    }
                  }
                }
              }
            }
          }
        }

        // ---------------------------------------------------------- footer
        Text {
          id: footer
          textFormat: Text.PlainText
          width: parent.width
          height: root.footerHeight
          verticalAlignment: Text.AlignVCenter
          text: {
            if (root.mode === "prompt") {
              if (root.promptKind === "template") return "\u2191\u2193 choose template  ·  Enter create  ·  Esc cancel"
              return "Enter confirm  ·  Esc cancel"
            }
            if (root.focusArea === "actions") {
              var s = "\u2191\u2193 move  ·  Enter run"
              if (root.hasLazygitAction) s += "  ·  Ctrl \u21e7G lazygit"
              s += "  ·  Ctrl G browser  ·  Ctrl Y copy  ·  Ctrl P pin  ·  \u2190 list  ·  Esc close"
              return s
            }
            return "type to search  ·  \u2191\u2193 move  ·  Enter open  ·  \u21e7Enter terminal  ·  \u2325Enter files  ·  \u2192 actions  ·  Ctrl P pin  ·  Ctrl N new  ·  Ctrl L clone  ·  Ctrl R rescan"
          }
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: root.fCaption
          elide: Text.ElideRight
        }
      }
    }
  }
}
