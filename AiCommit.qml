import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button for bin/omarchy-ai-commit. Shows how many repos have uncommitted
// changes; a click commits them all with Claude-written messages.
//   left click   commit every dirty repo
//   right click  dry run in a terminal (shows the messages, commits nothing)
//   middle click refresh the count
BarWidget {
  id: root
  moduleName: "gladkywdsd.ai-commit"

  readonly property string script: decodeURIComponent(
    Qt.resolvedUrl("bin/omarchy-ai-commit").toString().replace(/^file:\/\//, ""))

  property int dirty: 0
  property bool running: false
  property var repos: []

  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 300)) || 300)
  readonly property bool hideWhenClean: setting("hideWhenClean", false) === true

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function commitAll() {
    if (root.running || !root.bar) return
    root.running = true
    root.bar.run(Util.shellQuote(root.script))
  }

  function dryRun() {
    if (!root.bar) return
    root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(root.script) + " --dry-run")
  }

  function tooltip() {
    if (root.running) return "AI Commit: committing…"
    if (root.dirty === 0) return "AI Commit: every repo is clean"
    var names = root.repos.map(function(path) { return "• " + path.split("/").pop() })
    return "AI Commit: " + root.dirty + " repo" + (root.dirty === 1 ? "" : "s") + " with changes\n"
      + names.join("\n") + "\n\nClick to commit all · right-click for a dry run"
  }

  visible: !(hideWhenClean && dirty === 0 && !running)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The script calls `omarchy-shell -q gladkywdsd.ai-commit refresh` when a
  // run starts and ends, so every monitor's bar updates; a keybinding can
  // also trigger a run through `commit`.
  ShellIpc {
    target: "gladkywdsd.ai-commit"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function commit(): void {
      root.commitAll()
    }
  }

  Process {
    id: statusProc
    command: [root.script, "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var status = JSON.parse(text)
          root.dirty = status.dirty || 0
          root.running = status.running === true
          root.repos = status.repos || []
        } catch (e) {
          root.running = false
        }
      }
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.running ? "󰑓" : "󰊢"
    labelText: root.dirty > 0 && !root.running && !root.vertical ? String(root.dirty) : ""
    active: root.running
    dimmed: root.dirty === 0 && !root.running
    slotSize: Style.bar.statusSlot * (labelText !== "" ? 1.8 : 1)
    tooltipText: root.tooltip()

    onPressed: function(b) {
      if (b === Qt.RightButton) root.dryRun()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.commitAll()
    }
  }
}
