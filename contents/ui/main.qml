import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // All provider entries as delivered by collect_usage.py:
    // [{ id, name, state, detail, windows: [{id,label,percent,resetsAt}],
    //    extraUsage, resetGrant, cached, notice }]
    property var providers: []

    property bool hasError: false
    property string errorMessage: ""
    property bool loading: true
    property date lastUpdated: new Date(0)

    // Ticks so reset countdowns and pace markers keep counting between polls.
    property date now: new Date()

    // --- Config ---
    readonly property int pollInterval: plasmoid.configuration.pollInterval * 1000
    readonly property int warningThreshold: plasmoid.configuration.warningThreshold
    readonly property int criticalThreshold: plasmoid.configuration.criticalThreshold
    readonly property string panelStyle: plasmoid.configuration.panelStyle || "dual_rings"
    readonly property string gaugeLabel: plasmoid.configuration.gaugeLabel || "percent"
    readonly property string panelLabelMode: plasmoid.configuration.panelLabelMode || "plan"
    readonly property string popupStyle: plasmoid.configuration.popupStyle || "claudemeter"
    readonly property bool showPace: plasmoid.configuration.showPace !== false
    readonly property string timeFormat: plasmoid.configuration.timeFormat || "24h"
    readonly property string normalColor: plasmoid.configuration.normalColor || "#D77757"
    readonly property string warningColor: plasmoid.configuration.warningColor || "#E5C07B"

    readonly property var enabledProviders: {
        var flags = {}
        flags["claude"] = plasmoid.configuration.showClaude
        flags["codex"] = plasmoid.configuration.showCodex
        flags["opencode"] = plasmoid.configuration.showOpencode
        flags["zai"] = plasmoid.configuration.showZai
        flags["antigravity"] = plasmoid.configuration.showAntigravity
        flags["commandcode"] = plasmoid.configuration.showCommandcode
        return flags
    }

    // --- Fetch state ---
    property bool fetchInFlight: false
    property real lastFetchTime: 0
    readonly property int cooldownMs: 60000

    function providerEnabled(p) {
        var flags = root.enabledProviders
        return flags[p.id] !== false
    }

    // Visible provider list for the popup and the panel. Healthy providers
    // come first, then problems, so trouble never hides working data.
    readonly property var visibleProviders: {
        var good = []
        var bad = []
        for (var i = 0; i < root.providers.length; i++) {
            var p = root.providers[i]
            if (!root.providerEnabled(p)) continue
            if (p.state === "ok") good.push(p)
            else bad.push(p)
        }
        return good.concat(bad)
    }

    // Flat row list: every usable window of every enabled provider.
    readonly property var limitRows: {
        var rows = []
        for (var i = 0; i < root.visibleProviders.length; i++) {
            var p = root.visibleProviders[i]
            if (p.state !== "ok") continue
            var windows = root.toArray(p.windows)
            for (var j = 0; j < windows.length; j++) {
                rows.push({
                    providerId: p.id,
                    provider: p.name,
                    label: windows[j].label,
                    util: windows[j].percent || 0,
                    resets: windows[j].resetsAt || ""
                })
            }
        }
        return rows
    }

    // Highest usage across all rows drives the single-worst panel style.
    readonly property real worstUtil: {
        var worst = 0
        for (var i = 0; i < root.limitRows.length; i++) {
            var value = root.limitRows[i].util
            if (value > worst) worst = value
        }
        return worst
    }

    // Distinct glyphs: initials alone would collide (Claude / Codex both "C").
    function providerGlyph(p) {
        var map = { "claude": "C", "codex": "X", "opencode": "G", "zai": "Z",
                    "antigravity": "A", "commandcode": "\u25C6" }
        var g = p && p.id ? map[p.id] : undefined
        return g ? g : (p && p.name ? p.name.charAt(0).toUpperCase() : "?")
    }

    function providerGlyphForId(providerId, providerName) {
        return providerGlyph({ id: providerId, name: providerName })
    }

    // Short plan/tier badge shown beside panel gauges/bars (like MAX / PRO in claudemeter).
    function providerPlanBadge(p) {
        if (!p) return ""
        var d = String(p.detail || "").trim()
        if (p.id === "claude") return d ? d.toUpperCase() : "PRO"
        if (p.id === "codex") {
            var stripped = d.replace(/^ChatGPT\s+/i, "").trim().toUpperCase()
            return stripped || "PLUS"
        }
        if (p.id === "opencode") return "GO"
        if (p.id === "zai") return "GLM"
        if (p.id === "antigravity") return "AGY"
        if (p.id === "commandcode") {
            return (d && d !== "Command Code") ? d.toUpperCase() : "CMD"
        }
        return providerGlyph(p)
    }

    function providerShortName(p) {
        if (!p) return ""
        var map = {
            "claude": "Claude",
            "codex": "Codex",
            "opencode": "Go",
            "zai": "Z.ai",
            "antigravity": "Agy",
            "commandcode": "Cmd"
        }
        return map[p.id] || p.name || ""
    }

    // Claudemeter-style section heading ("Claude Code Usage - MAX", "Codex Usage - PLUS", etc.)
    function providerHeaderTitle(p) {
        if (!p) return ""
        if (p.state !== "ok") return providerRowLabel(p)
        var d = String(p.detail || "").trim()
        if (p.id === "claude") {
            return "Claude Code Usage" + (d ? " - " + d.toUpperCase() : "")
        }
        if (p.id === "codex") {
            var tier = d.replace(/^ChatGPT\s+/i, "").trim().toUpperCase()
            return "Codex Usage" + (tier ? " - " + tier : "")
        }
        if (p.id === "opencode") return "OpenCode Go Usage"
        if (p.id === "zai") {
            return "Z.ai Usage" + (d ? " - " + d : "")
        }
        if (p.id === "antigravity") return "Antigravity Usage"
        if (p.id === "commandcode") {
            var plan = (d && d !== "Command Code") ? " - " + d.toUpperCase() : ""
            return "Command Code Usage" + plan
        }
        return p.name + " Usage"
    }

    // Descriptive window label for Claudemeter popup bars ("5-Hour Window", "Weekly (All Models)", etc.)
    function windowFullLabel(win) {
        if (!win) return ""
        var id = String(win.id || "")
        var lbl = String(win.label || "")
        if (lbl === "5h" || id === "five_hour" || id === "rolling") return "5-Hour Window"
        if (lbl === "7d" || id === "seven_day") return "Weekly (All Models)"
        if (lbl === "Weekly" || id === "weekly") return "Weekly Window"
        if (lbl === "Monthly" || id === "monthly") return "Monthly Window"
        if (lbl === "Claude/GPT 5h") return "Claude / GPT (5-Hour)"
        if (lbl === "Claude/GPT Weekly") return "Claude / GPT (Weekly)"
        if (lbl === "Gemini 5h") return "Gemini (5-Hour)"
        if (lbl === "Gemini Weekly") return "Gemini (Weekly)"
        if (lbl === "MCP") return "MCP Tool Quota"
        if (lbl === "Credits") return "Monthly Credits"
        return lbl
    }

    // Number of pace segments for a window (5 for 5h, 7 for 7d/weekly, 6 for monthly).
    function windowSegments(win) {
        if (!win) return 0
        var id = String(win.id || "")
        var lbl = String(win.label || "")
        if (id === "five_hour" || id === "rolling" || /5h|5-hour/i.test(lbl)) return 5
        if (id === "seven_day" || id === "weekly" || id === "weekly_scoped" || /7d|weekly/i.test(lbl)) return 7
        if (id === "monthly" || /monthly/i.test(lbl)) return 6
        return 0
    }

    // Window duration in milliseconds for computing elapsed pace fraction.
    function windowDurationMs(win) {
        if (!win) return 0
        var id = String(win.id || "")
        var lbl = String(win.label || "")
        if (id === "five_hour" || id === "rolling" || /5h|5-hour/i.test(lbl)) return 5 * 60 * 60 * 1000
        if (id === "seven_day" || id === "weekly" || id === "weekly_scoped" || /7d|weekly/i.test(lbl)) return 7 * 24 * 60 * 60 * 1000
        if (id === "monthly" || /monthly/i.test(lbl)) return 30 * 24 * 60 * 60 * 1000
        return 0
    }

    // Fraction 0..1 of a window that has elapsed, or -1 when unknown.
    function paceFraction(resetsAt, windowMs) {
        if (!resetsAt || !windowMs) return -1
        var end = new Date(resetsAt).getTime()
        if (isNaN(end)) return -1
        var elapsed = windowMs - (end - root.now.getTime())
        if (elapsed < 0 || elapsed > windowMs) return -1
        return elapsed / windowMs
    }

    // Highest window percentage of one provider (for marks and accents).
    function providerWorst(p) {
        var windows = toArray(p ? p.windows : [])
        var worst = 0
        for (var i = 0; i < windows.length; i++) {
            if (windows[i].percent > worst) worst = windows[i].percent
        }
        return worst
    }

    function usageColor(percent) {
        if (percent >= root.criticalThreshold) return Kirigami.Theme.negativeTextColor
        if (percent >= root.warningThreshold) return root.warningColor
        return root.normalColor
    }

    function toArray(value) {
        if (!value) return []
        if (value.length !== undefined) return value
        return []
    }

    function providerRowLabel(p) {
        if (p.state === "ok") return p.name
        if (p.state === "unauthenticated") return p.name + " — not signed in"
        if (p.state === "token_expired") return p.name + " — token expired"
        if (p.state === "rate_limited") return p.name + " — rate limited"
        return p.name + " — error"
    }

    function formatResetTime(isoString) {
        if (!isoString) return ""
        var d = new Date(isoString)
        if (isNaN(d.getTime())) return ""
        var diffMs = d.getTime() - root.now.getTime()
        if (diffMs <= 0) return "expired"
        var diffMin = Math.floor(diffMs / 60000)
        var hrs = Math.floor(diffMin / 60)
        if (hrs >= 24) return Math.floor(hrs / 24) + "d " + (hrs % 24) + "h"
        if (hrs > 0) return hrs + "h " + (diffMin % 60) + "m"
        return diffMin + "m"
    }

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    function scriptCommand() {
        var scriptPath = decodeURIComponent(Qt.resolvedUrl("../scripts/collect_usage.py").toString().replace(/^file:\/\/(?=\/)/, ""))
        return "python3 " + root.shellQuote(scriptPath)
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            root.parseUsageData(data["stdout"])
            disconnectSource(sourceName)
        }
        function exec(cmd) {
            if (cmd) connectSource(cmd)
        }
    }

    function requestFetch(source) {
        if (root.fetchInFlight) return
        if (source !== "startup" && source !== "manual"
                && Date.now() - root.lastFetchTime < root.cooldownMs) return
        root.fetchInFlight = true
        root.loading = true
        root.lastFetchTime = Date.now()
        fetchTimeoutTimer.restart()
        executable.exec(root.scriptCommand())
    }

    function parseUsageData(stdout) {
        fetchTimeoutTimer.stop()
        root.fetchInFlight = false
        root.loading = false
        root.lastUpdated = new Date()

        var data
        try {
            data = JSON.parse(stdout)
        } catch (e) {
            root.hasError = true
            root.errorMessage = "Failed to parse the collector's output"
            return
        }

        if (!data || !Array.isArray(data.providers)) {
            root.hasError = true
            root.errorMessage = "The collector returned no provider data"
            return
        }

        root.hasError = false
        root.errorMessage = ""
        root.providers = data.providers
    }

    // --- Timers ---
    Timer {
        id: pollTimer
        interval: root.pollInterval
        running: true
        repeat: true
        onTriggered: root.requestFetch("poll")
        Component.onCompleted: root.requestFetch("startup")
    }

    Timer {
        id: clockTimer
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Timer {
        id: fetchTimeoutTimer
        interval: 45000
        onTriggered: {
            executable.disconnectSource(root.scriptCommand())
            root.fetchInFlight = false
            root.loading = false
            root.hasError = true
            root.errorMessage = "Request timed out"
        }
    }

    // --- Widget setup ---
    switchWidth: Kirigami.Units.gridUnit * 12
    switchHeight: Kirigami.Units.gridUnit * 10

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}
}
