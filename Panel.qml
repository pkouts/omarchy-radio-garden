import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Radio Garden panel: browse cities (from the bundled modules.json), drill into
// a city's stations (Radio Garden API), and play the stream with mpv.
Panel {
    id: root
    moduleName: "pkouts.radio-garden"
    ipcTarget: "radio-garden"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string modulesPath: home + "/.config/omarchy/plugins/" + root.moduleName + "/modules.json"
    readonly property string userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

    // state
    property var places: []
    property var filtered: []
    property var channels: []
    property var filteredChannels: []
    property string mode: "places"          // "places" | "channels"
    property string query: ""
    property string chanQuery: ""
    property string selectedId: ""
    property string selectedTitle: ""
    property string nowPlaying: ""
    property bool playing: false
    property string statusText: ""
    property string lastError: ""
    property string pendingUrl: ""
    property string pendingTitle: ""
    property bool restarting: false
    property bool stopping: false

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

    function selectPlace(id, title) {
        selectedId = id
        selectedTitle = title
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
        statusText = ""
    }

    function playChannel(id, title) {
        if (!id) return
        pendingUrl = "https://radio.garden/api/ara/content/listen/" + id + "/channel.mp3"
        pendingTitle = title
        if (playProc.running) {
            // Serialize: stop the current stream, then start the new one from
            // its onExited. Avoids pkill racing (and killing) the new stream.
            restarting = true
            playProc.running = false
        } else {
            startPending()
        }
    }

    function startPending() {
        if (pendingUrl === "") return
        root.lastError = ""
        playProc.command = ["mpv", "--no-video", "--really-quiet",
                            "--user-agent=" + userAgent, pendingUrl]
        playProc.running = true
        root.nowPlaying = pendingTitle
        root.playing = true
        root.statusText = qsTr("Playing: %1").arg(pendingTitle)
        pendingUrl = ""
    }

    function stopPlayback() {
        pendingUrl = ""
        if (playProc.running) {
            stopping = true
            playProc.running = false
        } else {
            playing = false
            nowPlaying = ""
            statusText = qsTr("Stopped")
        }
    }

    // --- load the bundled city list once ---
    Process {
        id: catProc
        command: ["cat", root.modulesPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var arr = JSON.parse(String(text || "[]"))
                    root.places = arr
                    root.applyFilter()
                    root.statusText = qsTr("%1 cities").arg(arr.length)
                } catch (e) {
                    root.statusText = qsTr("Could not read station list")
                }
            }
        }
        onExited: function(exitCode) { if (exitCode !== 0) root.statusText = qsTr("Could not read station list") }
    }

    // --- fetch stations for the selected city ---
    Process {
        id: channelsProc
        command: ["curl", "-s", "--max-time", "25", "-A", root.userAgent,
                  "https://radio.garden/api/ara/content/page/" + root.selectedId + "/channels?s=1&hls=1&hl=en"]
        stdout: StdioCollector {
            onStreamFinished: {
                var text = String(this.text || "")
                var out = []
                try {
                    var doc = JSON.parse(text)
                    var content = (doc.data && doc.data.content) || []
                    for (var i = 0; i < content.length; i++) {
                        var block = content[i]
                        if (block.itemsType !== "channel") continue
                        var items = block.items || []
                        for (var j = 0; j < items.length; j++) {
                            var pg = items[j].page
                            if (!pg || !pg.url) continue
                            var cid = (pg.url.split("/").pop()) || ""
                            out.push({ title: pg.title || "", id: cid })
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
                root.statusText = qsTr("Network error")
        }
    }

    Process {
        id: playProc
        stderr: StdioCollector {
            onStreamFinished: root.lastError = String(this.text || "").trim()
        }
        onExited: function(exitCode) {
            if (root.restarting) {
                root.restarting = false
                root.startPending()
                return
            }
            if (root.stopping) {
                root.stopping = false
                root.playing = false
                root.nowPlaying = ""
                root.statusText = qsTr("Stopped")
                return
            }
            root.playing = false
            if (exitCode !== 0) {
                var first = (root.lastError || "").split("\n")[0]
                root.statusText = first !== ""
                    ? qsTr("Stream failed: ") + first
                    : qsTr("Stream ended or failed")
                console.warn("radio-garden: mpv exit " + exitCode + " :: " + root.lastError)
            } else {
                root.statusText = qsTr("Stream ended")
            }
        }
    }

    Component.onCompleted: catProc.running = true

    // --- popup ---
    KeyboardPanel {
        id: panel

        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        contentWidth: Style.space(420)
        contentHeight: Style.space(560)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(12)
            spacing: Style.space(8)

            // header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: qsTr("Radio Garden")
                    color: root.barForeground
                    font.pixelSize: Style.font.title
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.statusText
                    color: "#9aa0a6"
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    Layout.maximumWidth: Style.space(220)
                }
            }

            // search (places mode)
            TextField {
                id: searchField
                Layout.fillWidth: true
                visible: root.mode === "places"
                placeholderText: qsTr("Search a city…")
                text: root.query
                onTextEdited: { root.query = text; root.applyFilter() }
            }

            // back row (channels mode)
            RowLayout {
                Layout.fillWidth: true
                visible: root.mode === "channels"
                Text {
                    text: "‹ " + qsTr("Back")
                    color: "#5aa9ff"
                    font.pixelSize: Style.font.bodySmall
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.backToPlaces()
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.selectedTitle
                    color: "#9aa0a6"
                    font.pixelSize: Style.font.bodySmall
                }
            }

            // station search (channels mode)
            TextField {
                id: stationsSearchField
                Layout.fillWidth: true
                visible: root.mode === "channels"
                placeholderText: qsTr("Search stations…")
                text: root.chanQuery
                onTextEdited: { root.chanQuery = text; root.applyChannelFilter() }
            }

            Text {
                visible: root.mode === "channels" && root.chanQuery !== ""
                         && root.filteredChannels.length === 0
                Layout.fillWidth: true
                text: qsTr("No stations match \"%1\"").arg(root.chanQuery)
                color: "#9aa0a6"
                font.pixelSize: Style.font.bodySmall
            }

            // places list
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.mode === "places"
                clip: true
                model: root.filtered
                spacing: Style.space(2)

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: Style.space(44)
                    radius: Style.space(6)
                    color: hover.containsMouse ? "#ffffff14" : "transparent"

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(10)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        spacing: 1
                        Text {
                            width: parent.width
                            text: modelData.title || ""
                            color: root.barForeground
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: modelData.country || ""
                            color: "#9aa0a6"
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectPlace(modelData.id, modelData.title)
                    }
                }
            }

            // channels list
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.mode === "channels"
                clip: true
                model: root.filteredChannels
                spacing: Style.space(2)

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: Style.space(40)
                    radius: Style.space(6)
                    color: chanHover.containsMouse ? "#ffffff14" : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(10)
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        text: modelData.title || ""
                        color: root.barForeground
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: chanHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.playChannel(modelData.id, modelData.title)
                    }
                }
            }

            // footer
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: root.playing
                        ? qsTr("▶ %1").arg(root.nowPlaying)
                        : qsTr("Idle")
                    color: root.playing ? "#5aa9ff" : "#9aa0a6"
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: qsTr("Stop")
                    color: root.playing ? "#ff6b6b" : "#555b60"
                    font.pixelSize: Style.font.bodySmall
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.playing) root.stopPlayback()
                    }
                }
            }
        }
    }
}
