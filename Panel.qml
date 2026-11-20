import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
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

    // All browsing and playback state lives in the shared Service, so every
    // panel on every monitor shows the same city, station list and search text.
    property var service: null

    readonly property var places: service ? service.places : []
    readonly property var filtered: service ? service.filtered : []
    readonly property var channels: service ? service.channels : []
    readonly property var filteredChannels: service ? service.filteredChannels : []
    readonly property string mode: service ? (service.mode || "places") : "places"
    readonly property string query: service ? (service.query || "") : ""
    readonly property string chanQuery: service ? (service.chanQuery || "") : ""
    readonly property string selectedTitle: service ? (service.selectedTitle || "") : ""
    readonly property string statusText: service ? (service.statusText || "") : ""

    readonly property bool playing: service ? service.playing === true : false
    readonly property bool paused: service ? service.paused === true : false
    readonly property string nowPlaying: service ? (service.nowPlaying || "") : ""
    readonly property bool hasStation: service ? service.hasStation === true : false

    function setQuery(value) { if (service) service.setQuery(value) }
    function setChanQuery(value) { if (service) service.setChanQuery(value) }
    function selectPlace(id, title) { if (service) service.selectPlace(id, title) }
    function backToPlaces() { if (service) service.backToPlaces() }
    function playChannel(id, title) { if (service) service.playStation(id, title) }
    function stopPlayback() { if (service) service.stop() }
    function togglePlay() { if (service) service.togglePlay() }

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
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.statusText
                    textFormat: Text.PlainText
                    color: "#9aa0a6"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                text: root.query
                onTextEdited: root.setQuery(text)
            }

            // back row (channels mode)
            RowLayout {
                Layout.fillWidth: true
                visible: root.mode === "channels"
                Text {
                    text: "‹ " + qsTr("Back")
                    color: "#5aa9ff"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
                    textFormat: Text.PlainText
                    color: "#9aa0a6"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
            }

            // station search (channels mode)
            TextField {
                id: stationsSearchField
                Layout.fillWidth: true
                visible: root.mode === "channels"
                placeholderText: qsTr("Search stations…")
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                text: root.chanQuery
                onTextEdited: root.setChanQuery(text)
            }

            Text {
                visible: root.mode === "channels" && root.chanQuery !== ""
                         && root.filteredChannels.length === 0
                Layout.fillWidth: true
                text: qsTr("No stations match \"%1\"").arg(root.chanQuery)
                textFormat: Text.PlainText
                color: "#9aa0a6"
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
                            textFormat: Text.PlainText
                            color: root.barForeground
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: modelData.country || ""
                            textFormat: Text.PlainText
                            color: "#9aa0a6"
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
                        textFormat: Text.PlainText
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
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

            // footer: now-playing text + transport controls
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(12)

                Text {
                    textFormat: Text.PlainText
                    text: root.playing
                        ? qsTr("Playing: %1").arg(root.nowPlaying)
                        : (root.hasStation
                            ? qsTr("Paused: %1").arg(root.nowPlaying)
                            : qsTr("Nothing playing"))
                    color: root.playing ? "#5aa9ff" : "#9aa0a6"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Play / pause is drawn as vector shapes, not a font glyph:
                // private-use icon codepoints fall back to unrelated symbols
                // when the resolved font differs, which made the button wrong.
                Item {
                    id: transport
                    visible: root.hasStation
                    implicitWidth: Style.space(18)
                    implicitHeight: Style.space(16)
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight

                    // Play triangle (shown while paused).
                    Shape {
                        anchors.fill: parent
                        visible: !root.playing
                        ShapePath {
                            strokeWidth: 0
                            strokeColor: "transparent"
                            fillColor: root.barForeground
                            startX: Style.space(5)
                            startY: Style.space(3)
                            PathLine { x: Style.space(13); y: Style.space(8) }
                            PathLine { x: Style.space(5); y: Style.space(13) }
                            PathLine { x: Style.space(5); y: Style.space(3) }
                        }
                    }

                    // Pause bars (shown while playing).
                    Row {
                        anchors.centerIn: parent
                        spacing: Style.space(4)
                        visible: root.playing
                        Rectangle { width: Style.space(4); height: Style.space(10); radius: Style.space(1); color: root.barForeground }
                        Rectangle { width: Style.space(4); height: Style.space(10); radius: Style.space(1); color: root.barForeground }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(6)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePlay()
                    }
                }

                Text {
                    text: qsTr("Stop")
                    visible: root.hasStation
                    color: "#ff6b6b"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.stopPlayback()
                    }
                }
            }
        }
    }
}
