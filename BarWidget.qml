import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar icon that opens the Project Manager overlay. A small badge shows how
// many of the known repos are dirty; right/middle click rescans.
BarWidget {
  id: root
  moduleName: "kalel.project-manager"

  readonly property var svc: {
    if (root.bar && root.bar.shell && typeof root.bar.shell.serviceFor === "function")
      return root.bar.shell.serviceFor(root.moduleName)
    return null
  }

  readonly property string iconGlyph: {
    var v = root.setting("barIcon", "")
    var s = v === undefined || v === null ? "" : String(v)
    return s.length > 0 ? s : "\uf121"
  }
  readonly property int dirtyCount: root.svc ? root.svc.dirtyCount : 0
  readonly property int totalCount: root.svc ? root.svc.projects.length : 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function launch() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function") {
      root.bar.shell.toggle(root.moduleName, "{}")
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", root.moduleName])
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: {
      if (!root.svc) return "Project Manager\nClick to open"
      var t = root.totalCount + (root.totalCount === 1 ? " project" : " projects")
      if (root.dirtyCount > 0) t += " · " + root.dirtyCount + " dirty"
      return "Project Manager\n" + t + "\nClick to open · right-click to rescan"
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) {
        if (root.svc) root.svc.runScan()
        return
      }
      root.launch()
    }
  }
}
