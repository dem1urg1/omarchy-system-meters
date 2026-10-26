import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons as Commons
import qs.Commons
import Quickshell.Io
import qs.Ui

Panel {
  id: root
  moduleName: "demiurg.system-meters"
  ipcTarget: moduleName
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property string panelFont: bar ? bar.fontFamily : Style.font.family
  readonly property color panelDim: Qt.darker(normalColor, 1.55)

  function launchMonitor() {
    if (bar) bar.run("omarchy-launch-tui btop")
    close()
  }
  function uptimeText(seconds) {
    var minutes = Math.floor(seconds / 60)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    return (days > 0 ? days + "d " : "") + (hours % 24) + "h " + (minutes % 60) + "m"
  }
  implicitWidth: vertical ? barSize : meters.implicitWidth + 2 * Style.spaceReal(8.5)
  implicitHeight: vertical ? meters.implicitHeight + 8 : barSize
  readonly property real openPanelIndicatorWidth: implicitWidth
  property var stats: null
  readonly property color normalColor: bar ? bar.foreground : Commons.Color.foreground
  readonly property color criticalColor: Commons.Color.urgent
  readonly property color warningColor: Qt.rgba((normalColor.r + criticalColor.r) / 2,
    (normalColor.g + criticalColor.g) / 2, (normalColor.b + criticalColor.b) / 2, 1)
  function levelColor(level) {
    return level >= 0.9 ? criticalColor : level >= 0.8 ? warningColor : normalColor
  }

  function gib(bytes) { return (bytes / 1073741824).toFixed(1) }

  Process {
    id: collector
    command: ["/usr/bin/python3", Qt.resolvedUrl("stats.py").toString().replace(/^file:\/\//, "")]
    running: true
    stdout: SplitParser {
      onRead: data => {
        try { root.stats = JSON.parse(data) } catch (error) { console.warn("System meters:", error) }
      }
    }
  }

  // Restart the collector if it exits unexpectedly, without spawning overlapping processes.
  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: if (!collector.running) collector.running = true
  }

  Grid {
    id: meters
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 3
    columnSpacing: Style.space(6)
    rowSpacing: 6
    Repeater {
      model: ["CPU", "RAM", "DSK"]
      delegate: Item {
        id: meter
        required property int index
        required property string modelData
        width: root.vertical ? 22 : 32
        height: root.vertical ? compactTrack.y + compactTrack.height : Math.max(label.implicitHeight, segmentsColumn.implicitHeight)
        readonly property real usage: !root.stats ? 0 : index === 0 ? root.stats.cpu : index === 1 ? root.stats.ram : root.stats.disk
        readonly property int segments: 8
        readonly property int lit: Math.floor(Math.max(0, Math.min(100, usage)) * segments / 100)
        Text {
          id: label
          x: 0
          y: root.vertical ? 0 : (parent.height - height) / 2
          width: root.vertical ? 22 : 20
          horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
          text: meter.modelData
          color: root.bar ? root.bar.foreground : "white"
          font.family: root.bar ? root.bar.fontFamily : "monospace"
          font.pixelSize: 10
          font.bold: false
        }
        Item {
          id: compactTrack
          visible: root.vertical
          x: (parent.width - width) / 2
          y: label.implicitHeight + 2
          width: 18
          height: 2
          Repeater {
            model: [0, 0.8, 0.9]
            delegate: Item {
              required property int index
              required property real modelData
              readonly property real end: index === 0 ? 0.8 : index === 1 ? 0.9 : 1
              x: modelData * compactTrack.width
              width: (end - modelData) * compactTrack.width
              height: compactTrack.height
              Rectangle {
                anchors.fill: parent
                color: root.normalColor
                opacity: 0.16
              }
              Rectangle {
                width: root.stats ? Math.max(0, Math.min(parent.end, meter.usage / 100) - parent.modelData) * compactTrack.width : 0
                height: parent.height
                color: root.levelColor((parent.modelData + parent.end) / 2)
              }
            }
          }
        }
        Column {
          id: segmentsColumn
          visible: !root.vertical
          x: root.vertical ? (parent.width - width) / 2 : label.width + 4
          y: root.vertical ? label.implicitHeight + 3 : (parent.height - height) / 2
          spacing: 1
          Repeater {
            model: meter.segments
            delegate: Rectangle {
              required property int index
              width: root.vertical ? 9 : 8
              height: 1
              radius: 0
              readonly property bool filled: root.stats !== null && (meter.segments - 1 - index) < meter.lit
              color: filled ? root.levelColor((meter.segments - index - 0.5) / meter.segments) : root.normalColor
              opacity: filled ? 1 : 0.16
            }
          }
        }
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: ""
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: detailPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: direction => root.switchPanel(direction)
      onActivateRequested: root.launchMonitor()
      onMoveRequested: (dx, dy) => flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy * Style.space(56)))

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: qsTr("System")
            meta: root.stats ? qsTr("%1 · up %2").arg(root.stats.hostname).arg(root.uptimeText(root.stats.uptime)) : qsTr("Reading system usage…")
            foreground: root.normalColor
            fontFamily: root.panelFont
            iconComponent: Component {
              Text {
                text: "󰍹"
                color: root.normalColor
                font.family: root.panelFont
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.normalColor }

          UsageSection {
            width: parent.width
            heading: "CPU"
            title: root.stats ? qsTr("%1 logical CPUs").arg(root.stats.cores) : qsTr("Reading…")
            value: root.stats ? root.stats.cpu : 0
            coreLoads: root.stats && root.stats.cpuCores ? root.stats.cpuCores : []
            detail: root.stats ? root.stats.cpuModel : qsTr("Reading…")
          }

          PanelSeparator { foreground: root.normalColor }

          Column {
            width: parent.width
            spacing: Style.space(12)
            PanelSectionHeader {
              width: parent.width
              text: qsTr("Memory").toUpperCase()
              foreground: root.normalColor
              fontFamily: root.panelFont
            }
            UsageSection {
              width: parent.width
              title: "RAM"
              totalText: root.stats ? qsTr("%1 GiB").arg(root.gib(root.stats.ramTotal)) : "—"
              value: root.stats ? root.stats.ram : 0
              detail: root.stats ? qsTr("Used %1 GiB").arg(root.gib(root.stats.ramUsed))
                + (root.stats.ramReserved > 0 ? " " + qsTr("(%1 GiB reserved)").arg(root.gib(root.stats.ramReserved)) : "") : qsTr("Reading…")
              detailTail: root.stats ? qsTr("Free %1 GiB").arg(root.gib(root.stats.ramAvailable)) : ""
            }

            UsageSection {
              width: parent.width
              visible: !!root.stats && root.stats.swapTotal > 0
              title: qsTr("Swap")
              totalText: root.stats ? qsTr("%1 GiB").arg(root.gib(root.stats.swapTotal)) : "—"
              value: root.stats && root.stats.swapTotal > 0 ? 100 * root.stats.swapUsed / root.stats.swapTotal : 0
              detail: root.stats ? qsTr("Used %1 GiB").arg(root.gib(root.stats.swapUsed)) : ""
              detailTail: root.stats ? qsTr("Free %1 GiB").arg(root.gib(root.stats.swapTotal - root.stats.swapUsed)) : ""
            }
          }

          PanelSeparator { foreground: root.normalColor }

          Column {
            width: parent.width
            spacing: Style.space(12)
            PanelSectionHeader {
              width: parent.width
              text: qsTr("Disks").toUpperCase()
              foreground: root.normalColor
              fontFamily: root.panelFont
            }
            Repeater {
              model: root.stats && root.stats.disks ? root.stats.disks : []
              delegate: UsageSection {
                required property var modelData
                width: parent.width
                title: modelData.mounts[0] + " [" + modelData.filesystem + "]"
                totalText: qsTr("%1 GiB").arg(root.gib(modelData.total))
                value: modelData.percent
                inlineMeterLabel: true
                detail: qsTr("Used %1 GiB").arg(root.gib(modelData.used))
                detailTail: qsTr("Free %1 GiB").arg(root.gib(modelData.free))
                detailTailCritical: modelData.percent >= 90
              }
            }
            Text {
              width: parent.width
              visible: !root.stats || !root.stats.disks || root.stats.disks.length === 0
              text: root.stats ? qsTr("No accessible disk filesystems mounted") : qsTr("Reading…")
              color: root.panelDim
              font.family: root.panelFont
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
          }

          PanelSeparator { foreground: root.normalColor }

          WidgetButton {
            width: parent.width
            bar: root.bar
            fontFamily: root.panelFont
            fontSize: Style.font.bodySmall
            text: qsTr("Open system monitor ↗")
            tooltipText: ""
            onPressed: root.launchMonitor()
          }
        }
      }
    }
  }

  component UsageSection: Column {
    id: section
    property string heading: ""
    property string title: ""
    property string totalText: ""
    property string titleTail: ""
    property string titleAnnotation: ""
    property real value: 0
    property var coreLoads: null
    property bool inlineMeterLabel: false
    property string detail: ""
    property string detailAnnotation: ""
    property string detailTail: ""
    property bool detailTailCritical: false
    property string note: ""
    spacing: Style.space(6)

    PanelSectionHeader {
      width: parent.width
      visible: section.heading !== ""
      text: section.heading
      foreground: root.normalColor
      fontFamily: root.panelFont
    }

    Item {
      width: parent.width
      visible: !section.inlineMeterLabel
      implicitHeight: Math.max(titleText.implicitHeight, valueText.implicitHeight)
      Item {
        anchors.left: parent.left
        anchors.right: valueText.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        height: titleText.implicitHeight
        Text {
          id: titleText
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width)
          text: section.title
          textFormat: Text.PlainText
          color: root.normalColor
          font.family: root.panelFont
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: titleText.width + Style.space(6)
          width: Math.max(0, parent.width - x)
          text: section.titleTail
          textFormat: Text.PlainText
          color: root.panelDim
          font.family: root.panelFont
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
      }
      Text {
        id: valueText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: section.totalText !== "" ? section.totalText : root.stats ? section.value.toFixed(0) + "%" : "—"
        color: section.totalText !== "" ? root.normalColor : root.levelColor(section.value / 100)
        font.family: root.panelFont
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: section.titleAnnotation
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.panelDim
      font.family: root.panelFont
      font.pixelSize: Style.font.caption
    }

    Row {
      id: coreMeters
      width: parent.width
      visible: section.coreLoads !== null
      spacing: Style.space(4)
      Repeater {
        model: section.coreLoads || []
        delegate: Column {
          id: coreMeter
          required property var modelData
          width: Math.max(1, (coreMeters.width - coreMeters.spacing * Math.max(0, section.coreLoads.length - 1)) / Math.max(1, section.coreLoads.length))
          spacing: Style.space(4)
          Item {
            id: coreTrack
            width: parent.width
            height: Style.space(64)
            Rectangle {
              anchors.fill: parent
              radius: Style.space(1)
              color: root.normalColor
              opacity: 0.07
            }
            Item {
              anchors.bottom: parent.bottom
              width: parent.width
              height: coreTrack.height * Math.max(0, Math.min(100, coreMeter.modelData.usage)) / 100
              clip: true
              Rectangle {
                anchors.bottom: parent.bottom
                width: coreTrack.width
                height: coreTrack.height
                radius: Style.space(1)
                gradient: Gradient {
                  GradientStop { position: 0; color: root.criticalColor }
                  GradientStop { position: 0.1; color: root.warningColor }
                  GradientStop { position: 0.2; color: root.normalColor }
                  GradientStop { position: 1; color: root.normalColor }
                }
              }
              Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
          Text {
            width: parent.width
            text: coreMeter.modelData.id + 1
            horizontalAlignment: Text.AlignHCenter
            color: root.panelDim
            font.family: root.panelFont
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Item {
      id: largeMeter
      visible: section.coreLoads === null
      width: parent.width
      height: section.inlineMeterLabel ? inlineTitle.implicitHeight + Style.spacing.lg
        : Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      Rectangle {
        anchors.fill: parent
        radius: section.inlineMeterLabel ? Style.cornerRadius : height / 2
        opacity: section.inlineMeterLabel ? 0.05 : 0.16
        color: root.normalColor
      }
      Item {
        width: largeMeter.width * Math.max(0, Math.min(100, section.value)) / 100
        height: parent.height
        clip: true
        Rectangle {
          width: largeMeter.width
          height: largeMeter.height
          radius: section.inlineMeterLabel ? Style.cornerRadius : height / 2
          opacity: section.inlineMeterLabel ? 0.14 : 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.normalColor }
            GradientStop { position: 0.8; color: root.normalColor }
            GradientStop { position: 0.9; color: root.warningColor }
            GradientStop { position: 1; color: root.criticalColor }
          }
        }
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
      Text {
        id: inlineTitle
        visible: section.inlineMeterLabel
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.right: inlineValue.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: section.title
        textFormat: Text.PlainText
        color: root.normalColor
        font.family: root.panelFont
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        id: inlineValue
        visible: section.inlineMeterLabel
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: section.totalText !== "" ? section.totalText : root.stats ? section.value.toFixed(0) + "%" : "—"
        textFormat: Text.PlainText
        color: root.normalColor
        font.family: root.panelFont
        font.pixelSize: Style.font.bodySmall
        font.bold: section.totalText === ""
      }
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(detailLeft.implicitHeight, detailRight.visible ? detailRight.implicitHeight : 0)
      visible: section.detail !== "" || section.detailTail !== ""
      Flow {
        id: detailLeft
        anchors.left: parent.left
        anchors.right: detailRight.visible ? detailRight.left : parent.right
        anchors.rightMargin: detailRight.visible ? Style.space(12) : 0
        spacing: Style.space(6)
        Text {
          width: Math.min(implicitWidth, parent.width)
          visible: text !== ""
          text: section.detail
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.panelDim
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: text !== ""
          text: section.detailAnnotation
          textFormat: Text.PlainText
          color: Qt.darker(root.panelDim, 1.25)
          font.family: root.panelFont
          font.pixelSize: Style.font.caption
        }
      }
      Text {
        id: detailRight
        anchors.right: parent.right
        width: Math.min(implicitWidth, parent.width)
        visible: section.detailTail !== ""
        text: section.detailTail
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignRight
        color: section.detailTailCritical ? root.criticalColor : root.panelDim
        font.family: root.panelFont
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      width: parent.width
      visible: text !== ""
      text: section.note
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.panelDim
      font.family: root.panelFont
      font.pixelSize: Style.font.caption
    }
  }
}
