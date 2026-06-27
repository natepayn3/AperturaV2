import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Item {
    id: vpnLayoutRoot

    property var shellTarget: null
    property var settingsWindow: null

    property color themeBorder: "transparent"
    property color themeAccent: "transparent"
    property color themeText: "transparent"
    property color themeSubtext: "transparent"

    // --- Core State Management ---
    property string activeVpnName: ""
    property string publicIpAddress: "" 
    property bool textVisible: true
    
    property bool hasImportError: false
    property bool showFileBrowser: false
    property string currentBrowserPath: "file://" + Quickshell.env("HOME")

    // Centralized Fallback Palette (Uses shellTarget / settingsWindow bindings or defaults)
    QtObject {
        id: vpnTheme
        readonly property color text: shellTarget ? shellTarget.colorText : "#cdd6f4"
        readonly property color subtext: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
        readonly property color accent: shellTarget ? shellTarget.colorAccent : "#89b4fa"
        readonly property color border: shellTarget ? shellTarget.colorBorder : "#313244"
        readonly property color error: "#f38ba8"
        // FIX: Extract font family explicitly as a safe primitive string to prevent object-clashing
        readonly property string fontFamily: settingsWindow ? settingsWindow.selectedFont : "sans-serif"
    }

    // Auto-clears the red text error state cleanly after 5 seconds
    Timer {
        id: errorDismissTimer
        interval: 5000
        repeat: false
        running: vpnLayoutRoot.hasImportError
        onTriggered: vpnLayoutRoot.hasImportError = false
    }

    // Explicit internal data store allows smooth tracking of rows
    ListModel {
        id: vpnListModel
    }

    // Reset browser directory to $HOME and hide warnings whenever settings app opens
    Connections {
        target: settingsWindow
        ignoreUnknownSignals: true
        
        function onVisibleChanged() {
            if (settingsWindow && settingsWindow.visible) {
                vpnLayoutRoot.showFileBrowser = false;
                vpnLayoutRoot.hasImportError = false;
                vpnLayoutRoot.currentBrowserPath = "file://" + Quickshell.env("HOME");
                vpnListPopulator.running = false;
                vpnListPopulator.running = true;
            }
        }
    }

    // Polling engine keeps state tracks synchronized
    Timer {
        id: syncVpnTimer
        interval: 3000
        running: settingsWindow && settingsWindow.visible && !vpnLayoutRoot.showFileBrowser
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            vpnListPopulator.running = false;
            vpnListPopulator.running = true;
        }
    }

    Timer {
        id: delayFetchTimer
        interval: 800 
        repeat: false
        running: false
        onTriggered: {
            publicIpFetcher.running = false;
            publicIpFetcher.running = true;
        }
    }

    // Robust Scraper processes system outputs into the local ListModel container smoothly
    Process {
        id: vpnListPopulator
        command: ["nmcli", "-g", "TYPE,NAME,STATE", "connection", "show"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanText = text.trim();
                if (!cleanText) {
                    vpnListModel.clear();
                    vpnLayoutRoot.activeVpnName = "";
                    return;
                }

                let lines = cleanText.split("\n");
                let incomingProfiles = [];
                let currentActive = "";

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    let parts = line.split(":");
                    if (parts.length >= 2) {
                        let type = parts[0];
                        let name = parts[1];
                        let state = parts[2] || "";

                        if (type === "wireguard" || type === "vpn" || type === "tun") {
                            let isActive = (state.indexOf("activated") !== -1);
                            if (isActive) {
                                currentActive = name;
                            }
                            if (incomingProfiles.indexOf(name) === -1) {
                                incomingProfiles.push(name);
                            }
                        }
                    }
                }

                vpnLayoutRoot.activeVpnName = currentActive;

                // Sync incoming profiles to our local ListModel without breaking object allocations
                for (let m = vpnListModel.count - 1; m >= 0; m--) {
                    let currentModelName = vpnListModel.get(m).profileName;
                    if (incomingProfiles.indexOf(currentModelName) === -1) {
                        vpnListModel.remove(m);
                    }
                }

                for (let p = 0; p < incomingProfiles.length; p++) {
                    let pName = incomingProfiles[p];
                    let foundIndex = -1;
                    
                    for (let m = 0; m < vpnListModel.count; m++) {
                        if (vpnListModel.get(m).profileName === pName) {
                            foundIndex = m;
                            break;
                        }
                    }

                    if (foundIndex === -1) {
                        vpnListModel.append({ "profileName": pName });
                    }
                }

                if (vpnLayoutRoot.activeVpnName !== "") {
                    for (let m = 0; m < vpnListModel.count; m++) {
                        if (vpnListModel.get(m).profileName === vpnLayoutRoot.activeVpnName) {
                            if (m !== 0) {
                                vpnListModel.move(m, 0, 1);
                            }
                            break;
                        }
                    }
                } else {
                    let sortingChanged = true;
                    while (sortingChanged) {
                        sortingChanged = false;
                        for (let i = 0; i < vpnListModel.count - 1; i++) {
                            let nameA = vpnListModel.get(i).profileName;
                            let nameB = vpnListModel.get(i+1).profileName;
                            if (nameA.localeCompare(nameB, undefined, { numeric: true }) > 0) {
                                vpnListModel.move(i + 1, i, 1);
                                sortingChanged = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // Dynamic Connection State Machine Manager (Handles Up/Down/Delete)
    Process {
        id: vpnStateExecutor
        running: false
        onExited: {
            vpnListPopulator.running = false;
            vpnListPopulator.running = true;
            delayFetchTimer.restart();
        }
    }

    // Native Public IP Scraper
    Process {
        id: publicIpFetcher
        command: ["curl", "-s", "-4", "icanhazip.com"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanIp = text.trim();
                if (cleanIp) {
                    vpnLayoutRoot.publicIpAddress = cleanIp;
                    vpnLayoutRoot.textVisible = true;
                }
            }
        }
    }

    // Pipeline: Attempts raw import and checks stderr stream for validation block tokens
    Process {
        id: vpnImporter
        running: false
        stderr: StdioCollector {
            onTextChanged: {
                if (text.indexOf("QS_IMPORT_FAILED") !== -1 || text.toLowerCase().indexOf("error") !== -1) {
                    vpnLayoutRoot.hasImportError = true;
                }
            }
        }
        onExited: {
            if (!vpnLayoutRoot.hasImportError) {
                notifyProc.command = ["notify-send", "-a", "VPN Manager", "-i", "network-vpn", "Profile Imported", "Configuration processed successfully."];
                notifyProc.running = true;
                nmcliReloader.running = true;
            }
        }
    }

    Process {
        id: nmcliReloader
        command: ["nmcli", "connection", "reload"]
        running: false
        onExited: {
            vpnListPopulator.running = false;
            vpnListPopulator.running = true;
        }
    }

    Process {
        id: notifyProc
        running: false
    }

    // Isolated state changes prevent crossover triggering blocks
    function toggleProfileState(profileName, itemChecked) {
        vpnLayoutRoot.textVisible = false;
        
        if (itemChecked) {
            if (vpnLayoutRoot.activeVpnName !== "" && vpnLayoutRoot.activeVpnName !== profileName) {
                vpnStateExecutor.command = [
                    "bash", "-c",
                    "nmcli connection down id '" + vpnLayoutRoot.activeVpnName + "' && nmcli connection up id '" + profileName + "'"
                ];
            } else {
                vpnStateExecutor.command = ["nmcli", "connection", "up", "id", profileName];
            }
        } else {
            vpnStateExecutor.command = ["nmcli", "connection", "down", "id", profileName];
        }
        vpnStateExecutor.running = true;
    }

    // Disconnects profile if active, then purges connection profile from NetworkManager
    function deleteProfile(profileName) {
        if (vpnLayoutRoot.activeVpnName === profileName) {
            vpnLayoutRoot.textVisible = false;
        }
        vpnStateExecutor.command = ["nmcli", "connection", "delete", "id", profileName];
        vpnStateExecutor.running = true;
    }

    Component.onCompleted: {
        publicIpFetcher.running = true;
        vpnListPopulator.running = true;
    }

    // --- Core Layout Rendering Area ---
    Item {
        anchors.fill: parent

        // Main Profile Control Panel
        ColumnLayout {
            anchors.fill: parent
            spacing: 16
            visible: !vpnLayoutRoot.showFileBrowser

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Available profiles:"
                    font.family: vpnTheme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    color: vpnTheme.text
                    Layout.fillWidth: true
                }

                Button {
                    id: importBtn
                    flat: true
                    implicitWidth: 150
                    implicitHeight: 34

                    background: Rectangle {
                        color: importBtn.hovered ? vpnTheme.border : "transparent"
                        border.color: importBtn.hovered ? vpnTheme.accent : vpnTheme.border
                        border.width: 1
                        radius: 8
                        
                        Behavior on border.color { ColorAnimation { duration: 110 } }
                        Behavior on color { ColorAnimation { duration: 110 } }
                    }

                    contentItem: Item {
                        anchors.fill: parent
                        RowLayout {
                            spacing: 6
                            anchors.centerIn: parent
                            
                            Text {
                                text: "upload_file"
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 16
                                color: vpnTheme.accent
                            }
                            Text {
                                text: "Import Profile"
                                font.family: vpnTheme.fontFamily
                                font.pixelSize: 13
                                font.bold: true
                                color: vpnTheme.text
                            }
                        }
                    }

                    onClicked: {
                        vpnLayoutRoot.hasImportError = false;
                        vpnLayoutRoot.showFileBrowser = true;
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }

            // Fallback visual block if zero WireGuard profiles exist
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 90
                color: Qt.rgba(0, 0, 0, 0.15)
                radius: 12
                border.color: vpnTheme.border
                border.width: 1
                visible: vpnListModel.count === 0

                Text {
                    anchors.centerIn: parent
                    text: "No VPN Profiles found. Click 'Import Profile' above to add a .conf file."
                    font.family: vpnTheme.fontFamily
                    font.pixelSize: 13
                    color: vpnTheme.subtext
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: profileListView
                    anchors.fill: parent
                    spacing: 10
                    clip: true
                    model: vpnListModel
                    
                    topMargin: 20
                    bottomMargin: 20

                    move: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: 220
                            easing.type: Easing.Linear
                        }
                    }

                    moveDisplaced: Transition {
                        NumberAnimation {
                            properties: "x,y"
                            duration: 220
                            easing.type: Easing.Linear
                        }
                    }

                    delegate: Rectangle {
                        id: profileCard
                        width: profileListView.width - 4 
                        height: 84
                        color: Qt.rgba(0, 0, 0, 0.15)
                        radius: 12
                        border.color: vpnLayoutRoot.activeVpnName === profileName ? vpnTheme.accent : vpnTheme.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 14

                            Rectangle {
                                width: 40; height: 40; radius: 20
                                color: vpnLayoutRoot.activeVpnName === profileName ? Qt.rgba(137/255, 180/255, 250/255, 0.15) : Qt.rgba(1, 1, 1, 0.05)

                                Text {
                                    anchors.centerIn: parent
                                    text: vpnLayoutRoot.activeVpnName === profileName ? "vpn_key" : "vpn_key_off"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 20
                                    color: vpnLayoutRoot.activeVpnName === profileName ? vpnTheme.accent : vpnTheme.subtext
                                }
                            }

                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true

                                Text {
                                    text: profileName 
                                    font.family: vpnTheme.fontFamily
                                    font.bold: true
                                    font.pixelSize: 14
                                    color: vpnTheme.text
                                    elide: Text.ElideRight
                                }

                                ColumnLayout {
                                    spacing: 0
                                    Layout.fillWidth: true

                                    Text {
                                        text: vpnLayoutRoot.activeVpnName === profileName ? "Connected" : "Disconnected"
                                        font.family: vpnTheme.fontFamily
                                        font.pixelSize: 12
                                        color: vpnTheme.subtext
                                    }

                                    Text {
                                        text: (vpnLayoutRoot.activeVpnName === profileName && vpnLayoutRoot.publicIpAddress !== "") 
                                            ? vpnLayoutRoot.publicIpAddress 
                                            : "No active endpoint"
                                        font.family: vpnTheme.fontFamily
                                        font.pixelSize: 11
                                        color: vpnLayoutRoot.activeVpnName === profileName ? vpnTheme.accent : "transparent"
                                        opacity: vpnLayoutRoot.textVisible ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                }
                            }

                            // Nested control layout aligns items cleanly on the right bound
                            RowLayout {
                                spacing: 30
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

                                Switch {
                                    id: itemToggleSwitch
                                    checked: vpnLayoutRoot.activeVpnName === profileName
                                    
                                    onClicked: {
                                        vpnLayoutRoot.toggleProfileState(profileName, checked);
                                    }

                                    background: Rectangle {
                                        implicitWidth: 44
                                        implicitHeight: 22
                                        radius: 11
                                        color: itemToggleSwitch.checked ? vpnTheme.accent : vpnTheme.border
                                        
                                        Rectangle {
                                            width: 16; height: 16; radius: 8; color: "#11111b"
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: itemToggleSwitch.checked ? 24 : 4
                                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                                        }
                                    }
                                    indicator: Item {}
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }

                                Button {
                                    id: deleteProfileBtn
                                    flat: true
                                    implicitWidth: 32
                                    implicitHeight: 32

                                    background: Rectangle {
                                        color: deleteProfileBtn.hovered ? Qt.rgba(243/255, 139/255, 168/255, 0.15) : "transparent"
                                        radius: 6
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                    }

                                    contentItem: Text {
                                        text: "delete"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 18
                                        color: deleteProfileBtn.hovered ? vpnTheme.error : vpnTheme.subtext
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                    }

                                    onClicked: {
                                        vpnLayoutRoot.deleteProfile(profileName);
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                }
                            }
                        }
                    }
                    ScrollBar.vertical: ScrollBar {}
                }

                Text {
                    id: floatingErrorText
                    text: "Error: check your config"
                    font.family: vpnTheme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                    color: vpnTheme.error
                    
                    anchors.top: parent.top
                    anchors.topMargin: -2 
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    visible: opacity > 0.0
                    opacity: vpnLayoutRoot.hasImportError ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }
        }

        // --- Custom Embedded File Browser Component ---
        ColumnLayout {
            anchors.fill: parent
            spacing: 12
            visible: vpnLayoutRoot.showFileBrowser

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Select WireGuard Config File:"
                    font.family: vpnTheme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    color: vpnTheme.text
                    Layout.fillWidth: true
                }

                Button {
                    id: cancelBrowserBtn
                    flat: true
                    implicitWidth: 80
                    implicitHeight: 30
                    
                    background: Rectangle {
                        color: cancelBrowserBtn.hovered ? vpnTheme.border : "transparent"
                        border.color: cancelBrowserBtn.hovered ? vpnTheme.accent : "transparent"
                        border.width: 1
                        radius: 6
                    }
                    contentItem: Text {
                        text: "Cancel"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: vpnTheme.fontFamily
                        color: vpnTheme.subtext
                    }
                    onClicked: vpnLayoutRoot.showFileBrowser = false
                }
            }

            Text {
                text: vpnLayoutRoot.currentBrowserPath.replace("file://", "")
                font.family: vpnTheme.fontFamily
                font.pixelSize: 12
                color: vpnTheme.accent
                elide: Text.ElideLeft
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(0, 0, 0, 0.2)
                radius: 10
                border.color: vpnTheme.border
                border.width: 1
                clip: true

                Item {
                    id: browserViewContainer
                    anchors.fill: parent
                    
                    property string pendingPath: ""
                    property string lastPath: ""

                    ListView {
                        id: fileListView
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        clip: true
                        
                        Behavior on contentY {
                            NumberAnimation { duration: 180; easing.type: Easing.Linear }
                        }

                        model: FolderListModel {
                            id: folderModel
                            folder: vpnLayoutRoot.currentBrowserPath
                            showDirsFirst: true
                            showDotAndDotDot: true
                            nameFilters: ["*.conf"] 
                        }

                        populate: null

                        delegate: ItemDelegate {
                            id: fileDelegateItem
                            width: fileListView.width
                            
                            height: fileName === "." ? 0 : 38
                            visible: fileName !== "."

                            background: Rectangle {
                                color: fileDelegateItem.hovered ? Qt.rgba(255/255, 255/255, 255/255, 0.04) : "transparent"
                                border.color: fileDelegateItem.hovered ? Qt.rgba(137/255, 180/255, 250/255, 0.3) : "transparent"
                                border.width: 1
                                radius: 6
                            }

                            contentItem: RowLayout {
                                spacing: 10
                                anchors.fill: parent
                                anchors.leftMargin: 8

                                Text {
                                    text: fileIsDir ? "folder" : "description"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 18
                                    color: fileIsDir ? "#f9e2af" : vpnTheme.accent
                                }

                                Text {
                                    text: fileName
                                    font.family: vpnTheme.fontFamily
                                    font.pixelSize: 13
                                    color: vpnTheme.text
                                    Layout.fillWidth: true
                                }
                            }

                            onClicked: {
                                if (fileIsDir) {
                                    browserViewContainer.lastPath = vpnLayoutRoot.currentBrowserPath;
                                    browserViewContainer.pendingPath = fileUrl.toString();
                                    pathFadeAnimation.start();
                                } else {
                                    let urlString = fileUrl.toString();
                                    let parsedPath = urlString.startsWith("file:///") 
                                        ? urlString.substring(7) 
                                        : urlString.replace("file://", "");

                                    vpnImporter.command = [
                                        "bash", "-c",
                                        "nmcli connection import type wireguard file '" + parsedPath + "' || echo 'QS_IMPORT_FAILED' >&2"
                                    ];
                                    vpnImporter.running = true;
                                    vpnLayoutRoot.showFileBrowser = false;
                                }
                            }
                        }
                        ScrollBar.vertical: ScrollBar {}
                    }

                    SequentialAnimation {
                        id: pathFadeAnimation
                        
                        ParallelAnimation {
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "opacity"
                                from: 1.0; to: 0.0
                                duration: 110
                                easing.type: Easing.Linear
                            }
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "x"
                                to: (browserViewContainer.pendingPath.length > browserViewContainer.lastPath.length) ? -30 : 30
                                duration: 110
                                easing.type: Easing.Linear
                            }
                        }
                        
                        ScriptAction {
                            script: {
                                vpnLayoutRoot.currentBrowserPath = browserViewContainer.pendingPath;
                            }
                        }
                        
                        PropertyAction {
                            target: browserViewContainer
                            property: "x"
                            value: (browserViewContainer.pendingPath.length > browserViewContainer.lastPath.length) ? 30 : -30
                        }
                        
                        ParallelAnimation {
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "opacity"
                                from: 0.0; to: 1.0
                                duration: 130
                                easing.type: Easing.Linear
                            }
                            PropertyAnimation {
                                target: browserViewContainer
                                property: "x"
                                to: 0
                                duration: 130
                                easing.type: Easing.Linear
                            }
                        }
                    }
                }
            }
        }
    }
}
