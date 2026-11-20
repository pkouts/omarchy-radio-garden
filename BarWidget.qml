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


    // The shell exposes the plugin's single Service instance through
    // bar.shell.serviceFor(). Every bar widget on every monitor resolves to
    // the same object, so playback state is shared instead of per-instance.
    readonly property var service: (bar && bar.shell && typeof bar.shell.serviceFor === "function")
        ? bar.shell.serviceFor(moduleName) : null

    readonly property bool playing: service ? service.playing === true : false
    readonly property bool paused: service ? service.paused === true : false
    readonly property string stationLabel: (service && service.nowPlaying)
        ? service.nowPlaying : qsTr("Radio Garden")

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
        if ("service" in panelLoader.item) panelLoader.item.service = root.service
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()
    onServiceChanged: injectPanel()

    // Lazily instantiate the panel; bindings only run once it is opened.
    property bool _openPending: false

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
            if (root.service) root.service.playStation(id, title)
        }
        function pause(): void { if (root.service) root.service.pause() }
        function resume(): void { if (root.service) root.service.resume() }
        function stop(): void { if (root.service) root.service.stop() }
        function back(): void { if (root.service) root.service.backToPlaces() }
        function search(text: string): void { if (root.service) root.service.setQuery(text) }
        function searchStations(text: string): void { if (root.service) root.service.setChanQuery(text) }
        function select(id: string, title: string): void {
            // Goes to the shared service so it works without a panel and every
            // bar instance follows along.
            if (root.service) root.service.selectPlace(id, title)
        }
        function status(): string {
            var s = root.service
            var loaded = panelLoader.item !== null
            var pl = s && s.places ? s.places.length : -1
            var ch = s && s.channels ? s.channels.length : -1
            var fch = s && s.filteredChannels ? s.filteredChannels.length : -1
            var fpl = s && s.filtered ? s.filtered.length : -1
            var md = s ? (s.mode || "") : ""
            return "{\"ok\":true,\"playing\":" + (s ? s.playing : false)
                 + ",\"paused\":" + (s ? s.paused : false)
                 + ",\"hasStation\":" + (s ? s.hasStation : false)
                 + ",\"nowPlaying\":" + JSON.stringify(s ? (s.nowPlaying || "") : "")
                 + ",\"error\":" + JSON.stringify(s ? (s.lastError || "") : "")
                 + ",\"panelLoaded\":" + loaded
                 + ",\"panelOpen\":" + (loaded && panelLoader.item.opened === true)
                 + ",\"mode\":" + JSON.stringify(md)
                 + ",\"city\":" + JSON.stringify(s ? (s.selectedTitle || "") : "")
                 + ",\"places\":" + pl
                 + ",\"channels\":" + ch
                 + ",\"matched\":" + fch
                 + ",\"matchedPlaces\":" + fpl
                 + ",\"panelMode\":" + JSON.stringify(loaded ? (panelLoader.item.mode || "") : "")
                 + ",\"panelCity\":" + JSON.stringify(loaded ? (panelLoader.item.selectedTitle || "") : "")
                 + ",\"panelQuery\":" + JSON.stringify(loaded ? (panelLoader.item.query || "") : "") + "}"
        }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // The icon is drawn, not a font glyph: a small radio (body, speaker
        // slot, dial and antenna) that reads at bar size on any font.
        text: ""
        iconComponent: Component {
            Item {
                id: radioIcon
                readonly property real s: Math.min(width, height) / 16
                readonly property color ink: root.bar && root.bar.barForeground
                    ? root.bar.barForeground : "#e8e8e8"


                // Everything is drawn in a 16x16 box that is centred inside the
                // bar slot. The slot is not square, so without this wrapper the
                // icon sits off-centre vertically.
                Item {
                    width: 16 * radioIcon.s
                    height: 16 * radioIcon.s
                    anchors.centerIn: parent

                    // antenna
                    Rectangle {
                        x: 10.2 * radioIcon.s; y: 2.3 * radioIcon.s
                        width: 1.2 * radioIcon.s; height: 4.4 * radioIcon.s
                        radius: width / 2
                        color: radioIcon.ink
                        transform: Rotation {
                            origin.x: 0.6 * radioIcon.s
                            origin.y: 4.4 * radioIcon.s
                            angle: 26
                        }
                    }
                    // antenna tip
                    Rectangle {
                        x: 12.5 * radioIcon.s; y: 1.2 * radioIcon.s
                        width: 1.9 * radioIcon.s; height: 1.9 * radioIcon.s
                        radius: width / 2
                        color: radioIcon.ink
                    }
                    // body
                    Rectangle {
                        x: 1.5 * radioIcon.s; y: 6.2 * radioIcon.s
                        width: 13 * radioIcon.s; height: 8 * radioIcon.s
                        radius: 2.2 * radioIcon.s
                        color: "transparent"
                        border.width: Math.max(1, 1.15 * radioIcon.s)
                        border.color: radioIcon.ink
                    }
                    // speaker slot
                    Rectangle {
                        x: 3.5 * radioIcon.s; y: 9.9 * radioIcon.s
                        width: 4.2 * radioIcon.s; height: 1.6 * radioIcon.s
                        radius: height / 2
                        color: radioIcon.ink
                    }
                    // dial
                    Rectangle {
                        x: 9.9 * radioIcon.s; y: 9.0 * radioIcon.s
                        width: 3.4 * radioIcon.s; height: 3.4 * radioIcon.s
                        radius: width / 2
                        color: radioIcon.ink
                    }
                }
            }
        }
        tooltipText: root.cleanForTooltip(root.stationLabel)
        active: root.playing

        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) {
                root.toggle()
            } else if (buttonCode === Qt.RightButton) {
                root.toggle()
            } else if (buttonCode === Qt.MiddleButton) {
                if (root.service) root.service.stop()
            }
        }
    }
}
