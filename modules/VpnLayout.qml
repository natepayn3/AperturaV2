import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: vpnLayoutRoot

    property var shellTarget: null
    property var settingsWindow: null

    // --- State Machine Synchronizers ---
    property bool hasVpnProfile: false
    property string detectedConnection: ""
    property string fallbackConnection: "" // <-- Stores the target profile name when disconnected
    property bool isVpnActive: false

    // Passive polling pipeline handles synchronization
    Timer {
        id: syncVpnTimer
        interval: 3000
        running: settingsWindow && settingsWindow.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            vpnScanner.running = false;
            vpnScanner.running = true;
            vpnProfileCheck.running = false;
            vpnProfileCheck.running = true;
        }
    }

    // Identifies if any valid wireguard, vpn, or tun endpoints exist
    Process {
        id: vpnProfileCheck
        // FIX: Request both connection types AND names from nmcli
        command: ["nmcli", "-g", "TYPE,NAME", "connection", "show"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanText = text.trim();
                if (!cleanText) {
                    vpnLayoutRoot.hasVpnProfile = false;
                    return;
                }
                
                let lines = cleanText.split("\n");
                let foundProfile = false;
                let staticFallback = "";

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    let parts = line.split(":");
                    if (parts.length >= 2) {
                        let type = parts[0];
                        let name = parts[1];
                        
                        if (type === "vpn" || type === "wireguard" || type === "tun") {
                            foundProfile = true;
                            // Cache the first valid connection profile name we find as a baseline fallback
                            if (staticFallback === "") {
                                staticFallback = name;
                            }
                        }
                    }
                }
                vpnLayoutRoot.hasVpnProfile = foundProfile;
                vpnLayoutRoot.fallbackConnection = staticFallback;
            }
        }
    }

    // Scrapes operational session network maps for activated secure nodes
    Process {
        id: vpnScanner
        command: ["nmcli", "-g", "TYPE,NAME,STATE", "connection", "show", "--active"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                try {
                    let cleanText = text.trim();
                    if (!cleanText) {
                        vpnLayoutRoot.detectedConnection = "";
                        vpnLayoutRoot.isVpnActive = false;
                        return;
                    }

                    let lines = cleanText.split("\n");
                    let foundActive = false;
                    let parsedConnection = "";

                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i].trim();
                        if (line.startsWith("wireguard:") || line.startsWith("vpn:") || line.startsWith("tun:")) {
                            let parts = line.split(":");
                            if (parts.length >= 3 && parts[2] === "activated") {
                                parsedConnection = parts[1];
                                foundActive = true;
                                break;
                            }
                        }
                    }

                    if (foundActive) {
                        vpnLayoutRoot.detectedConnection = parsedConnection;
                        vpnLayoutRoot.isVpnActive = true;
                    } else {
                        vpnLayoutRoot.detectedConnection = "";
                        vpnLayoutRoot.isVpnActive = false;
                    }
                } catch(e) {
                    vpnLayoutRoot.detectedConnection = "";
                    vpnLayoutRoot.isVpnActive = false;
                }
            }
        }
    }

    // Native Toggler: Directly leverages nmcli connection flags inline
    Process {
        id: vpnToggler
        running: false
        onExited: {
            if (vpnLayoutRoot.isVpnActive) {
                notifyProc.command = ["notify-send", "-a", "VPN Manager", "-i", "network-vpn-disabled", "VPN Disconnected", "The secure tunnel connection has been closed."];
            } else {
                notifyProc.command = ["notify-send", "-a", "VPN Manager", "-i", "network-vpn", "VPN Connected", "Secure tunnel established successfully."];
            }
            notifyProc.running = true;

            vpnScanner.running = false;
            vpnScanner.running = true;
        }
    }

    Process {
        id: notifyProc
        running: false
    }

    function executeVpnToggle() {
        if (vpnLayoutRoot.isVpnActive) {
            // Active: Drop down the running connection via its active ID
            vpnToggler.command = ["nmcli", "connection", "down", "id", vpnLayoutRoot.detectedConnection];
        } else {
            // Disconnected: Bring up the profiled fallback connection name natively
            vpnToggler.command = ["nmcli", "connection", "up", "id", vpnLayoutRoot.fallbackConnection];
        }
        vpnToggler.running = true;
    }

    // --- Module User Interface View ---
    ColumnLayout {
        anchors.fill: parent
        spacing: 20

        Text {
            text: "Available VPN profiles:"
            font.family: settingsWindow.selectedFont
            font.pixelSize: 16
            font.bold: true
            color: shellTarget ? shellTarget.colorText : "#cdd6f4"
        }

        Rectangle {
            id: vpnCardBody
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            color: Qt.rgba(0, 0, 0, 0.15)
            radius: 12
            border.color: shellTarget ? shellTarget.colorBorder : "#313244"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 24
                    color: vpnLayoutRoot.isVpnActive ? Qt.rgba(137/255, 180/255, 250/255, 0.15) : Qt.rgba(1, 1, 1, 0.05)

                    Text {
                        anchors.centerIn: parent
                        text: vpnLayoutRoot.isVpnActive ? "vpn_key" : "vpn_key_off"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 24
                        color: vpnLayoutRoot.isVpnActive ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorSubtext : "#a6adc8")
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Layout.fillWidth: true

                    Text {
                        text: !vpnLayoutRoot.hasVpnProfile 
                            ? "No Configured Connections" 
                            : (vpnLayoutRoot.isVpnActive ? vpnLayoutRoot.detectedConnection : vpnLayoutRoot.fallbackConnection)
                        font.family: settingsWindow.selectedFont
                        font.bold: true
                        font.pixelSize: 14
                        color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                    }

                    Text {
                        text: !vpnLayoutRoot.hasVpnProfile 
                            ? "Create a tunnel endpoint via NetworkManager connection settings." 
                            : (vpnLayoutRoot.isVpnActive ? "Connected" : "Disconnected")
                        font.family: settingsWindow.selectedFont
                        font.pixelSize: 14
                        color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Switch {
                    id: toggleSwitch
                    checked: vpnLayoutRoot.isVpnActive
                    // FIX: Ensure it validates against fallback availability so it can toggle back on
                    enabled: vpnLayoutRoot.hasVpnProfile && (vpnLayoutRoot.detectedConnection !== "" || vpnLayoutRoot.fallbackConnection !== "")
                    onClicked: vpnLayoutRoot.executeVpnToggle()

                    background: Rectangle {
                        implicitWidth: 48
                        implicitHeight: 24
                        radius: 12
                        color: toggleSwitch.checked 
                            ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                            : (shellTarget ? shellTarget.colorBorder : "#313244")
                        
                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            color: "#11111b"
                            anchors.verticalCenter: parent.verticalCenter
                            x: toggleSwitch.checked ? 26 : 4
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                        }
                    }
                    
                    indicator: Item {}
                    HoverHandler { cursorShape: toggleSwitch.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
            }
        }
        
        Item { Layout.fillHeight: true }
    }
}
