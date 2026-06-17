// modules/Audio.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: audioRoot

    property string namespace: "quickshell-audio-popup"
    property bool active: false
    
    property bool isHovered: popupHoverArea.containsMouse || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real baseLayoutHeight: 140
    property real calculatedHeight: baseLayoutHeight + (sinkModel.count > 0 ? (sinkModel.count - 1) * 54 : 0)
    property real maxCardHeight: 300

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.min(Math.round(calculatedHeight), Math.round(maxCardHeight))
    width: Math.round(maxCardWidth)
    height: implicitHeight

    // Position anchoring
    x: rootShell.barPosition === "right" 
       ? parent.width - width - 46
       : (rootShell.barPosition === "left" ? hoverOriginX + 35 : hoverOriginX) 
       
    y: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left" || rootShell.barPosition === "right") 
       ? hoverOriginY - height + 94
       : hoverOriginY

    property real currentVolume: 0.0
    property bool isMuted: false

    ListModel {
        id: sinkModel
    }

    // --- Core Polling Loop ---
    Timer {
        interval: 400
        running: audioRoot.active
        repeat: true
        onTriggered: {
            if (!mainSlider.pressed) {
                fetchVolumeProc.running = false;
                fetchVolumeProc.running = true;
            }
            fetchSinksProc.running = false;
            fetchSinksProc.running = true;
        }
    }

    // --- Core Audio Processes ---
    Process {
        id: fetchVolumeProc
        command: ["/bin/bash", "-c", "TARGET=$(wpctl status | awk '/Audio/,/Video/' | grep '*' | awk '{print $2}' | tr -d '.') && if [ -n \"$TARGET\" ]; then wpctl get-volume $TARGET; else wpctl get-volume @DEFAULT_AUDIO_SINK@; fi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let cleaned = this.text.trim();
                if (cleaned === "") return;
                
                audioRoot.isMuted = cleaned.includes("[MUTED]");
                let parts = cleaned.split(" ");
                if (parts.length >= 2) {
                    let volVal = parseFloat(parts[1]);
                    if (!isNaN(volVal) && !mainSlider.pressed) {
                        audioRoot.currentVolume = volVal;
                    }
                }
            }
        }
    }

    Process {
        id: fetchSinksProc
        command: ["/bin/bash", "-c", "wpctl status | awk '/Audio/,/Video/'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n");
                sinkModel.clear();
                let seenIds = {};
                let parsingSinks = false;

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];

                    if (line.includes("Sinks:")) {
                        parsingSinks = true;
                        continue;
                    }

                    if (parsingSinks && (line.includes("Sources:") || line.includes("Filters:") || line.includes("Streams:"))) {
                        parsingSinks = false;
                    }

                    if (parsingSinks) {
                        let match = line.match(/(\*\s*)?\s*(\d+)\.\s+(.*)/);
                        if (match) {
                            let isDef = (match[1] !== undefined && match[1].includes("*"));
                            let id = match[2].trim();
                            
                            if (seenIds[id]) continue;
                            seenIds[id] = true;

                            let rawName = match[3].trim();
                            let name = rawName.split("[")[0].trim();

                            name = name.replace(/[├─└─│]/g, "").trim();
                            if (name === "") continue;

                            sinkModel.append({
                                isDefault: isDef,
                                sinkId: id,
                                sinkName: name
                            });
                        }
                    }
                }
            }
        }
    }

    Process {
        id: setVolumeProc
        running: false
    }
    
    Process { 
        id: setDefaultSinkProc
        running: false 
        function switchSink(sinkId) {
            command = ["wpctl", "set-default", sinkId];
            running = true;
        }
    }

    onActiveChanged: {
        if (active) {
            fetchVolumeProc.running = true;
            fetchSinksProc.running = true;
        }
    }

    // --- Visual Control Panel Component Layout ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.BottomLeft
            if (rootShell.barPosition === "right") return Item.BottomRight
            if (rootShell.barPosition === "top") return Item.TopLeft
            if (rootShell.barPosition === "bottom") return Item.BottomLeft
            return Item.Center
        }

        states: [
            State {
                name: "hidden"
                when: !audioRoot.active
                PropertyChanges { target: animatedGroup; opacity: 0.0; scale: 0.0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 0.0 }
                PropertyChanges { 
                    target: animatedGroup
                    x: (rootShell.barPosition === "right") ? 40 : -40
                    y: (rootShell.barPosition === "top") ? -40 : 40 
                }
            },
            State {
                name: "shown"
                when: audioRoot.active
                PropertyChanges { target: animatedGroup; opacity: 1.0; scale: 1.0; x: 0; y: 0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 1.0 }
            }
        ]

        transitions: [
            Transition {
                from: "hidden"; to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: animatedGroup; properties: "x,y,scale"; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    NumberAnimation { target: animatedGroup; property: "opacity"; duration: 250; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 200 } 
                        NumberAnimation { target: layoutContentWrapper; property: "opacity"; duration: 200; easing.type: Easing.InQuad }
                    }
                }
            },
            Transition {
                from: "shown"; to: "hidden"
                ParallelAnimation {
                    NumberAnimation { target: layoutContentWrapper; property: "opacity"; duration: 100 }
                    NumberAnimation { target: animatedGroup; properties: "x,y,scale"; duration: 350; easing.type: Easing.InBack; easing.overshoot: 1.1 }
                    NumberAnimation { target: animatedGroup; property: "opacity"; duration: 250; easing.type: Easing.InQuad }
                }
            }
        ]

        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            color: rootShell.colorBackground
            z: 2
            
            topLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "top") ? 0 : audioRoot.radiusValue
            bottomLeftRadius: (rootShell.barPosition === "left" || rootShell.barPosition === "bottom" || rootShell.barPosition === "right") ? 0 : audioRoot.radiusValue
            topRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "top") ? 0 : audioRoot.radiusValue
            bottomRightRadius: (rootShell.barPosition === "right" || rootShell.barPosition === "bottom" || rootShell.barPosition === "left") ? 0 : audioRoot.radiusValue
        }

        // --- Extruded Wayland Shell Wing Geometry ---
        Item {
            anchors.fill: parent
            visible: audioRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"
                
                Shape {
                    x: 0; y: -audioRoot.wingSize
                    width: audioRoot.wingSize; height: audioRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: audioRoot.wingSize
                        PathLine { x: audioRoot.wingSize; y: audioRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: audioRoot.wingSize }
                        PathLine { x: 0; y: audioRoot.wingSize }
                    }
                }
                
                Shape {
                    rotation: -90
                    transformOrigin: Item.TopLeft
                    x: parent.width; y: parent.height
                    width: audioRoot.wingSize; height: audioRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: audioRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: audioRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                Shape {
                    x: parent.width - audioRoot.wingSize; y: -audioRoot.wingSize
                    width: audioRoot.wingSize; height: audioRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: audioRoot.wingSize; startY: audioRoot.wingSize
                        PathLine { x: 0; y: audioRoot.wingSize }
                        PathQuad { x: audioRoot.wingSize; y: 0; controlX: audioRoot.wingSize; controlY: audioRoot.wingSize }
                        PathLine { x: audioRoot.wingSize; y: audioRoot.wingSize }
                    }
                }

                Shape {
                    rotation: 90
                    transformOrigin: Item.TopRight
                    x: 0 - audioRoot.wingSize; y: parent.height
                    width: audioRoot.wingSize; height: audioRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: audioRoot.wingSize; startY: 0
                        PathLine { x: 0; y: 0 }
                        PathQuad { x: audioRoot.wingSize; y: audioRoot.wingSize; controlX: audioRoot.wingSize; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        MouseArea { id: popupHoverArea; anchors.fill: parent; hoverEnabled: true; z: 1 }

        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            z: 5

            HoverHandler { id: contentHoverHandler }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    
                    Text {
                        text: audioRoot.isMuted ? "volume_off" : "volume_up"
                        font.family: "Material Symbols Outlined"; font.pixelSize: 24
                        color: audioRoot.isMuted ? rootShell.colorClose : rootShell.colorAccent
                    }
                    
                    Slider {
                        id: mainSlider
                        Layout.fillWidth: true
                        from: 0.0
                        to: 1.0
                        value: audioRoot.currentVolume
                        
                        onMoved: {
                            let cmd = "TARGET=$(wpctl status | awk '/Audio/,/Video/' | grep '*' | awk '{print $2}' | tr -d '.') && " +
                                      "if [ -n \"$TARGET\" ]; then wpctl set-volume $TARGET " + mainSlider.value.toFixed(2) + "; " +
                                      "else wpctl set-volume @DEFAULT_AUDIO_SINK@ " + mainSlider.value.toFixed(2) + "; fi";
                            
                            setVolumeProc.command = ["/bin/bash", "-c", cmd];
                            setVolumeProc.running = false;
                            setVolumeProc.running = true;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(255,255,255,0.1)
                }

                ListView {
                    id: mainDeviceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: sinkModel
                    spacing: 6
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        width: mainDeviceList.width
                        height: 48

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            
                            color: model.isDefault 
                                   ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15) 
                                   : (itemMouse.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent")

                            border.width: model.isDefault ? 1 : 0
                            border.color: rootShell.colorAccent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 16

                                Text {
                                    text: model.sinkName
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.weight: model.isDefault ? Font.Bold : Font.Normal
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                Rectangle {
                                    visible: model.isDefault
                                    width: 8; height: 8; radius: 4
                                    color: rootShell.colorAccent
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    setDefaultSinkProc.switchSink(model.sinkId);
                                    fetchSinksProc.running = false;
                                    fetchSinksProc.running = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
