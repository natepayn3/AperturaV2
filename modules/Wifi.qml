import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: wifiRoot

    property string namespace: "quickshell-wifi-popup"
    property bool active: false
    
    property bool isHovered: popupHoverArea.containsMouse || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 340
    property real maxCardHeight: 440

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(maxCardHeight)
    width: Math.round(maxCardWidth)
    height: Math.round(maxCardHeight)

    x: {
        if (rootShell.barPosition === "top") return Screen.width - width - 10;
        if (rootShell.barPosition === "bottom") return Screen.width - width - 10;
        if (rootShell.barPosition === "right") return Screen.width - width - 46;
        if (rootShell.barPosition === "left") return 46; 
        return hoverOriginX; 
    }

    y: {
        switch (rootShell.barPosition) {
            case "bottom": return Screen.height - height - 46; 
            case "top":    return 46;                             
            case "left":   return Screen.height - height - 10;       
            case "right":  return Screen.height - height - 10;
            default:       return hoverOriginY;
        }
    }

    // --- State Management ---
    property bool isPowered: false
    property bool isScanning: false
    property string activeSsid: ""
    property string activeStatusText: isScanning 
        ? "Scanning networks..." 
        : (isPowered ? (activeSsid !== "" ? "Connected to " + activeSsid : "Wi-Fi is ON") : "Wi-Fi is OFF")

    ListModel { id: wifiModel }

    // --- Core Network Drivers ---
    Timer {
        id: statePollerTimer
        interval: 3000
        repeat: true
        running: wifiRoot.active
        triggeredOnStart: true
        onTriggered: {
            if (!togglePowerProc.running && !connectNetworkProc.running && !scanNetworksProc.running) {
                fetchStatusProc.running = false;
                fetchStatusProc.running = true;
            }
        }
    }

    Process {
        id: fetchStatusProc
        command: ["nmcli", "-t", "-f", "無線,WIFI", "g"] // Quick wireless hardware switch check
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let cleaned = this.text.trim();
                wifiRoot.isPowered = (cleaned.includes("有効") || cleaned.includes("enabled"));
                
                if (wifiRoot.isPowered) {
                    fetchCurrentSsidProc.running = false;
                    fetchCurrentSsidProc.running = true;
                } else {
                    wifiRoot.activeSsid = "";
                    wifiModel.clear();
                }
            }
        }
    }

    Process {
        id: fetchCurrentSsidProc
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n");
                let foundActive = "";
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].startsWith("yes:")) {
                        foundActive = lines[i].substring(4).trim();
                        break;
                    }
                }
                wifiRoot.activeSsid = foundActive;
                
                // Chain directly into updating the access point grid list
                fetchNetworksProc.running = false;
                fetchNetworksProc.running = true;
            }
        }
    }

    Process {
        id: fetchNetworksProc
        command: ["nmcli", "-t", "-f", "ACTIVE,BARS,SIGNAL,SSID", "dev", "wifi"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n");
                let tempActiveList = [];
                let tempNormalList = [];
                let seenSsids = {};

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line === "") continue;

                    let parts = line.split(":");
                    if (parts.length < 4) continue;

                    let isActive = parts[0] === "yes";
                    let bars = parts[1].trim();
                    let signal = parseInt(parts[2].trim()) || 0;
                    let ssid = parts.slice(3).join(":"); // Re-stitch SSIDs containing colons

                    if (ssid === "" || seenSsids[ssid]) continue;
                    seenIds[ssid] = true;

                    let itemData = {
                        ssid: ssid,
                        signalStrength: signal,
                        barsString: bars,
                        connected: isActive
                    };

                    if (isActive) tempActiveList.push(itemData);
                    else tempNormalList.push(itemData);
                }

                // Sort non-active access points by signal output power
                tempNormalList.sort((a, b) => b.signalStrength - a.signalStrength);

                wifiModel.clear();
                for (let j = 0; j < tempActiveList.length; j++) wifiModel.append(tempActiveList[j]);
                for (let k = 0; j < tempNormalList.length; k++) wifiModel.append(tempNormalList[k]);
            }
        }
    }

    Process {
        id: scanNetworksProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        running: false
        onRunningChanged: {
            if (!running) {
                wifiRoot.isScanning = false;
                fetchStatusProc.running = true;
            }
        }
    }

    Process {
        id: togglePowerProc
        running: false
        function setPower(turnOn) {
            command = ["nmcli", "radio", "wifi", turnOn ? "on" : "off"];
            running = true;
        }
        onRunningChanged: { if (!running) fetchStatusProc.running = true; }
    }

    Process {
        id: connectNetworkProc
        running: false
        function connectTo(ssidTarget) {
            command = ["nmcli", "dev", "wifi", "connect", ssidTarget];
            running = true;
        }
        onRunningChanged: { if (!running) fetchStatusProc.running = true; }
    }

    function triggerRescan() {
        if (!isPowered || isScanning) return;
        wifiRoot.isScanning = true;
        scanNetworksProc.running = true;
    }

    function togglePowerState() {
        togglePowerProc.setPower(!isPowered);
    }

    onActiveChanged: {
        if (active) {
            fetchStatusProc.running = true;
        }
    }

    // --- Visual Layout and Dynamic Springs ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.BottomLeft
            if (rootShell.barPosition === "right") return Item.BottomRight
            if (rootShell.barPosition === "top") return Item.TopRight
            if (rootShell.barPosition === "bottom") return Item.BottomRight
            return Item.Center
        }

        opacity: wifiRoot.active ? 1.0 : 0.0
        scale: wifiRoot.active ? 1.0 : 0.0
        x: wifiRoot.active ? 0 : (rootShell.barPosition === "right" ? 40 : -40)
        y: wifiRoot.active ? 0 : (rootShell.barPosition === "top" ? -40 : 40)
        
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
            border.width: 0

            topLeftRadius:     getCornerRadius("topLeft")
            topRightRadius:    getCornerRadius("topRight")
            bottomLeftRadius:  getCornerRadius("bottomLeft")
            bottomRightRadius: getCornerRadius("bottomRight")

            function getCornerRadius(corner) {
                let pos = rootShell.barPosition;
                let rad = wifiRoot.radiusValue;

                if (pos === "top") return (corner === "bottomLeft") ? rad : 0;
                if (pos === "bottom") return (corner === "topLeft") ? rad : 0;
                if (pos === "left") return (corner === "topRight") ? rad : 0;
                if (pos === "right") return (corner === "topLeft") ? rad : 0;
                return rad;
            }
        }

        // --- Geometric Corner Wing Anchors ---
        Item {
            anchors.fill: parent
            visible: wifiRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"
                Shape {
                    x: 0; y: -wifiRoot.wingSize; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: 0; startY: wifiRoot.wingSize
                        PathLine { x: wifiRoot.wingSize; y: wifiRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: wifiRoot.wingSize }
                        PathLine { x: 0; y: wifiRoot.wingSize }
                    }
                }
                Shape {
                    rotation: -90; transformOrigin: Item.TopLeft
                    x: parent.width; y: parent.height; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: 0; startY: 0
                        PathLine { x: wifiRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: wifiRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"
                Shape {
                    x: parent.width - wifiRoot.wingSize; y: -wifiRoot.wingSize; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: wifiRoot.wingSize; startY: wifiRoot.wingSize
                        PathLine { x: 0; y: wifiRoot.wingSize }
                        PathQuad { x: wifiRoot.wingSize; y: 0; controlX: wifiRoot.wingSize; controlY: wifiRoot.wingSize }
                        PathLine { x: wifiRoot.wingSize; y: wifiRoot.wingSize }
                    }
                }
                Shape {
                    rotation: 90; transformOrigin: Item.TopRight
                    x: 0 - wifiRoot.wingSize; y: parent.height; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: wifiRoot.wingSize; startY: 0
                        PathLine { x: 0; y: 0 }
                        PathQuad { x: wifiRoot.wingSize; y: wifiRoot.wingSize; controlX: wifiRoot.wingSize; controlY: 0 }
                        PathLine { x: wifiRoot.wingSize; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"
                Shape {
                    x: -wifiRoot.wingSize; y: 0; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: wifiRoot.wingSize; startY: 0
                        PathLine { x: wifiRoot.wingSize; y: wifiRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: wifiRoot.wingSize; controlY: 0 }
                        PathLine { x: wifiRoot.wingSize; y: 0 }
                    }
                }
                Shape {
                    x: parent.width - wifiRoot.wingSize; y: parent.height; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: wifiRoot.wingSize; startY: 0
                        PathLine { x: wifiRoot.wingSize; y: wifiRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: wifiRoot.wingSize; controlY: 0 }
                        PathLine { x: wifiRoot.wingSize; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "bottom"
                Shape {
                    x: parent.width - wifiRoot.wingSize; y: -wifiRoot.wingSize; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: wifiRoot.wingSize; startY: wifiRoot.wingSize
                        PathLine { x: 0; y: wifiRoot.wingSize }
                        PathQuad { x: wifiRoot.wingSize; y: 0; controlX: wifiRoot.wingSize; controlY: wifiRoot.wingSize }
                        PathLine { x: wifiRoot.wingSize; y: wifiRoot.wingSize }
                    }
                }
                Shape {
                    rotation: 180; transformOrigin: Item.TopLeft
                    x: parent.width - maxCardWidth; y: parent.height; width: wifiRoot.wingSize; height: wifiRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"
                        startX: 0; startY: 0
                        PathLine { x: wifiRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: wifiRoot.wingSize; controlX: 0; controlY: 0 }
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
                anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 16; anchors.bottomMargin: 8
                spacing: 0

                ListView {
                    id: networkListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: wifiModel
                    spacing: 6
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        width: networkListView.width
                        height: 48

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: model.connected 
                                   ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15) 
                                   : (itemMouse.containsMouse ? Qt.rgba(255,255,255,0.05) : "transparent")

                            border.width: model.connected ? 1 : 0
                            border.color: rootShell.colorAccent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    text: model.ssid
                                    color: "#ffffff"
                                    font.family: rootShell.shellFont
                                    font.pixelSize: 13
                                    font.weight: model.connected ? Font.Bold : Font.Normal
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.connected ? "wifi_connected" : (model.signalStrength > 75 ? "signal_wifi_4_bar" : (model.signalStrength > 45 ? "network_wifi" : "signal_wifi_bad"))
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 18
                                    color: model.connected ? rootShell.colorAccent : rootShell.colorSubtext
                                }
                            }

                            MouseArea {
                                id: itemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !model.connected && !connectNetworkProc.running
                                onClicked: connectNetworkProc.connectTo(model.ssid)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(255,255,255,0.1)
                    Layout.topMargin: 8; Layout.bottomMargin: 8
                }

                // --- Footer Toolbar Controls ---
                Item {
                    Layout.fillWidth: true; Layout.preferredHeight: 48

                    RowLayout {
                        anchors.fill: parent
                        spacing: 12

                        Rectangle {
                            width: 32; height: 32; radius: 6
                            color: footerScanMouse.containsMouse ? Qt.rgba(255,255,255,0.1) : "transparent"
                            
                            Text {
                                anchors.centerIn: parent
                                text: "refresh"
                                font.family: "Material Symbols Outlined"; font.pixelSize: 22
                                color: wifiRoot.isScanning ? rootShell.colorAccent : "#ffffff"
                            }
                            
                            MouseArea {
                                id: footerScanMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: wifiRoot.isPowered && !wifiRoot.isScanning
                                onClicked: wifiRoot.triggerRescan()
                            }
                        }

                        Text {
                            text: wifiRoot.activeStatusText
                            font.family: rootShell.shellFont; font.pixelSize: 13;
                            color: "#ffffff"; opacity: 0.8
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Switch {
                            id: powerSwitch
                            checked: wifiRoot.isPowered
                            implicitWidth: 42; implicitHeight: 24
                            Layout.alignment: Qt.AlignVCenter
                            onClicked: wifiRoot.togglePowerState()
                            
                            indicator: Rectangle {
                                width: powerSwitch.implicitWidth; height: powerSwitch.implicitHeight; radius: 12
                                color: powerSwitch.checked ? rootShell.colorAccent : "transparent"
                                border.color: powerSwitch.checked ? rootShell.colorAccent : rootShell.colorBorder
                                border.width: 2

                                Rectangle {
                                    x: powerSwitch.checked ? parent.width - width - 4 : 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14; height: 14; radius: 7
                                    color: powerSwitch.checked ? rootShell.colorBackground : rootShell.colorSubtext
                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
