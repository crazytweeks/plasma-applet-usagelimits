import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // All provider entries as delivered by collect_usage.py:
    // [{ id, name, state, detail, windows: [{id,label,percent,resetsAt}], cached, notice }]
    property var providers: []

    property bool hasError: false
    property string errorMessage: ""
    property bool loading: true
    property date lastUpdated: new Date(0)

    // Ticks so reset countdowns keep counting between polls.
    property date now: new Date()

    // --- Config ---
    readonly property int pollInterval: plasmoid.configuration.pollInterval * 1000
    readonly property int warningThreshold: plasmoid.configuration.warningThreshold
    readonly property int criticalThreshold: plasmoid.configuration.criticalThreshold
    readonly property string panelStyle: plasmoid.configuration.panelStyle
    readonly property string normalColor: plasmoid.configuration.normalColor
    readonly property string warningColor: plasmoid.configuration.warningColor

    readonly property var enabledProviders: {
        var flags = {}
        flags["claude"] = plasmoid.configuration.showClaude
        flags["codex"] = plasmoid.configuration.showCodex
        flags["opencode"] = plasmoid.configuration.showOpencode
        flags["zai"] = plasmoid.configuration.showZai
        return flags
    }

    // --- Fetch state ---
    property bool fetchInFlight: false
    property real lastFetchTime: 0
    readonly property int cooldownMs: 60000

    // Providers that should be rendering something: enabled, and either
    // healthy or reporting a problem the user needs to see.
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

    // Flat row list: every usable window of every enabled provider, used by
    // the compact representation and the tooltip. Rows carry their provider.
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

    function usageColor(percent) {
        if (percent >= root.criticalThreshold) return Kirigami.Theme.negativeTextColor
        if (percent >= root.warningThreshold) return plasmoid.configuration.warningColor || "#E5C07B"
        return plasmoid.configuration.normalColor || "#D77757"
    }

    // Values read back from a `property var` cross a QVariant boundary and
    // arrive as array-like QVariantLists that Array.isArray() rejects, so
    // accept anything with a length instead.
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
        var diffMin = Math.floor((d.getTime() - root.now.getTime()) / 60000)
        if (diffMin <= 0) return "expiring"
        var hrs = Math.floor(diffMin / 60)
        if (hrs >= 24) return Math.floor(hrs / 24) + "d " + (hrs % 24) + "h"
        if (hrs > 0) return hrs + "h " + (diffMin % 60) + "m"
        return diffMin + "m"
    }

    // The DataSource runs commands through `sh -c`, so single-quote every
    // part. The key never hits argv: collect_usage.py reads it from where
    // each CLI stores it.
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