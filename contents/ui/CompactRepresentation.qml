import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    readonly property bool barsMode: root.panelStyle === "bars"
    readonly property bool textMode: root.panelStyle === "text"
    // "worst" or anything unrecognized falls back to the single number.

    readonly property string summaryText: {
        var parts = []
        var rows = root.limitRows
        for (var i = 0; i < rows.length; i++) {
            parts.push(rows[i].provider + " " + rows[i].label + ": " + Math.round(rows[i].util) + "%")
        }
        if (parts.length === 0) return "Usage Limits — no usage data yet"
        return parts.join("\n")
    }

    // The number shown in text styles. textMode abbreviates each provider
    // to its first letter; worstMode shows the single highest window.
    readonly property string badgeText: {
        if (textMode) {
            var parts = []
            var rows = root.limitRows
            for (var i = 0; i < rows.length; i++) {
                var initial = rows[i].provider.charAt(0).toUpperCase()
                parts.push(initial + " " + Math.round(rows[i].util) + "%")
            }
            return parts.join("  ")
        }
        return Math.round(Math.min(100, Math.max(0, root.worstUtil))) + "%"
    }

    // Compact sizing adapts: in horizontal panels height is bounded, in
    // vertical panels width is. Clamp differents smalls for tiny sizes.
    Layout.minimumWidth: barsMode ? barRow.implicitWidth + Kirigami.Units.smallSpacing * 3
                                  : badge.implicitWidth + Kirigami.Units.smallSpacing * 4
    Layout.minimumHeight: Kirigami.Units.gridUnit
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    onClicked: root.expanded = !root.expanded
    hoverEnabled: true

    QQC2.ToolTip {
        visible: compact.containsMouse
        delay: Kirigami.Units.longDuration
        text: root.hasError ? root.errorMessage : compact.summaryText
    }

    Rectangle {
        id: badge
        anchors.centerIn: parent
        visible: !barsMode
        implicitWidth: badgeRow.implicitWidth + Kirigami.Units.smallSpacing * 2.5
        implicitHeight: compact.height * 0.82
        radius: height / 2
        color: Qt.alpha(root.usageColor(root.worstUtil), 0.18)

        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                visible: root.hasError
                anchors.verticalCenter: parent.verticalCenter
                width: Kirigami.Units.iconSizes.small
                height: width
                source: "data-warning"
                color: Kirigami.Theme.negativeTextColor
            }

            QQC2.Label {
                visible: !root.hasError
                anchors.verticalCenter: parent.verticalCenter
                text: compact.badgeText
                font.pointSize: Qt.application.font.pointSize * 0.85
                font.bold: root.worstUtil >= root.warningThreshold
                minimumPointSize: 9
            }
        }
    }

    Row {
        id: barRow
        anchors.centerIn: parent
        visible: barsMode
        spacing: Kirigami.Units.smallSpacing * 2.5
        // spacing between providers; group gap added by the last item in each
        // provider group is realized via a per-provider grouping below.

        Repeater {
            // One column of mini-bars per provider.
            model: root.visibleProviders

            Rectangle {
                id: providerColumn
                required property var modelData
                readonly property var provider: modelData
                readonly property bool isOk: provider.state === "ok"

                width: {
                    var windowCount = root.toArray(provider.windows).length
                    if (windowCount === 0) return Kirigami.Units.gridUnit * 0.6
                    return windowCount * Kirigami.Units.gridUnit * 0.6
                        + (windowCount - 1) * providerColumn.spacingInner
                }
                height: compact.height * 0.72
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"

                readonly property real spacingInner: Kirigami.Units.smallSpacing

                Row {
                    anchors.centerIn: parent
                    spacing: providerColumn.spacingInner

                    Repeater {
                        model: providerColumn.isOk ? root.toArray(providerColumn.provider.windows) : []

                        Rectangle {
                            required property var modelData
                            readonly property var win: modelData

                            width: Kirigami.Units.gridUnit * 0.6
                            height: providerColumn.height
                            radius: 2
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.12)

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: parent.height * Math.min(100, Math.max(0, parent.win ? parent.win.percent : 0)) / 100
                                radius: parent.radius
                                color: parent.win ? root.usageColor(parent.win.percent) : "transparent"
                            }
                        }
                    }
                }

                Kirigami.Icon {
                    visible: providerColumn.isOk
                        ? root.toArray(providerColumn.provider.windows).length === 0
                        : true
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