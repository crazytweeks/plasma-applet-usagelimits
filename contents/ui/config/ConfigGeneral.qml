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
    property string cfg_colorTheme
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
                { label: "Rings — round gauge per provider", value: "rings" },
                { label: "Glow — chip brightness = usage", value: "glow" },
                { label: "Capsule — one segmented strip", value: "capsule" },
                { label: "Dots — severity dots (smallest)", value: "dots" },
                { label: "Bars — mini bars per window", value: "bars" },
                { label: "Letters and percentages", value: "text" },
                { label: "Single worst usage pill", value: "worst" }
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
            Kirigami.FormData.label: "Color theme"
        }

        QQC2.ComboBox {
            id: colorThemeBox
            Kirigami.FormData.label: "Theme:"
            textRole: "label"
            valueRole: "value"
            model: [
                { label: "Custom (colors below)", value: "custom", normal: "", warning: "" },
                { label: "Warm (Claude orange)", value: "warm", normal: "#D77757", warning: "#E5C07B" },
                { label: "Sunset (pink → amber)", value: "sunset", normal: "#E06C75", warning: "#F5A97F" },
                { label: "Nord (blue → teal)", value: "nord", normal: "#88C0D0", warning: "#EBCB8B" },
                { label: "Mono (grayscale)", value: "mono", normal: "#B8BAC2", warning: "#D0D2DA" }
            ]
            onActivated: {
                configGeneral.cfg_colorTheme = currentValue
                var entry = model[currentIndex]
                if (entry && entry.normal) configGeneral.cfg_normalColor = entry.normal
                if (entry && entry.warning) configGeneral.cfg_warningColor = entry.warning
            }
            Component.onCompleted: {
                var found = currentIndex
                for (var i = 0; i < model.length; i++) {
                    if (model[i].value === configGeneral.cfg_colorTheme) {
                        found = i
                        break
                    }
                }
                currentIndex = found
            }
        }

        QQC2.Label {
            Kirigami.FormData.label: ""
            text: "Picking a theme fills the colors below; adjust them freely afterwards."
            opacity: 0.5
            wrapMode: Text.WordWrap
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
                if (String(color) !== configGeneral.cfg_normalColor) {
                    configGeneral.cfg_normalColor = String(color)
                    configGeneral.cfg_colorTheme = "custom"
                }
            }
        }

        KQC.ColorButton {
            Kirigami.FormData.label: "Warning color:"
            color: configGeneral.cfg_warningColor
            onColorChanged: {
                if (String(color) !== configGeneral.cfg_warningColor) {
                    configGeneral.cfg_warningColor = String(color)
                    configGeneral.cfg_colorTheme = "custom"
                }
            }
        }
    }
}