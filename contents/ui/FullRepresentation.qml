import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full

    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.minimumWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true

        QQC2.Label {
            Layout.fillWidth: true
            text: "AI plan usage"
            font.bold: true
            elide: Text.ElideRight
        }

        QQC2.Label {
            visible: root.loading && !root.hasError
            text: "Loading…"
            opacity: 0.6
        }

        QQC2.ToolButton {
            display: QQC2.AbstractButton.IconOnly
            icon.name: "view-refresh"
            enabled: !root.fetchInFlight
            onClicked: root.requestFetch("manual")

            QQC2.ToolTip.text: "Refresh now"
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.longDuration
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: root.hasError
        text: root.errorMessage
        color: Kirigami.Theme.negativeTextColor
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.visibleProviders

        QQC2.Frame {
            id: card
            required property var modelData
            readonly property var provider: modelData
            readonly property bool isOk: provider.state === "ok"
            // Route through toArray: windows crossed a `property var`
            // boundary and need array-like handling, not Array.isArray.
            readonly property var windows: isOk ? root.toArray(provider.windows) : []

            Layout.fillWidth: true
            padding: Kirigami.Units.smallSpacing * 1.5
            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing * 1.5

                // --- Provider header ---
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    Kirigami.Icon {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: card.isOk ? "view-statistics" : "data-warning"
                        color: card.isOk ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.negativeTextColor
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: root.providerRowLabel(card.provider)
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    QQC2.Label {
                        visible: card.provider.detail !== ""
                        text: card.provider.detail
                        opacity: 0.55
                        elide: Text.ElideRight
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 8
                    }

                    QQC2.Label {
                        visible: card.provider.cached === true
                        text: "cached"
                        font.italic: true
                        opacity: 0.55
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: card.isOk && card.provider.notice !== undefined && card.provider.notice !== ""
                    text: card.provider.notice || ""
                    color: Kirigami.Theme.neutralTextColor
                    opacity: 0.8
                    wrapMode: Text.WordWrap
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: !card.isOk && card.provider.detail !== ""
                    text: card.provider.detail
                    color: Kirigami.Theme.negativeTextColor
                    opacity: 0.7
                    wrapMode: Text.WordWrap
                }

                // --- Window rows ---
                Repeater {
                    model: card.windows

                    ColumnLayout {
                        required property var modelData
                        readonly property var win: modelData

                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true

                            QQC2.Label {
                                text: win.label
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            QQC2.Label {
                                visible: win.resetsAt !== ""
                                text: root.formatResetTime(win.resetsAt)
                                opacity: 0.6
                            }

                            QQC2.Label {
                                text: Math.round(win.percent) + "%"
                                horizontalAlignment: Text.AlignRight
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.4
                            radius: 2
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.12)

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.min(100, Math.max(0, win.percent)) / 100
                                radius: parent.radius
                                color: root.usageColor(win.percent)
                            }
                        }
                    }
                }

                QQC2.Label {
                    Layout.fillWidth: true
                    visible: card.isOk && card.windows.length === 0
                    text: "No usage windows reported"
                    opacity: 0.5
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    QQC2.Label {
        Layout.fillWidth: true
        visible: !root.hasError && !root.loading && root.limitRows.length === 0
        text: {
            var any = root.providers.length > 0
            return any ? "No active usage data. Enable providers in settings or sign in via their CLIs."
                       : "No usage data yet. Wait for the first fetch."
        }
        opacity: 0.6
        wrapMode: Text.WordWrap
    }

    Item {
        Layout.fillHeight: true
    }

    QQC2.Label {
        Layout.alignment: Qt.AlignRight
        visible: !root.hasError && !root.loading
        text: "Updated " + Qt.formatTime(root.lastUpdated, "hh:mm")
        opacity: 0.5
    }
}