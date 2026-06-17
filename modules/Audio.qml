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
    property bool forceShow: false

    ListModel { id: sinkModel }

    // --- Active State Timers ---
    
    // Dedicated timer for the bottom-center hardware overlay
    Timer {
        id: hardwareOsdTimer
        interval: 1000 
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

    // Trigger graph rebuilds whenever the interactive menu is opened
    onActiveChanged: {
        if (active) {
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
                
                let isNowMuted = cleaned.includes("[MUTED]");
                let parts = cleaned.split(" ");
                let volVal = parseFloat(parts[1]);
                
                // ADDED: Simple lock to ignore system state for 300ms after a manual click
                if (!isNaN(volVal) && !mainSlider.pressed && !toggleMuteProc.running) {
                    
                    if (Math.abs(audioRoot.currentVolume - volVal) > 0.001 || audioRoot.isMuted !== isNowMuted) {
                        audioRoot.currentVolume = volVal;
                        audioRoot.isMuted = isNowMuted;
                        
                        if (lastSeenVolume !== -1 && !mainSlider.pressed && !audioRoot.active) {
                            hardwareOsdTimer.restart();
                        }
                    }
                    lastSeenVolume = volVal;
                }
            }
        }
    }

    Process {
        id: setVolumeProc
        running: false
        
        // Use a variable to track if a command is pending
        property real pendingVolume: 0.0

        function setVol(volVal) {
            pendingVolume = volVal;
            
            // 1. If currently muted, we must toggle it first
            if (audioRoot.isMuted) {
                // Execute just the mute toggle
                Quickshell.exec(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
                
                // Update local state immediately
                audioRoot.isMuted = false;
                
                // Wait a tiny bit for the pipewire server to update the node's mute flag
                Qt.callLater(() => {
                    executeVolumeSet(pendingVolume);
                });
            } else {
                executeVolumeSet(volVal);
            }
        }

        function executeVolumeSet(volVal) {
            command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", volVal.toFixed(2)];
            running = false; 
            running = true;
        }
    }

    Process {
        id: toggleMuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        running: false
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
            // 1. Optimistic UI Update: Immediately toggle the local model
            for (let i = 0; i < sinkModel.count; i++) {
                let item = sinkModel.get(i);
                item.isDefault = (item.sinkId === sinkId);
                sinkModel.set(i, item);
            }
            
            // 2. Execute the backend change
            command = ["wpctl", "set-default", sinkId];
            running = true;
            
            // 3. Trigger a background refresh to stay in sync with the real system
            Qt.callLater(() => {
                fetchSinksProc.running = false;
                fetchSinksProc.running = true;
            });
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
        opacity: audioRoot.active ? 1.0 : 0.0
        scale: audioRoot.active ? 1.0 : 0.0
        x: audioRoot.active ? 0 : (rootShell.barPosition === "right" ? 40 : -40)
        y: audioRoot.active ? 0 : (rootShell.barPosition === "top" ? -40 : 40)
        
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
                    
                    Rectangle {
                        width: 32
                        height: 32
                        radius: 8
                        Layout.alignment: Qt.AlignVCenter
                        color: muteMouseArea.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: audioRoot.isMuted ? "volume_off" : (audioRoot.currentVolume < 0.33 ? "volume_mute" : (audioRoot.currentVolume < 0.50 ? "volume_down" : "volume_up"))
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24
                            color: audioRoot.isMuted ? rootShell.colorClose : rootShell.colorAccent
                        }

                        MouseArea {
                            id: muteMouseArea
                            anchors.fill: parent
                            hoverEnabled: true 
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                toggleMuteProc.running = false;
                                toggleMuteProc.running = true;
                                audioRoot.isMuted = !audioRoot.isMuted; 
                                
                                // CallLater ensures the timer fires after the UI state settles
                                Qt.callLater(() => {
                                    hardwareOsdTimer.stop();
                                    hardwareOsdTimer.restart();
                                });
                            }
                        }
                    }
                    
                    Slider {
                        id: mainSlider
                        Layout.fillWidth: true
                        from: 0.0
                        to: 1.0
                        stepSize: 0.01 
                        value: audioRoot.currentVolume
                        
                        onMoved: {
                            audioRoot.currentVolume = value;
                            // Force the mute state to false locally immediately
                            if (audioRoot.isMuted) audioRoot.isMuted = false;
                            
                            setVolumeProc.setVol(value);
                        }

                        background: Rectangle {
                            x: mainSlider.leftPadding
                            y: mainSlider.topPadding + mainSlider.availableHeight / 2 - height / 2
                            implicitWidth: 200
                            implicitHeight: 4
                            width: mainSlider.availableWidth
                            height: implicitHeight
                            radius: 2
                            color: Qt.rgba(255, 255, 255, 0.1)

                            Rectangle {
                                width: mainSlider.visualPosition * parent.width
                                height: parent.height
                                color: audioRoot.isMuted ? "#666666" : rootShell.colorAccent
                                radius: 2
                            }
                        }

                        handle: Rectangle {
                            x: mainSlider.leftPadding + mainSlider.visualPosition * (mainSlider.availableWidth - width)
                            y: mainSlider.topPadding + mainSlider.availableHeight / 2 - height / 2
                            implicitWidth: 16
                            implicitHeight: 16
                            radius: 8 
                            color: mainSlider.pressed ? Qt.lighter(rootShell.colorAccent, 1.2) : (audioRoot.isMuted ? "#999999" : rootShell.colorAccent)
                        }
                    }

                    Text {
                        text: Math.round(audioRoot.currentVolume * 100) + "%"
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: audioRoot.isMuted ? "#999999" : "#ffffff"
                        Layout.alignment: Qt.AlignVCenter
                        Layout.minimumWidth: 36 
                        horizontalAlignment: Text.AlignRight
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

    // --- Floating Hardware Volume OSD ---
    PanelWindow {
        id: volumePillWindow
        WlrLayershell.namespace: audioRoot.namespace
        exclusiveZone: 0 
        implicitWidth: 260
        implicitHeight: 48
        color: "transparent"
        
        visible: true

        anchors { bottom: true }
        margins { bottom: 120 }

        Rectangle {
            id: pillBackground
            anchors.fill: parent
            
            opacity: hardwareOsdTimer.running ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

            // Refined color: Using 0.6 opacity for a "glassier" feel
            color: rootShell.colorBackground
            radius: 12

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: audioRoot.isMuted ? "volume_off" : (audioRoot.currentVolume < 0.33 ? "volume_mute" : (audioRoot.currentVolume < 0.50 ? "volume_down" : "volume_up"))
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    color: audioRoot.isMuted ? rootShell.colorClose : rootShell.colorAccent
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 4
                    radius: 2
                    color: Qt.rgba(255, 255, 255, 0.1)

                    Rectangle {
                        width: parent.width * audioRoot.currentVolume
                        height: parent.height
                        radius: 2
                        color: audioRoot.isMuted ? "#666666" : rootShell.colorAccent
                        
                        Behavior on width { NumberAnimation { duration: 75; easing.type: Easing.OutQuad } }
                    }
                }

                Text {
                    text: Math.round(audioRoot.currentVolume * 100) + "%"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: audioRoot.isMuted ? "#999999" : "#ffffff"
                    Layout.minimumWidth: 36 
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
