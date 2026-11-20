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
        proc.command = ["mpv", "--no-video", "--really-quiet",
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
        playing = false
        paused = false
        nowPlaying = ""
        currentUrl = ""
        currentTitle = ""
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

    Component.onCompleted: loadPlaces()
}
