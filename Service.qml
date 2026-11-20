import QtQuick
import Quickshell
import Quickshell.Io

// Headless singleton that owns the ONE player and the ONE browse state for the
// whole shell. Every bar widget and panel instance binds to this object, so all
// monitors show the same city, the same station list, the same search text and
// the same playback state — and only one mpv process ever runs.
Item {
    id: root

    property var manifest: null
    property var shell: null

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string pluginId: manifest && manifest.id ? manifest.id : "pkouts.radio-garden"
    readonly property string modulesPath: home + "/.config/omarchy/plugins/" + pluginId + "/modules.json"
    readonly property string userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    // ---- browse state (shared by every panel) ----
    property var places: []
    property var filtered: []
    property var channels: []
    property var filteredChannels: []
    property string mode: "places"          // "places" | "channels"
    property string query: ""
    property string chanQuery: ""
    property string selectedId: ""
    property string selectedTitle: ""
    property string statusText: ""
    property bool placesLoaded: false

    // ---- playback state ----
    property bool playing: false
    property bool paused: false
    property string nowPlaying: ""
    property string lastError: ""

    property string currentUrl: ""
    property string currentTitle: ""

    // ---- ducking: mute ourselves while something else plays audio ----
    property bool duckEnabled: false
    property bool otherAudio: false
    property real mpvVolume: 100
    property real fadeTarget: 100
    readonly property string mpvSocket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/radio-garden-mpv.sock"
    readonly property string duckStatePath: home + "/.local/state/omarchy-radio-garden-duck"
    readonly property bool hasStation: currentUrl !== ""

    property string pendingUrl: ""
    property string pendingTitle: ""
    property string intent: ""        // "restart" | "stop" | "pause" | ""

    function clean(value) {
        return String(value === undefined || value === null ? "" : value)
            .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")
            .replace(/[<>&"']/g, "")
            .slice(0, 120)
    }

    // ---------- browsing ----------

    function loadPlaces() {
        if (placesLoaded) return
        catProc.running = true
    }

    function applyFilter() {
        var q = (query || "").toLowerCase()
        var src = places || []
        var out = []
        for (var i = 0; i < src.length && out.length < 300; i++) {
            var p = src[i]
            if (!p) continue
            if (q === "" || (p.title || "").toLowerCase().indexOf(q) >= 0
                          || (p.country || "").toLowerCase().indexOf(q) >= 0) {
                out.push(p)
            }
        }
        filtered = out
    }

    function applyChannelFilter() {
        var q = (chanQuery || "").toLowerCase()
        var src = channels || []
        if (q === "") { filteredChannels = src; return }
        var out = []
        for (var i = 0; i < src.length; i++) {
            var c = src[i]
            if (c && (c.title || "").toLowerCase().indexOf(q) >= 0) out.push(c)
        }
        filteredChannels = out
    }

    function setQuery(value) {
        query = value
        applyFilter()
    }

    function setChanQuery(value) {
        chanQuery = value
        applyChannelFilter()
    }

    function selectPlace(id, title) {
        if (!/^[A-Za-z0-9_-]{1,32}$/.test(String(id || ""))) return
        selectedId = id
        selectedTitle = clean(title)
        channels = []
        filteredChannels = []
        chanQuery = ""
        mode = "channels"
        statusText = qsTr("Loading stations…")
        channelsProc.running = true
    }

    function backToPlaces() {
        mode = "places"
        channels = []
        filteredChannels = []
        chanQuery = ""
        statusText = placesLoaded ? qsTr("%1 cities").arg(places.length) : ""
    }

    // ---------- playback ----------

    function playStation(id, title) {
        if (!/^[A-Za-z0-9_-]{1,32}$/.test(String(id || ""))) return
        startUrl("https://radio.garden/api/ara/content/listen/" + id + "/channel.mp3", clean(title))
    }

    function startUrl(url, title) {
        pendingUrl = url
        pendingTitle = title
        if (proc.running) {
            // Serialize: stop the current stream, then start from its exit.
            intent = "restart"
            proc.running = false
        } else {
            startPending()
        }
    }

    function startPending() {
        if (pendingUrl === "") return
        lastError = ""
        // Start at 0 when something else is already playing, so the first
        // moment of the stream never talks over it.
        var startVol = (duckEnabled && otherAudio) ? 0 : 100
        mpvVolume = startVol
        fadeTarget = startVol
        proc.command = ["mpv", "--no-video", "--really-quiet",
                        "--input-ipc-server=" + mpvSocket,
                        "--volume=" + startVol,
                        "--user-agent=" + userAgent, pendingUrl]
        proc.running = true
        currentUrl = pendingUrl
        currentTitle = pendingTitle
        nowPlaying = pendingTitle
        playing = true
        paused = false
        pendingUrl = ""
    }

    function pause() {
        if (!playing) return
        paused = true
        playing = false
        if (proc.running) {
            intent = "pause"
            proc.running = false
        }
    }

    function resume() {
        if (!hasStation) return
        startUrl(currentUrl, currentTitle)
    }

    function togglePlay() {
        if (playing) pause()
        else if (hasStation) resume()
    }

    function stop() {
        pendingUrl = ""
        if (proc.running) {
            intent = "stop"
            proc.running = false
        } else {
            clearState()
        }
    }

    function clearState() {
        fadeTimer.stop()
        mpvVolume = 100
        fadeTarget = 100
        playing = false
        paused = false
        nowPlaying = ""
        currentUrl = ""
        currentTitle = ""
    }

    // ---------- ducking ----------

    function toggleDuck() { setDuck(!duckEnabled) }

    function setDuck(on) {
        duckEnabled = on === true
        saveDuckState()
        if (!duckEnabled) {
            fadeTo(100)
            return
        }
        audioScan.running = true
        if (playing) fadeTo(otherAudio ? 0 : 100)
    }

    // Ramp the stream volume by 5 every 50 ms: 100 -> 0 in exactly one second.
    function fadeTo(target) {
        fadeTarget = Math.max(0, Math.min(100, target))
        if (!proc.running) { mpvVolume = fadeTarget; return }
        if (!fadeTimer.running) fadeTimer.start()
    }

    function fadeTick() {
        if (!proc.running) { fadeTimer.stop(); return }
        var d = fadeTarget - mpvVolume
        if (Math.abs(d) < 5) { sendVolume(fadeTarget); fadeTimer.stop(); return }
        sendVolume(mpvVolume + (d > 0 ? 5 : -5))
    }

    function sendVolume(v) {
        mpvVolume = Math.round(v)
        if (!proc.running || volumeProc.running) return
        volumeProc.command = ["sh", "-c",
            "printf '%s' '{\"command\":[\"set_property\",\"volume\"," + mpvVolume +
            "]}' | socat -t 1 - UNIX-CONNECT:" + mpvSocket]
        volumeProc.running = true
    }

    // "Other audio" = any running PipeWire output stream that is not our mpv.
    // pw-dump is the only source that reports live node state on PipeWire;
    // pactl's sink-input listing no longer includes it, so fall back to that
    // for plain PulseAudio setups.
    function scanAudio(text) {
        var t = String(text || "")
        var other = false
        if (t.charAt(0) === "[") {
            try {
                var nodes = JSON.parse(t)
                for (var i = 0; i < nodes.length; i++) {
                    var info = nodes[i].info || {}
                    if (info.state !== "running") continue
                    var props = info.props || {}
                    if (props["media.class"] !== "Stream/Output/Audio") continue
                    var bin = String(props["application.process.binary"] || "")
                    var name = String(props["application.name"] || "")
                    if (bin === "mpv" || name === "mpv") continue
                    other = true
                    break
                }
            } catch (e) {}
        } else {
            var blocks = t.split(/\n\s*\n/)
            for (var j = 0; j < blocks.length; j++) {
                var b = blocks[j]
                if (b.indexOf("State: RUNNING") === -1) continue
                if (/Corked:\s*yes/.test(b)) continue
                if (/application\.process\.binary = "mpv"/.test(b)) continue
                other = true
                break
            }
        }
        if (other !== otherAudio) {
            otherAudio = other
            if (duckEnabled && playing) fadeTo(other ? 0 : 100)
        }
    }

    function saveDuckState() {
        stateWrite.command = ["sh", "-c",
            "printf '%s' '" + (duckEnabled ? "1" : "0") + "' > '" + duckStatePath + "'"]
        stateWrite.running = true
    }

    // ---------- data ----------

    Process {
        id: catProc
        command: ["cat", root.modulesPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(String(this.text || "[]"))
                    root.places = arr
                    root.placesLoaded = true
                    root.applyFilter()
                    root.statusText = qsTr("%1 cities").arg(arr.length)
                } catch (e) {
                    root.statusText = qsTr("Could not read station list")
                }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) root.statusText = qsTr("Could not read station list")
        }
    }

    Process {
        id: channelsProc
        // -f fails on HTTP errors; --max-filesize aborts oversized bodies
        // mid-transfer so the collector can never buffer an unbounded response.
        command: ["curl", "-sS", "-f", "--max-time", "25", "--max-filesize", "4000000",
                  "-A", root.userAgent,
                  "https://radio.garden/api/ara/content/page/" + root.selectedId + "/channels?s=1&hls=1&hl=en"]
        stdout: StdioCollector {
            onStreamFinished: {
                var text = String(this.text || "")
                if (text.length > 4000000) {
                    root.channels = []
                    root.filteredChannels = []
                    root.statusText = qsTr("Station list too large")
                    return
                }
                var out = []
                try {
                    var doc = JSON.parse(text)
                    var content = (doc.data && doc.data.content) || []
                    for (var i = 0; i < content.length && out.length < 1000; i++) {
                        var block = content[i]
                        if (block.itemsType !== "channel") continue
                        var items = block.items || []
                        for (var j = 0; j < items.length && out.length < 1000; j++) {
                            var pg = items[j].page
                            if (!pg || typeof pg.url !== "string") continue
                            var cid = (pg.url.split("/").pop()) || ""
                            if (!/^[A-Za-z0-9_-]{1,32}$/.test(cid)) continue
                            out.push({ title: String(pg.title || "").slice(0, 200), id: cid })
                        }
                    }
                } catch (e) {}
                root.channels = out
                root.applyChannelFilter()
                root.statusText = out.length > 0
                    ? qsTr("%1 stations in %2").arg(out.length).arg(root.selectedTitle)
                    : qsTr("No stations found")
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0 && root.channels.length === 0)
                root.statusText = qsTr("Could not load stations")
        }
    }

    Process {
        id: proc
        stderr: StdioCollector {
            onStreamFinished: root.lastError = String(this.text || "").trim()
        }
        onExited: function(exitCode) {
            var why = root.intent
            root.intent = ""
            if (why === "restart") {
                root.startPending()
                return
            }
            if (why === "stop") {
                root.clearState()
                return
            }
            if (why === "pause") {
                return          // paused state was set before stopping
            }
            // Natural end (or failure) of the stream.
            root.playing = false
            if (exitCode !== 0) {
                var first = (root.lastError || "").split("\n")[0]
                if (first !== "") root.lastError = first
            }
        }
    }

    Timer {
        id: fadeTimer
        interval: 50
        repeat: true
        onTriggered: root.fadeTick()
    }

    Timer {
        id: duckPoll
        interval: 700
        repeat: true
        running: root.duckEnabled
        onTriggered: if (!audioScan.running) audioScan.running = true
    }

    Process {
        id: audioScan
        command: ["sh", "-c", "pw-dump Node 2>/dev/null || pactl list sink-inputs 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.scanAudio(String(this.text || ""))
        }
    }

    Process { id: volumeProc }

    Process { id: stateWrite }

    Process {
        id: stateRead
        command: ["cat", root.duckStatePath]
        stdout: StdioCollector {
            onStreamFinished: {
                if (String(this.text || "").trim() === "1") root.duckEnabled = true
            }
        }
    }

    Component.onCompleted: {
        loadPlaces()
        stateRead.running = true
    }
}
