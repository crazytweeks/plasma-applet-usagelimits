import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    // Styles: "bars" grouped mini bars, "text" letters+percentages, "worst"
    // single pill, "rings" round gauges, "glow" brightness chips, "dots"
    // severity dots, "capsule" one segmented strip.
    readonly property string style: root.panelStyle
    readonly property bool hasData: root.limitRows.length > 0
    readonly property int chipSize: Math.max(14, Math.min(24, compact.height - 8))
    readonly property real pad: Kirigami.Units.smallSpacing * 1.5

    // Distinct glyphs: initials alone would collide (Claude / Codex both "C").
    function glyph(p) {
        var map = { "claude": "C", "codex": "X", "opencode": "G", "zai": "Z" }
        var g = p && p.id ? map[p.id] : undefined
        return g ? g : (p && p.name ? p.name.charAt(0).toUpperCase() : "?")
    }

    // Glyph by provider id, for flat rows that no longer carry the object.
    function glyphForId(providerId, providerName) {
        return glyph({ id: providerId, name: providerName })
    }

    function worstOf(provider) {
        var windows = root.toArray(provider.windows)
        var worst = 0
        for (var i = 0; i < windows.length; i++) {
            var value = windows[i].percent || 0
            if (value > worst) worst = value
        }
        return worst
    }

    readonly property string summaryText: {
        var parts = []
        var rows = root.limitRows
        for (var i = 0; i < rows.length; i++) {
            parts.push(rows[i].provider + " " + rows[i].label + ": " + Math.round(rows[i].util) + "%")
        }
        if (parts.length === 0) return "Usage Limits — no usage data yet"
        return parts.join("\n")
    }

    onClicked: root.expanded = !root.expanded
    hoverEnabled: true

    Layout.minimumWidth: (loader.item ? loader.item.implicitWidth : Kirigami.Units.gridUnit) + compact.pad * 2
    Layout.minimumHeight: Kirigami.Units.gridUnit
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    QQC2.ToolTip {
        visible: compact.containsMouse
        delay: Kirigami.Units.longDuration
        text: root.hasError ? root.errorMessage : compact.summaryText
    }

    Kirigami.Icon {
        visible: root.hasError && (!loader.item || !loader.item.showsData)
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.small
        height: width
        source: "data-warning"
        color: Kirigami.Theme.negativeTextColor
    }

    Loader {
        id: loader
        anchors.centerIn: parent
        sourceComponent: {
            if (compact.style === "rings") return ringsStyle
            if (compact.style === "glow") return glowStyle
            if (compact.style === "dots") return dotsStyle
            if (compact.style === "capsule") return capsuleStyle
            if (compact.style === "text") return textStyle
            if (compact.style === "worst") return worstStyle
            return barsStyle
        }
    }

    // --- Shared binding helpers: values crossing Repeater delegates need
    // to survive the var->QVariant boundary, so windows come via toArray.

    // Style: grouped mini bars (per provider, per window).
    Component {
        id: barsStyle
        Item {
            readonly property bool showsData: true
            implicitWidth: barRow.implicitWidth
            implicitHeight: compact.height * 0.72

            Row {
                id: barRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing * 2.5

                Repeater {
                    model: root.visibleProviders

                    Item {
                        id: providerColumn
                        required property var modelData
                        readonly property var provider: modelData
                        readonly property bool isOk: provider.state === "ok"
                        readonly property var windows: isOk ? root.toArray(provider.windows) : []

                        width: {
                            var n = windows.length
                            if (n === 0) return Kirigami.Units.gridUnit * 0.6
                            return n * Kirigami.Units.gridUnit * 0.6
                                + (n - 1) * innerRow.spacing
                        }
                        height: compact.height * 0.72

                        Row {
                            id: innerRow
                            anchors.centerIn: parent
                            spacing: Kirigami.Units.smallSpacing

                            Repeater {
                                model: providerColumn.windows

                                Rectangle {
                                    required property var modelData
                                    readonly property var win: modelData
                                    readonly property real util: win ? (win.percent || 0) : 0

                                    width: Kirigami.Units.gridUnit * 0.6
                                    height: providerColumn.height
                                    radius: 2
                                    color: Qt.alpha(Kirigami.Theme.textColor, 0.12)

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * Math.min(100, Math.max(0, parent.util)) / 100
                                        radius: parent.radius
                                        color: root.usageColor(parent.util)
                                    }
                                }
                            }
                        }

                        Kirigami.Icon {
                            visible: providerColumn.windows.length === 0
                            anchors.centerIn: parent
                            width: Kirigami.Units.iconSizes.small
                            height: width
                            source: providerColumn.isOk ? "view-refresh" : "data-warning"
                            color: providerColumn.isOk ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.negativeTextColor
                        }
                    }
                }
            }
        }
    }

    // Style: rings — one circular gauge per provider.
    Component {
        id: ringsStyle
        Item {
            readonly property bool showsData: compact.hasData
            readonly property int ringSize: compact.chipSize
            implicitWidth: ringRow.implicitWidth
            implicitHeight: ringSize

            Row {
                id: ringRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing * 1.2

                Repeater {
                    model: root.visibleProviders

                    Item {
                        id: ringCell
                        required property var modelData
                        readonly property var provider: modelData
                        readonly property bool isOk: provider.state === "ok"
                        readonly property real util: isOk ? compact.worstOf(provider) : 0
                        readonly property real size: ringCellHeight
                        readonly property real radius: size / 2 - 1.6
                        // sizes filtered through this internal var to avoid
                        // anchor circularity on very small panels
                        readonly property real ringCellHeight: compact.chipSize

                        width: size
                        height: size

                        // Suppress unused warning: radius used below in Canvas.
                        readonly property real arcRadius: radius

                        Canvas {
                            id: ringCanvas
                            anchors.fill: parent
                            antialiasing: true
                            visible: ringCell.isOk

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var cx = width / 2, cy = height / 2
                                var r = ringCell.arcRadius
                                ctx.lineWidth = 2.4
                                ctx.lineCap = "round"
                                ctx.strokeStyle = Qt.rgba(0.5, 0.5, 0.5, 0.35)
                                ctx.beginPath()
                                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                                ctx.stroke()
                                if (ringCell.util > 0) {
                                    var start = -Math.PI / 2
                                    var sweep = 2 * Math.PI * Math.min(1, Math.max(0, ringCell.util) / 100)
                                    ctx.strokeStyle = root.usageColor(ringCell.util)
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, r, start, start + sweep)
                                    ctx.stroke()
                                }
                            }
                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            Connections {
                                target: ringCell
                                function onUtilChanged() { ringCanvas.requestPaint() }
                            }
                        }

                        QQC2.Label {
                            visible: ringCell.isOk
                            anchors.centerIn: parent
                            text: compact.glyph(ringCell.provider)
                            color: root.usageColor(ringCell.util)
                            font.pixelSize: ringCell.size * 0.42
                            font.bold: true
                        }

                        Kirigami.Icon {
                            visible: !ringCell.isOk
                            anchors.centerIn: parent
                            width: ringCell.size * 0.7
                            height: width
                            source: "data-warning"
                            color: Kirigami.Theme.negativeTextColor
                        }

                        onWidthChanged: ringCanvas.requestPaint()
                    }
                }
            }
        }
    }

    // Style: glow — chip whose brightness equals the provider's usage.
    Component {
        id: glowStyle
        Item {
            readonly property bool showsData: compact.hasData
            implicitWidth: glowRow.implicitWidth
            implicitHeight: compact.chipSize

            Row {
                id: glowRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing * 0.8

                Repeater {
                    model: root.visibleProviders

                    Rectangle {
                        id: glowCell
                        required property var modelData
                        readonly property var provider: modelData
                        readonly property bool isOk: provider.state === "ok"
                        readonly property real util: isOk ? compact.worstOf(provider) : 0
                        readonly property real intensity: isOk ? (0.10 + 0.90 * Math.min(1, Math.max(0, util) / 100)) : 0.0

                        width: compact.chipSize
                        height: compact.chipSize
                        radius: height * 0.32
                        color: isOk
                            ? Qt.alpha(root.usageColor(util), intensity)
                            : Qt.rgba(0.5, 0.5, 0.5, 0.15)

                        // At high usage the chip is fully lit; numbers readable
                        // as dark-on-bright like the mockup.
                        QQC2.Label {
                            anchors.centerIn: parent
                            text: compact.glyph(glowCell.provider)
                            color: glowCell.isOk
                                ? (glowCell.intensity > 0.75 ? "#241408" : Kirigami.Theme.textColor)
                                : Kirigami.Theme.negativeTextColor
                            font.pixelSize: glowCell.height * 0.5
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    // Style: severity dots — smallest possible footprint.
    Component {
        id: dotsStyle
        Item {
            readonly property bool showsData: compact.hasData
            implicitWidth: dotsRow.implicitWidth
            implicitHeight: Kirigami.Units.iconSizes.small

            Row {
                id: dotsRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing * 1.2

                Repeater {
                    model: root.visibleProviders

                    Rectangle {
                        required property var modelData
                        readonly property var provider: modelData
                        readonly property bool isOk: provider.state === "ok"
                        readonly property real util: isOk ? compact.worstOf(provider) : 0

                        width: Kirigami.Units.iconSizes.small
                        height: width
                        radius: width * 0.32
                        color: isOk
                            ? root.usageColor(util)
                            : Kirigami.Theme.disabledTextColor
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                    }
                }
            }
        }
    }

    // Style: capsule — one strip, one slot per provider.
    Component {
        id: capsuleStyle
        Item {
            readonly property bool showsData: compact.hasData
            readonly property real capsuleWidth: Kirigami.Units.gridUnit * 7
            readonly property real capsuleHeight: Math.max(10, Math.min(16, compact.height * 0.5))
            implicitWidth: capsuleWidth
            implicitHeight: capsuleHeight

            Rectangle {
                id: capsuleBg
                anchors.centerIn: parent
                width: parent.capsuleWidth
                height: parent.capsuleHeight
                radius: height / 2
                color: Qt.alpha(Kirigami.Theme.textColor, 0.15)
                clip: true

                Row {
                    id: capsuleRow
                    anchors.fill: parent
                    spacing: 0

                    Repeater {
                        model: root.visibleProviders

                        Item {
                            id: capsuleCell
                            required property var modelData
                            readonly property var provider: modelData
                            readonly property bool isOk: provider.state === "ok"
                            readonly property real util: isOk ? compact.worstOf(provider) : 0

                            width: capsuleBg.visible ? (capsuleBg.width / Math.max(1, root.visibleProviders.length)) : 0
                            height: parent.height

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Math.min(height / 2, 6)
                                color: capsuleCell.isOk
                                    ? Qt.alpha(root.usageColor(capsuleCell.util), 0.22)
                                    : "transparent"
                                visible: capsuleCell.isOk
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 1
                                width: (parent.width - 2) * Math.min(100, Math.max(0, capsuleCell.util)) / 100
                                radius: height / 2
                                color: capsuleCell.isOk ? root.usageColor(capsuleCell.util) : "transparent"
                                visible: capsuleCell.isOk && capsuleCell.util > 0
                            }
                        }
                    }
                }
            }
        }
    }

    // Style: letters and percentages ("C 46% C 45%" chips).
    Component {
        id: textStyle
        Row {
            readonly property bool showsData: compact.hasData
            spacing: Kirigami.Units.smallSpacing * 1.5
            leftPadding: 0

            Repeater {
                model: root.limitRows

                QQC2.Label {
                    required property var modelData
                    readonly property var win: modelData

                    text: compact.glyphForId(win.providerId, win.provider) + " " + Math.round(win.util) + "%"
                    color: root.usageColor(win.util)
                    font.bold: win.util >= root.warningThreshold
                    font.pointSize: Qt.application.font.pointSize * 0.85
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Style: single pill for the worst usage overall.
    Component {
        id: worstStyle
        Rectangle {
            readonly property bool showsData: compact.hasData
            implicitWidth: badgeRow.implicitWidth + Kirigami.Units.smallSpacing * 3
            implicitHeight: compact.height * 0.78
            radius: height / 2
            color: Qt.alpha(root.usageColor(root.worstUtil), 0.18)

            Row {
                id: badgeRow
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(Math.min(100, Math.max(0, root.worstUtil))) + "%"
                    font.pointSize: Qt.application.font.pointSize * 0.85
                    font.bold: root.worstUtil >= root.warningThreshold
                }
            }
        }
    }
}