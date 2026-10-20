import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQC

KCM.SimpleKCM {
    id: configGeneral

    property alias cfg_pollInterval: pollIntervalSpinBox.value
    property alias cfg_warningThreshold: warningSpinBox.value
    property alias cfg_criticalThreshold: criticalSpinBox.value
    property string cfg_panelStyle
    property alias cfg_showClaude: showClaudeBox.checked
    property alias cfg_showCodex: showCodexBox.checked
    property alias cfg_showOpencode: showOpencodeBox.checked
    property alias cfg_showZai: showZaiBox.checked
    property string cfg_normalColor
    property string cfg_warningColor

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: pollIntervalSpinBox
            Kirigami.FormData.label: "Poll interval (seconds):"
            from: 60
            to: 3600
            stepSize: 60
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Panel appearance"
        }

        QQC2.ComboBox {
            id: panelStyleBox
            Kirigami.FormData.label: "Panel style:"
            textRole: "label"
            valueRole: "value"
            model: [
                { label: "Mini bars per window", value: "bars" },
                { label: "Letters and percentages", value: "text" },
                { label: "Single worst usage", value: "worst" }
            ]
            onActivated: configGeneral.cfg_panelStyle = currentValue
            Component.onCompleted: {
                var found = currentIndex
                for (var i = 0; i < model.length; i++) {
                    if (model[i].value === configGeneral.cfg_panelStyle) {
                        found = i
                        break
                    }
                }
                currentIndex = found
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Providers"
        }

        QQC2.CheckBox {
            id: showClaudeBox
            Kirigami.FormData.label: "Claude:"
            text: "Show Claude usage"
        }

        QQC2.CheckBox {
            id: showCodexBox
            Kirigami.FormData.label: "Codex:"
            text: "Show Codex (ChatGPT plan) usage"
        }

        QQC2.CheckBox {
            id: showOpencodeBox
            Kirigami.FormData.label: "OpenCode Go:"
            text: "Show OpenCode Go usage"
        }

        QQC2.CheckBox {
            id: showZaiBox
            Kirigami.FormData.label: "Z.ai:"
            text: "Show Z.ai (GLM Coding Plan) usage"
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Thresholds"
        }

        QQC2.SpinBox {
            id: warningSpinBox
            Kirigami.FormData.label: "Warning threshold (%):"
            from: 10
            to: criticalSpinBox.value
            stepSize: 5
        }

        QQC2.SpinBox {
            id: criticalSpinBox
            Kirigami.FormData.label: "Critical threshold (%):"
            from: warningSpinBox.value
            to: 100
            stepSize: 5
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            text: "Beyond the critical threshold the bar uses the theme's negative color."
            opacity: 0.5
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Colors"
        }

        KQC.ColorButton {
            Kirigami.FormData.label: "Normal color:"
            color: configGeneral.cfg_normalColor
            onColorChanged: {
                if (String(color) !== configGeneral.cfg_normalColor)
                    configGeneral.cfg_normalColor = String(color)
            }
        }

        KQC.ColorButton {
            Kirigami.FormData.label: "Warning color:"
            color: configGeneral.cfg_warningColor
            onColorChanged: {
                if (String(color) !== configGeneral.cfg_warningColor)
                    configGeneral.cfg_warningColor = String(color)
            }
        }
    }
}