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

    // --- State Management & Dynamic Height ---
    property bool isPowered: false
    property bool isScanning: false
    property string activeSsid: ""
    property string activeStatusText: isScanning 
        ? "Scanning networks..." 
        : (isPowered ? (activeSsid !== "" ? "Connected to " + activeSsid : "Wi-Fi is ON") : "Wi-Fi is OFF")

    property string expandedSsid: ""
    property var knownNetworks: ({}) 
    
    property real baseLayoutHeight: 90
    property real calculatedHeight: baseLayoutHeight + (wifiModel.count * 48) + (Math.max(0, wifiModel.count - 1) * 6) + (expandedSsid !== "" ? 48 : 0)

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.min(Math.round(calculatedHeight), Math.round(maxCardHeight))
    width: Math.round(maxCardWidth)
    height: implicitHeight
    
    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

    x: {
        let targetWidth = Quickshell.screen ? Quickshell.screen.width : Screen.width;
        if (rootShell.barPosition === "top") return targetWidth - width - 10;
        if (rootShell.barPosition === "bottom") return targetWidth - width - 10;
        if (rootShell.barPosition === "right") return targetWidth - width - 46;
        if (rootShell.barPosition === "left") return 46; 
        return hoverOriginX; 
    }

    y: {
        let targetHeight = Quickshell.screen ? Quickshell.screen.height : Screen.height;
        switch (rootShell.barPosition) {
            case "bottom": return targetHeight - height - 46; 
            case "top":    return 46;                             
            case "left":   return targetHeight - height - 10;       
            case "right":  return targetHeight - height - 10;
            default:       return hoverOriginY;
        }
    }

    ListModel { id: wifiModel }

    // --- Core Network Drivers ---
    
    Timer {
        id: hardwareScanDelay
        interval: 4000 
        onTriggered: {
            wifiRoot.isScanning = false;
            fetchStatusProc.running = true;
        }
    }

    Timer {
        id: statePollerTimer
        interval: 3000
        repeat: true
        running: wifiRoot.active
        triggeredOnStart: true
        onTriggered: {
            // Freeze the background updates if the user is typing/interacting with an expanded row
            if (!togglePowerProc.running && !connectNetworkProc.running && !wifiRoot.isScanning && !disconnectProc.running && wifiRoot.expandedSsid === "") {
                fetchStatusProc.running = false;
                fetchStatusProc.running = true;
            }
        }
    }

    Process {
        id: fetchStatusProc
        command: ["nmcli", "-t", "-f", "WIFI", "g"] 
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let cleaned = this.text.trim();
                wifiRoot.isPowered = (cleaned.includes("enabled") || cleaned.includes("有効"));
                
                if (wifiRoot.isPowered) {
                    fetchKnownProc.running = false;
                    fetchKnownProc.running = true;
                } else {
                    wifiRoot.activeSsid = "";
                    wifiRoot.expandedSsid = "";
                    wifiRoot.knownNetworks = {};
                    wifiModel.clear();
                }
            }
        }
    }

    Process {
        id: fetchKnownProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                let dict = {};
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].trim() === "") continue;
                    let parts = lines[i].split(":");
                    if (parts.length >= 2) {
                        // Added strict trimming to ensure precise SSID matching
                        let type = parts.pop().trim();
                        let name = parts.join(":").trim();
                        if (type === "802-11-wireless") dict[name] = true;
                    }
                }
                wifiRoot.knownNetworks = dict;
                
                fetchCurrentSsidProc.running = false;
                fetchCurrentSsidProc.running = true;
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
                    let ssid = parts.slice(3).join(":"); 

                    if (ssid === "" || seenSsids[ssid]) continue;
                    seenSsids[ssid] = true;

                    let itemData = {
                        ssid: ssid,
                        signalStrength: signal,
                        barsString: bars,
                        connected: isActive
                    };

                    if (isActive) tempActiveList.push(itemData);
                    else tempNormalList.push(itemData);
                }

                tempNormalList.sort((a, b) => b.signalStrength - a.signalStrength);
                let allNewItems = tempActiveList.concat(tempNormalList);

                for (let j = 0; j < allNewItems.length; j++) {
                    let newItem = allNewItems[j];
                    let foundIndex = -1;

                    for (let m = 0; m < wifiModel.count; m++) {
                        if (wifiModel.get(m).ssid === newItem.ssid) {
                            foundIndex = m;
                            break;
                        }
                    }

                    if (foundIndex !== -1) {
                        let existing = wifiModel.get(foundIndex);
                        if (existing.signalStrength !== newItem.signalStrength) wifiModel.setProperty(foundIndex, "signalStrength", newItem.signalStrength);
                        if (existing.connected !== newItem.connected) wifiModel.setProperty(foundIndex, "connected", newItem.connected);
                        
                        if (foundIndex !== j) wifiModel.move(foundIndex, j, 1);
                    } else {
                        wifiModel.insert(j, newItem);
                    }
                }
                
                while (wifiModel.count > allNewItems.length) {
                    wifiModel.remove(wifiModel.count - 1, 1);
                }
            }
        }
    }

    Process {
        id: scanNetworksProc
        command: ["nmcli", "dev", "wifi", "rescan"]
        running: false
        onRunningChanged: {
            if (!running && wifiRoot.isScanning) {
                hardwareScanDelay.restart();
            }
        }
    }

    Process {
        id: togglePowerProc
        running: false
        function setPower(turnOn) {
            command = ["nmcli", "radio", "wifi", turnOn ? "on" : "off"];
            running = false; 
            running = true;
        }
        onRunningChanged: { if (!running) fetchStatusProc.running = true; }
    }

    Process {
        id: connectNetworkProc
        running: false
        function connectTo(ssidTarget, password, isKnown) {
            running = false; 
            
            if (isKnown) {
                command = ["nmcli", "connection", "up", "id", ssidTarget];
            } else if (password === "") {
                command = ["nmcli", "dev", "wifi", "connect", ssidTarget, "timeout", "15"];
            } else {
                command = ["nmcli", "dev", "wifi", "connect", ssidTarget, "password", password, "timeout", "15"];
            }
            running = true;
        }
        onRunningChanged: { if (!running) { fetchStatusProc.running = true; wifiRoot.expandedSsid = ""; } }
    }

    Process {
        id: disconnectProc
        running: false
        function disconnect(ssidTarget) {
            command = ["nmcli", "connection", "down", "id", ssidTarget];
            running = false;
            running = true;
        }
        onRunningChanged: { if (!running) { fetchStatusProc.running = true; wifiRoot.expandedSsid = ""; } }
    }

    Process {
        id: forgetProc
        running: false
        function forget(ssidTarget) {
            command = ["nmcli", "connection", "delete", "id", ssidTarget];
            running = false;
            running = true;
        }
        onRunningChanged: { if (!running) { fetchStatusProc.running = true; wifiRoot.expandedSsid = ""; } }
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
        if (active) fetchStatusProc.running = true;
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

        MouseArea { 
            id: popupHoverArea
            anchors.fill: parent
            hoverEnabled: true
            z: 1 
            onPressed: (mouse) => mouse.accepted = true 
        }

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
                        property bool isExpanded: wifiRoot.expandedSsid === model.ssid
                        property bool isKnown: wifiRoot.knownNetworks[model.ssid] === true
                        
                        width: networkListView.width
                        height: isExpanded ? 96 : 48
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            clip: true
                            
                            color: model.connected 
                                   ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15) 
                                   : (itemMouse.containsMouse || isExpanded ? Qt.rgba(255,255,255,0.05) : "transparent")

                            border.width: model.connected ? 1 : 0
                            border.color: rootShell.colorAccent

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Top Row: Standard Network Info
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48

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
                                            text: model.connected 
                                                ? "signal_wifi_4_bar" 
                                                : (model.signalStrength > 75 ? "network_wifi" : (model.signalStrength > 45 ? "network_wifi_2_bar" : (model.signalStrength > 20 ? "network_wifi_1_bar" : "signal_wifi_off")))
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
                                        onClicked: {
                                            if (wifiRoot.expandedSsid === model.ssid) wifiRoot.expandedSsid = "";
                                            else wifiRoot.expandedSsid = model.ssid;
                                        }
                                    }
                                }

                                // Bottom Row: Interactive Controls (Expanded State)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    visible: isExpanded
                                    opacity: isExpanded ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.bottomMargin: 8
                                        spacing: 8

                                        // -> Connected Controls
                                        Rectangle {
                                            visible: model.connected
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            radius: 6; color: Qt.rgba(255, 255, 255, 0.1)
                                            Text { anchors.centerIn: parent; text: "Disconnect"; color: "#ffffff"; font.family: rootShell.shellFont; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: disconnectProc.disconnect(model.ssid) }
                                        }
                                        
                                        Rectangle {
                                            visible: model.connected
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            radius: 6; color: Qt.rgba(rootShell.colorClose.r, rootShell.colorClose.g, rootShell.colorClose.b, 0.2)
                                            Text { anchors.centerIn: parent; text: "Forget"; color: rootShell.colorClose; font.family: rootShell.shellFont; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: forgetProc.forget(model.ssid) }
                                        }

                                        // -> Disconnected Controls (Known Network - No Password Input)
                                        Rectangle {
                                            visible: !model.connected && isKnown
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            radius: 6; color: Qt.rgba(255, 255, 255, 0.1)
                                            Text { anchors.centerIn: parent; text: "Connect"; color: "#ffffff"; font.family: rootShell.shellFont; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: connectNetworkProc.connectTo(model.ssid, "", true) }
                                        }
                                        
                                        Rectangle {
                                            visible: !model.connected && isKnown
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            radius: 6; color: Qt.rgba(rootShell.colorClose.r, rootShell.colorClose.g, rootShell.colorClose.b, 0.2)
                                            Text { anchors.centerIn: parent; text: "Forget"; color: rootShell.colorClose; font.family: rootShell.shellFont; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: forgetProc.forget(model.ssid) }
                                        }

                                        // -> Disconnected Controls (Unknown Network - Password Input)
                                        Rectangle {
                                            visible: !model.connected && !isKnown
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            radius: 6; color: Qt.rgba(0,0,0, 0.3)
                                            border.width: 1; border.color: Qt.rgba(255,255,255,0.1)
                                            
                                            TextInput {
                                                id: passInput
                                                anchors.fill: parent
                                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                                verticalAlignment: TextInput.AlignVCenter
                                                color: "#ffffff"; font.pixelSize: 12; font.family: rootShell.shellFont
                                                echoMode: TextInput.Password
                                                
                                                onAccepted: connectNetworkProc.connectTo(model.ssid, passInput.text, false)
                                                
                                                Text {
                                                    text: "Password"
                                                    color: Qt.rgba(255,255,255,0.4)
                                                    font.family: rootShell.shellFont; font.pixelSize: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: passInput.text === "" && !passInput.activeFocus
                                                }
                                            }
                                        }
                                        
                                        Rectangle {
                                            visible: !model.connected && !isKnown
                                            Layout.preferredWidth: 80; Layout.fillHeight: true
                                            radius: 6; color: rootShell.colorAccent
                                            Text { anchors.centerIn: parent; text: "Connect"; color: rootShell.colorBackground; font.family: rootShell.shellFont; font.pixelSize: 12; font.weight: Font.Bold }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: connectNetworkProc.connectTo(model.ssid, passInput.text, false) }
                                        }
                                    }
                                }
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
