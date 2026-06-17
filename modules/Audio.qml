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

    x: rootShell.barPosition === "right" 
       ? parent.width - width - 46
       : (rootShell.barPosition === "left" ? hoverOriginX + 35 : hoverOriginX) 
       
    y: (rootShell.barPosition === "bottom" || rootShell.barPosition === "left" || rootShell.barPosition === "right") 
       ? hoverOriginY - height + 94
       : hoverOriginY

    property real currentVolume: 0.0
    property bool isMuted: false
    property real lastSeenVolume: -1
    property string targetSinkId: "@DEFAULT_AUDIO_SINK@"

    // NEW: Decoupled State Tracking
    property bool osdActive: false
    property bool showUI: active || osdActive

    ListModel { id: sinkModel }

    // --- Active State Timers ---
    Timer {
        id: osdHideTimer
        interval: 2500
        onTriggered: {
            if (!audioRoot.isHovered) audioRoot.osdActive = false;
        }
    }

    Timer {
        interval: 400
        running: true 
        repeat: true
        onTriggered: {
            if (!mainSlider.pressed) {
                fetchVolumeProc.running = false;
                fetchVolumeProc.running = true;
            }
        }
    }

    // Trigger graph rebuilds whenever the UI is visible (Menu OR OSD)
    onShowUIChanged: {
        if (showUI) {
            fetchSinksProc.running = false;
            fetchSinksProc.running = true;
        }
    }

    // --- Core Audio Processes ---
    Process {
        id: fetchVolumeProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let cleaned = this.text.trim();
                if (!cleaned.startsWith("Volume:")) return;
                
                audioRoot.isMuted = cleaned.includes("[MUTED]");
                let parts = cleaned.split(" ");
                
                if (parts.length >= 2) {
                    let volVal = parseFloat(parts[1]);
                    if (!isNaN(volVal) && !mainSlider.pressed) {
                        
                        // Safely updates the bound property
                        if (Math.abs(audioRoot.currentVolume - volVal) > 0.001) {
                            audioRoot.currentVolume = volVal; 
                            
                            // Trigger OSD ONLY on background changes, and ONLY if menu is closed
                            if (lastSeenVolume !== -1 && !audioRoot.active) {
                                audioRoot.osdActive = true;
                                osdHideTimer.restart();
                            }
                        }
                        lastSeenVolume = volVal;
                    }
                }
            }
        }
    }

    Process {
        id: setVolumeProc
        running: false
        
        function setVol(volVal) {
            command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", volVal.toFixed(2)];
            running = false; // Guarantees previous queue is cleared
            running = true;
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

                    if (line.includes("Sinks:")) { parsingSinks = true; continue; }
                    if (parsingSinks && (line.includes("Sources:") || line.includes("Filters:") || line.includes("Streams:"))) { parsingSinks = false; }

                    if (parsingSinks) {
                        let match = line.match(/(\*\s*)?\s*(\d+)\.\s+(.*)/);
                        if (match) {
                            let isDef = (match[1] !== undefined && match[1].includes("*"));
                            let id = match[2].trim();
                            
                            if (seenIds[id]) continue;
                            seenIds[id] = true;

                            let rawName = match[3].trim();
                            let name = rawName.split("[")[0].trim().replace(/[├─└─│]/g, "");
                            if (name === "") continue;

                            sinkModel.append({ isDefault: isDef, sinkId: id, sinkName: name });
                        }
                    }
                }
            }
        }
    }
    
    Process { 
        id: setDefaultSinkProc
        running: false 
        function switchSink(sinkId) {
            command = ["wpctl", "set-default", sinkId];
            running = true;
            // Force an immediate refresh of the UI list after switching
            fetchSinksProc.running = false;
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

        // --- Unbreakable Declarative Animations ---
        opacity: audioRoot.showUI ? 1.0 : 0.0
        scale: audioRoot.showUI ? 1.0 : 0.0
        x: audioRoot.showUI ? 0 : (rootShell.barPosition === "right" ? 40 : -40)
        y: audioRoot.showUI ? 0 : (rootShell.barPosition === "top" ? -40 : 40)
        
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

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
                            audioRoot.currentVolume = value;
                            setVolumeProc.setVol(value);
                            
                            // Only extend the timer if we are in OSD mode
                            if (audioRoot.osdActive) {
                                osdHideTimer.restart();
                            }
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
                                onClicked: setDefaultSinkProc.switchSink(model.sinkId)
                            }
                        }
                    }
                }
            }
        }
    }
}
