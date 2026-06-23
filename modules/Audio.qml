import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

Item {
    id: audioRoot

    property string namespace: "quickshell-audio-popup"
    property bool active: false
    
    property bool isHovered: animatedGroup.isHovered || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    // 📐 Scaling Factor Configuration
    property real scaleFactor: rootShell.scale || 1.0

    // 📐 Snap Functions
    // ceil for size to prevent 1px clipping, floor for origins, toFixed to kill float drift
    function snapSize(logicalValue) { 
        return Number((Math.ceil(logicalValue * scaleFactor) / scaleFactor).toFixed(4)) 
    }
    function snapOrigin(logicalValue) { 
        return Number((Math.floor(logicalValue * scaleFactor) / scaleFactor).toFixed(4)) 
    }

    property real maxCardWidth: 340
    property real baseLayoutHeight: 140
    property real calculatedHeight: baseLayoutHeight + (sinkModel.count > 0 ? (sinkModel.count - 1) * 54 : 0)
    property real maxCardHeight: 300

    implicitWidth: snapSize(maxCardWidth)
    implicitHeight: Math.min(snapSize(calculatedHeight), snapSize(maxCardHeight))
    width: implicitWidth
    height: implicitHeight

    x: {
        if (rootShell.barPosition === "top") return snapOrigin(Screen.width - width - 10);
        if (rootShell.barPosition === "bottom") return snapOrigin(Screen.width - width - 10);
        if (rootShell.barPosition === "right") return snapOrigin(Screen.width - width - 46);
        if (rootShell.barPosition === "left") return snapOrigin(46); 
        return snapOrigin(hoverOriginX); 
    }

    y: {
        switch (rootShell.barPosition) {
            case "bottom": return snapOrigin(Screen.height - height - 46);
            case "top":    return snapOrigin(46);                             
            case "left":   return snapOrigin(Screen.height - height - 10);   
            case "right":  return snapOrigin(Screen.height - height - 10);
            default:       return snapOrigin(hoverOriginY);
        }
    }

    property real currentVolume: 0.0
    property bool isMuted: false
    property real lastSeenVolume: -1
    property string targetSinkId: "@DEFAULT_AUDIO_SINK@"
    property bool forceShow: false

    ListModel { id: sinkModel }

    Timer {
        id: hardwareOsdTimer
        interval: 1000 
    }

    onActiveChanged: {
        if (active) {
            fetchSinksProc.running = false;
            fetchSinksProc.running = true;
        }
    }

    Process {
        id: audioEventStream
        command: [
            "sh", "-c",
            "pactl subscribe | grep --line-buffered \"Event 'change' on sink\" | while read -r _; do wpctl get-volume @DEFAULT_AUDIO_SINK@; done"
        ]
        running: true

        stdout: SplitParser {
            onRead: data => {
                let cleaned = data.trim();
                if (!cleaned.startsWith("Volume:")) return;

                let isNowMuted = cleaned.includes("[MUTED]");
                let parts = cleaned.split(" ");
                let volVal = parseFloat(parts[1]);
                if (!isNaN(volVal) && !mainSlider.pressed && !toggleMuteProc.running) {
                    if (Math.abs(audioRoot.currentVolume - volVal) > 0.001 || audioRoot.isMuted !== isNowMuted) {
                        audioRoot.currentVolume = volVal;
                        audioRoot.isMuted = isNowMuted;

                        if (!audioRoot.active) {
                            hardwareOsdTimer.restart();
                        }
                    }
                    lastSeenVolume = volVal;
                }
            }
        }
    }

    Process {
        id: unmuteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]
        running: false
    }

    Process {
        id: setVolumeProc
        running: false
        property real pendingVolume: 0.0

        function setVol(volVal) {
            pendingVolume = volVal;
            if (audioRoot.isMuted) {
                unmuteProc.running = true;
                audioRoot.isMuted = false;
                Qt.callLater(() => { executeVolumeSet(pendingVolume); });
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
        command: ["wpctl", "status"]
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
            for (let i = 0; i < sinkModel.count; i++) {
                let item = sinkModel.get(i);
                item.isDefault = (item.sinkId === sinkId);
                sinkModel.set(i, item);
            }
            
            command = ["wpctl", "set-default", sinkId];
            running = true;
            
            Qt.callLater(() => {
                bootstrapVolume.running = false;
                bootstrapVolume.running = true;
            });
        }
    }

    Process {
        id: bootstrapVolume
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let cleaned = this.text.trim();
                if (!cleaned.startsWith("Volume:")) return;
                audioRoot.isMuted = cleaned.includes("[MUTED]");
                let parts = cleaned.split(" ");
                let volVal = parseFloat(parts[1]);
                if (!isNaN(volVal)) audioRoot.currentVolume = volVal;
            }
        }
    }

    Component.onCompleted: {
        fetchSinksProc.running = true;
        bootstrapVolume.running = true;
    }

    AnimatedCard {
        id: animatedGroup
        anchors.fill: parent
        
        barPosition: rootShell.barPosition
        backgroundColor: rootShell.colorBackground
        
        active: audioRoot.active
        radiusValue: audioRoot.radiusValue
        wingSize: audioRoot.wingSize
        targetWidth: audioRoot.width
        targetHeight: audioRoot.height

        Item {
            id: layoutContentWrapper
            anchors.fill: parent

            HoverHandler { id: contentHoverHandler }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: snapSize(16)
                spacing: snapSize(12)

                ListView {
                    id: mainDeviceList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: sinkModel
                    spacing: snapSize(6)
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        width: mainDeviceList.width
                        height: snapSize(48)

                        Rectangle {
                            anchors.fill: parent
                            radius: snapSize(8)
                            
                            color: model.isDefault 
                                   ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15) 
                                   : (itemMouse.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent")

                            border.width: model.isDefault ? snapSize(1) : 0
                            border.color: rootShell.colorAccent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: snapSize(12)
                                anchors.rightMargin: snapSize(16)

                                Text {
                                    text: model.sinkName
                                    color: "#ffffff"
                                    font.family: rootShell.shellFont
                                    font.pixelSize: snapSize(13)
                                    font.weight: model.isDefault ? Font.Bold : Font.Normal
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                Rectangle {
                                    visible: model.isDefault
                                    width: snapSize(8)
                                    height: snapSize(8)
                                    radius: snapSize(4)
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

                Rectangle {
                    Layout.fillWidth: true
                    height: snapSize(1)
                    color: Qt.rgba(255,255,255,0.1)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: snapSize(16)
                    
                    Rectangle {
                        width: snapSize(32)
                        height: snapSize(32)
                        radius: snapSize(8)
                        Layout.alignment: Qt.AlignVCenter
                        color: muteMouseArea.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: audioRoot.isMuted ? "volume_off" : "volume_up"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: snapSize(24)
                            color: audioRoot.isMuted ? rootShell.colorClose : rootShell.colorAccent
                        }

                        MouseArea {
                            id: muteMouseArea
                            anchors.fill: parent
                            hoverEnabled: true 
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                toggleMuteProc.running = false
                                toggleMuteProc.running = true
                                audioRoot.isMuted = !audioRoot.isMuted 
                                
                                Qt.callLater(() => {
                                    hardwareOsdTimer.stop()
                                    hardwareOsdTimer.restart()
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
                            audioRoot.currentVolume = value
                            if (audioRoot.isMuted) audioRoot.isMuted = false
                            setVolumeProc.setVol(value)
                        }

                        background: Rectangle {
                            x: mainSlider.leftPadding
                            y: mainSlider.topPadding + mainSlider.availableHeight / 2 - height / 2
                            implicitWidth: snapSize(200)
                            implicitHeight: snapSize(4)
                            width: mainSlider.availableWidth
                            height: implicitHeight
                            radius: snapSize(2)
                            color: Qt.rgba(255, 255, 255, 0.1)

                            Rectangle {
                                width: mainSlider.visualPosition * parent.width
                                height: parent.height
                                color: audioRoot.isMuted ? "#666666" : rootShell.colorAccent
                                radius: snapSize(2)
                            }
                        }

                        handle: Rectangle {
                            x: mainSlider.leftPadding + mainSlider.visualPosition * (mainSlider.availableWidth - width)
                            y: mainSlider.topPadding + mainSlider.availableHeight / 2 - height / 2
                            implicitWidth: snapSize(16)
                            implicitHeight: snapSize(16)
                            radius: snapSize(8) 
                            color: mainSlider.pressed ? Qt.lighter(rootShell.colorAccent, 1.2) : (audioRoot.isMuted ? "#999999" : rootShell.colorAccent)
                        }
                    }

                    Text {
                        text: Math.round(audioRoot.currentVolume * 100) + "%"
                        font.family: rootShell.shellFont
                        font.pixelSize: snapSize(13)
                        font.weight: Font.Bold
                        color: audioRoot.isMuted ? "#999999" : "#ffffff"
                        Layout.alignment: Qt.AlignVCenter
                        Layout.minimumWidth: snapSize(36)
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }

    PanelWindow {
        id: volumePillWindow
        WlrLayershell.namespace: audioRoot.namespace
        exclusiveZone: 0 
        implicitWidth: snapSize(260)
        implicitHeight: snapSize(48)
        color: "transparent"
        visible: hardwareOsdTimer.running

        anchors { bottom: true }
        margins { bottom: snapSize(120) }

        Rectangle {
            id: pillBackground
            anchors.fill: parent
            color: rootShell.colorBackground
            radius: snapSize(12)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: snapSize(16)
                anchors.rightMargin: snapSize(16)
                spacing: snapSize(12)

                Text {
                    text: audioRoot.isMuted ? "volume_off" : "volume_up"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: snapSize(20)
                    color: audioRoot.isMuted ? rootShell.colorClose : rootShell.colorAccent
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: snapSize(4)
                    radius: snapSize(2)
                    color: Qt.rgba(255, 255, 255, 0.1)

                    Rectangle {
                        width: parent.width * audioRoot.currentVolume
                        height: parent.height
                        radius: snapSize(2)
                        color: audioRoot.isMuted ? "#666666" : rootShell.colorAccent
                        
                        Behavior on width { NumberAnimation { duration: 75; easing.type: Easing.OutQuad } }
                    }
                }

                Text {
                    text: Math.round(audioRoot.currentVolume * 100) + "%"
                    font.family: rootShell.shellFont
                    font.pixelSize: snapSize(13)
                    font.weight: Font.Bold
                    color: audioRoot.isMuted ? "#999999" : "#ffffff"
                    Layout.minimumWidth: snapSize(36)
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
