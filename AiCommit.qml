import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar button and panel for bin/omarchy-ai-commit. The button shows how many
// repos have uncommitted changes.
//   left click   commit every dirty repo, or open the preview when the
//                "Preview before committing" setting is on
//   right click  open the panel: preview, push, undo
//   middle click refresh
BarWidget {
  id: root
  moduleName: "gladkywdsd.ai-commit"

  readonly property string script: decodeURIComponent(
    Qt.resolvedUrl("bin/omarchy-ai-commit").toString().replace(/^file:\/\//, ""))

  // From `omarchy-ai-commit --status`.
  property int dirty: 0
  property bool running: false
  property var repos: []
  property int unpushed: 0
  property var unpushedRepos: []
  property int undoCount: 0
  property real undoTime: 0

  // The preview: "idle", "loading", "ready" or "error". Each plan row is
  // {repo, name, message, error}; edits and ticks are kept by repo path.
  property string planState: "idle"
  property string planError: ""
  property var planRows: []
  property var edits: ({})
  property var unticked: ({})
  property bool editing: false

  property bool opened: false

  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 300)) || 300)
  readonly property bool hideWhenClean: setting("hideWhenClean", false) === true
  readonly property bool previewFirst: setting("preview", false) === true

  readonly property color foreground: bar && bar.foreground ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar && bar.urgent ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family

  readonly property var committable: planRows.filter(function(row) {
    return !row.error && !root.unticked[row.repo] && root.messageFor(row).trim() !== ""
  })

  // A refresh asked for mid-check (say, as a run ends) runs again afterwards,
  // so the check that started before the run can't leave stale numbers.
  property bool refreshQueued: false

  function refresh() {
    if (statusProc.running) root.refreshQueued = true
    else statusProc.running = true
  }

  // Detached, so a run survives the shell reloading; the script tells every
  // bar to refresh when it starts and ends.
  function runScript(args) {
    if (!root.bar) return
    root.running = true
    root.bar.run(Util.shellQuote(root.script) + (args ? " " + args : ""))
  }

  function commitAll() {
    if (root.running) return
    root.resetPlan()
    root.runScript("")
  }

  function pushAll() {
    if (!root.running) root.runScript("--push")
  }

  function undoLastRun() {
    if (!root.running) root.runScript("--undo")
  }

  function generatePlan() {
    if (planProc.running) return
    root.resetPlan()
    root.planState = "loading"
    planProc.running = true
  }

  function resetPlan() {
    root.planState = "idle"
    root.planError = ""
    root.planRows = []
    root.edits = ({})
    root.unticked = ({})
  }

  function messageFor(row) {
    return root.edits[row.repo] !== undefined ? root.edits[row.repo] : row.message
  }

  function setEdit(repo, text) {
    var next = Object.assign({}, root.edits)
    next[repo] = text
    root.edits = next
  }

  function toggleRow(repo) {
    var next = Object.assign({}, root.unticked)
    if (next[repo]) delete next[repo]
    else next[repo] = true
    root.unticked = next
  }

  function commitSelected() {
    if (root.running || root.committable.length === 0) return
    var plan = root.committable.map(function(row) {
      return { repo: row.repo, message: root.messageFor(row) }
    })
    root.resetPlan()
    root.close()
    root.runScript("--commit-plan " + Util.shellQuote(JSON.stringify(plan)))
  }

  function primaryAction() {
    if (root.previewFirst) root.preview()
    else root.commitAll()
  }

  function preview() {
    root.open()
    if (root.planState !== "ready" && root.planState !== "loading") root.generatePlan()
  }

  // Shape the bar expects from a widget that owns a popup.
  function open() { root.opened = true; root.refresh() }
  function close() { root.opened = false; root.editing = false }
  function toggle() { root.opened ? root.close() : root.open() }

  function ago(seconds) {
    var diff = Math.max(0, Math.round(Date.now() / 1000 - seconds))
    if (diff < 60) return "just now"
    if (diff < 3600) return Math.round(diff / 60) + " min ago"
    if (diff < 86400) return Math.round(diff / 3600) + " h ago"
    return Math.round(diff / 86400) + " d ago"
  }

  function baseName(path) {
    return String(path).split("/").pop()
  }

  function plural(n, word) {
    return n + " " + word + (n === 1 ? "" : "s")
  }

  function tooltip() {
    if (root.opened) return ""
    if (root.running) return "AI Commit: working…"
    var lines = []
    if (root.dirty === 0) lines.push("AI Commit: every repo is clean")
    else lines.push("AI Commit: " + root.plural(root.dirty, "repo") + " with changes\n"
      + root.repos.map(function(path) { return "• " + root.baseName(path) }).join("\n"))
    if (root.unpushed > 0) lines.push(root.plural(root.unpushed, "repo") + " not pushed yet")
    lines.push(root.previewFirst ? "Click to preview · right-click for more" : "Click to commit all · right-click for more")
    return lines.join("\n\n")
  }

  visible: !(hideWhenClean && dirty === 0 && unpushed === 0 && !running)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  ShellIpc {
    target: "gladkywdsd.ai-commit"

    function refresh(): void { root.broadcast("refresh") }
    function commit(): void { root.commitAll() }
    function preview(): void { root.preview() }
    function push(): void { root.pushAll() }
    function undo(): void { root.undoLastRun() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
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
          root.unpushed = status.unpushed || 0
          root.unpushedRepos = status.unpushedRepos || []
          root.undoCount = status.undo || 0
          root.undoTime = status.undoTime || 0
        } catch (e) {
          root.running = false
        }
      }
    }
    onExited: {
      if (!root.refreshQueued) return
      root.refreshQueued = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: planProc
    command: [root.script, "--plan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var plan = JSON.parse(text)
          if (plan.error) {
            root.planError = plan.error
            root.planState = "error"
          } else {
            root.planRows = plan.repos || []
            root.planState = "ready"
          }
        } catch (e) {
          root.planError = "Could not read the preview."
          root.planState = "error"
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
    active: root.running || root.opened
    dimmed: root.dirty === 0 && root.unpushed === 0 && !root.running
    slotSize: Style.bar.statusSlot * (labelText !== "" ? 1.8 : 1)
    tooltipText: root.tooltip()

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggle()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.primaryAction()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      // Let the message editors have the keyboard while they are focused.
      blocked: root.editing
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "p" || t === "P") root.generatePlan()
        else if (t === "r" || t === "R") root.refresh()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // --- Changes --------------------------------------------------

          PanelSectionHeader {
            text: "CHANGES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Note {
            visible: root.planState === "idle" || root.planState === "error"
            text: root.dirty === 0
              ? "Every repo is clean."
              : root.plural(root.dirty, "repo") + " with changes: "
                + root.repos.map(root.baseName).join(", ")
          }

          Note {
            visible: root.planState === "error"
            text: root.planError
            color: root.urgent
          }

          Note {
            visible: root.planState === "loading"
            text: "Claude is writing the messages…"
          }

          Column {
            visible: root.planState === "ready"
            width: parent.width
            spacing: Style.space(10)

            Note {
              visible: root.planRows.length === 0
              text: "Nothing to commit any more."
            }

            Repeater {
              model: root.planState === "ready" ? root.planRows : []

              delegate: PlanRow {
                required property var modelData
                row: modelData
                width: column.width
              }
            }
          }

          Row {
            spacing: Style.space(8)

            Button {
              visible: root.planState === "ready"
              text: "Commit " + root.plural(root.committable.length, "repo")
              iconText: "󰜘"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.running && root.committable.length > 0
              onClicked: root.commitSelected()
            }

            Button {
              visible: root.dirty > 0 && root.planState !== "loading"
              text: root.planState === "ready" ? "Rewrite" : "Preview messages"
              iconText: "󰏫"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: root.planState !== "ready"
              enabled: !root.running
              onClicked: root.generatePlan()
            }

            Button {
              visible: root.dirty > 0 && root.planState !== "ready" && root.planState !== "loading"
              text: "Commit all"
              iconText: "󰊢"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !root.running
              onClicked: { root.close(); root.commitAll() }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // --- Push -----------------------------------------------------

          PanelSectionHeader {
            text: "PUSH"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Note {
            text: root.unpushed === 0
              ? "Everything is pushed."
              : root.plural(root.unpushed, "repo") + " with commits GitHub doesn't have yet: "
                + root.unpushedRepos.map(root.baseName).join(", ")
          }

          Button {
            visible: root.unpushed > 0
            text: "Push all"
            iconText: "󰕒"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.running
            onClicked: root.pushAll()
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // --- Undo -----------------------------------------------------

          PanelSectionHeader {
            text: "UNDO"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Note {
            text: root.undoCount === 0
              ? "Nothing to undo."
              : "The last run (" + root.ago(root.undoTime) + ") made "
                + root.plural(root.undoCount, "commit") + " that can still be taken back. "
                + "Your changes stay; only the commits go."
          }

          Button {
            visible: root.undoCount > 0
            text: "Undo last run"
            iconText: "󰕌"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: !root.running
            onClicked: root.undoLastRun()
          }
        }
      }
    }
  }

  component Note: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // One repo in the preview: a tick box, its name, and Claude's message in an
  // editor, or why it can't be committed.
  component PlanRow: Column {
    id: planRow
    property var row: ({})
    readonly property bool ticked: !row.error && !root.unticked[row.repo]

    spacing: Style.space(4)

    Row {
      spacing: Style.space(8)

      Text {
        text: planRow.row.error ? "󰅖" : (planRow.ticked ? "󰄲" : "󰄱")
        color: planRow.row.error ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon

        MouseArea {
          anchors.fill: parent
          enabled: !planRow.row.error
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleRow(planRow.row.repo)
        }
      }

      Text {
        text: planRow.row.name || ""
        textFormat: Text.PlainText
        color: root.foreground
        opacity: planRow.ticked ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Note {
      visible: !!planRow.row.error
      text: planRow.row.error || ""
    }

    Rectangle {
      visible: !planRow.row.error
      width: planRow.width
      height: editor.contentHeight + Style.space(12)
      radius: Style.cornerRadius
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, editor.activeFocus ? 0.6 : 0.2)
      opacity: planRow.ticked ? 1 : 0.5

      TextEdit {
        id: editor
        anchors.fill: parent
        anchors.margins: Style.space(6)
        text: planRow.row.message || ""
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        color: root.foreground
        selectionColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        onTextChanged: if (activeFocus) root.setEdit(planRow.row.repo, text)
        onActiveFocusChanged: root.editing = activeFocus
        Keys.onEscapePressed: if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
      }
    }
  }
}
