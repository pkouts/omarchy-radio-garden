import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
    id: root
    moduleName: "pkouts.radio-garden"

    // A bar widget is sized from its own implicit size.
    visible: true
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // Live state comes from the lazily-loaded panel, never a bare `backend`.
    readonly property bool playing: panelLoader.item ? panelLoader.item.playing === true : false
    readonly property string stationLabel: (panelLoader.item && panelLoader.item.nowPlaying)
        ? panelLoader.item.nowPlaying : qsTr("Radio Garden")

    // Tooltips are rendered by Omarchy's own widget, so external station names
    // are stripped of control characters and markup before they get there.
    function cleanForTooltip(value) {
        return String(value === undefined || value === null ? "" : value)
            .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")
            .replace(/[<>&"']/g, "")
            .slice(0, 120)
    }

    function injectPanel() {
        if (!panelLoader.item) return
        if ("bar" in panelLoader.item) panelLoader.item.bar = root.bar
        if ("settings" in panelLoader.item) panelLoader.item.settings = root.settings
        if ("anchorItem" in panelLoader.item) panelLoader.item.anchorItem = button
        if ("hostWidget" in panelLoader.item) panelLoader.item.hostWidget = root
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    // Lazily instantiate the panel; bindings only run once it is opened.
    property bool _openPending: false
    property string _pendingPlayId: ""
    property string _pendingPlayTitle: ""

    function open() {
        if (!panelLoader.item) {
            _openPending = true
            panelLoader.active = true
        } else {
            panelLoader.item.open()
        }
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close()
    }

    function toggle() {
        if (panelLoader.item && panelLoader.item.opened) close()
        else open()
    }

    Loader {
        id: panelLoader
        active: false
        source: Qt.resolvedUrl("Panel.qml")
        onLoaded: {
            root.injectPanel()
            if (root._pendingPlayId !== "" && panelLoader.item) {
                const id = root._pendingPlayId, t = root._pendingPlayTitle
                root._pendingPlayId = ""
                panelLoader.item.playChannel(id, t)
            }
            if (root._openPending && panelLoader.item) {
                root._openPending = false
                panelLoader.item.open()
            }
        }
    }

    IpcHandler {
        target: "radio-garden"

        function open(): void { root.open() }
        function close(): void { root.close() }
        function toggle(): void { root.toggle() }
        function play(id: string, title: string): void {
            if (panelLoader.item) {
                panelLoader.item.playChannel(id, title)
            } else {
                root._pendingPlayId = id
                root._pendingPlayTitle = title
                panelLoader.active = true
            }
        }
        function stop(): void {
            if (panelLoader.item) panelLoader.item.stopPlayback()
        }
        function select(id: string, title: string): void {
            if (panelLoader.item) {
                panelLoader.item.selectPlace(id, title)
            } else {
                panelLoader.active = true
                Qt.callLater(function() {
                    if (panelLoader.item) panelLoader.item.selectPlace(id, title)
                })
            }
        }
        function status(): string {
            var loaded = panelLoader.item !== null
            var md = loaded ? (panelLoader.item.mode || "") : ""
            var ch = loaded && panelLoader.item.channels ? panelLoader.item.channels.length : -1
            var fch = loaded && panelLoader.item.filteredChannels ? panelLoader.item.filteredChannels.length : -1
            var pl = loaded && panelLoader.item.places ? panelLoader.item.places.length : -1
            return "{\"ok\":true,\"playing\":" + root.playing
                 + ",\"panelLoaded\":" + loaded
                 + ",\"panelOpen\":" + (loaded && panelLoader.item.opened === true)
                 + ",\"mode\":" + JSON.stringify(md)
                 + ",\"channels\":" + ch
                 + ",\"matched\":" + fch
                 + ",\"places\":" + pl + "}"
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // nf-md-radio_tower (U+F0433) — present in the Omarchy Nerd Font.
        text: "\uF0433"
        tooltipText: root.cleanForTooltip(root.stationLabel)
        active: root.playing

        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) {
                root.toggle()
            } else if (buttonCode === Qt.RightButton) {
                root.toggle()
            } else if (buttonCode === Qt.MiddleButton) {
                if (panelLoader.item && typeof panelLoader.item.stopPlayback === "function")
                    panelLoader.item.stopPlayback()
            }
        }
    }
}
