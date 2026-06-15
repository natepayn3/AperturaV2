import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Io

Item {
    id: launcherRoot

    property string namespace: "quickshell-applauncher-popup"

    property bool active: false
    property bool isHovered: popupHoverArea.containsMouse || contentHoverHandler.hovered
    
    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property real radiusValue: 12
    property real wingSize: 14

    property real maxCardWidth: 380
    property real maxCardHeight: 520

    signal closeRequested()

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: Math.round(maxCardHeight)
    width: Math.round(maxCardWidth)
    height: Math.round(maxCardHeight)
    opacity: 1.0
    visible: true
    clip: false

    x: rootShell.barPosition === "right" ? hoverOriginX + (maxCardWidth - width) : hoverOriginX
    y: rootShell.barPosition === "bottom" ? hoverOriginY + (maxCardHeight - height) : hoverOriginY

    // --- State Properties ---
    property var allApps: []
    property var filteredApps: []
    property var localPins: []

    // --- Core Logic & Pinning ---
    FileView {
        id: pinCacheReader
        path: Quickshell.env("HOME") + "/.cache/quickshell_launcher_pins.json"
        onTextChanged: {
            let cleanText = text().trim();
            if (!cleanText || cleanText === "[]") return;
            try {
                let parsed = JSON.parse(cleanText);
                if (parsed && parsed.pins) {
                    launcherRoot.localPins = parsed.pins;
                    launcherRoot.updateModel();
                }
            } catch(e) {}
        }
    }

    function togglePin(appPath) {
        let currentPins = launcherRoot.localPins.slice();
        let idx = currentPins.indexOf(appPath);
        if (idx !== -1) {
            currentPins.splice(idx, 1);
        } else {
            currentPins.push(appPath);
        }
        launcherRoot.localPins = currentPins;
        launcherRoot.updateModel();
        
        let jsonStr = JSON.stringify({ "pins": currentPins });
        Quickshell.execDetached(["bash", "-c", "echo '" + jsonStr + "' > ~/.cache/quickshell_launcher_pins.json"]);
    }

    // Inline shell execution utilizing awk to construct a pure JSON array from .desktop files
    Process {
        id: appFetcher
        command: ["bash", "-c", "find /usr/share/applications ~/.local/share/applications -maxdepth 2 -name '*.desktop' 2>/dev/null | awk 'BEGIN { print \"[\"; c=0 } { name=\"\"; exec=\"\"; icon=\"\"; nshow=0; while ((getline line < $0) > 0) { if (line ~ /^Name=/ && name==\"\") name = substr(line, 6); if (line ~ /^Exec=/ && exec==\"\") exec = substr(line, 6); if (line ~ /^Icon=/ && icon==\"\") icon = substr(line, 6); if (line ~ /^NoDisplay=true/) nshow=1 } close($0); if (name != \"\" && exec != \"\" && nshow==0) { gsub(/[\"\\\\]/, \"\", name); gsub(/[\"\\\\]/, \"\", exec); gsub(/[\"\\\\]/, \"\", icon); if (c > 0) print \",\"; printf \"{\\\"name\\\":\\\"%s\\\", \\\"exec\\\":\\\"%s\\\", \\\"icon\\\":\\\"%s\\\", \\\"path\\\":\\\"%s\\\"}\", name, exec, icon, $0; c++ } } END { print \"]\" }'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    launcherRoot.allApps = JSON.parse(this.text);
                    launcherRoot.updateModel();
                } catch(e) {}
            }
        }
    }

    function updateModel() {
        let query = searchInput.text.trim().toLowerCase();
        let pins = [];
        let others = [];

        for (let i = 0; i < launcherRoot.allApps.length; i++) {
            let app = launcherRoot.allApps[i];
            if (query !== "" && !app.name.toLowerCase().includes(query)) continue;

            if (launcherRoot.localPins.includes(app.path)) {
                pins.push(app);
            } else {
                others.push(app);
            }
        }

        pins.sort((a,b) => a.name.localeCompare(b.name));
        others.sort((a,b) => a.name.localeCompare(b.name));
        launcherRoot.filteredApps = pins.concat(others);
        
        appListView.currentIndex = 0;
        
        // Instantly snap the view to the top, bypassing all animations
        appListView.positionViewAtBeginning(); 
    }

    function launchApp(execString) {
        // Strip the freedesktop file-handler tags
        let cleanExec = execString.replace(/%[uUfFkKcCiI]/g, "").trim();
        
        // Fire the command through your custom Lua dispatcher
        Hyprland.dispatch(`hl.dsp.exec_cmd("${cleanExec}")`);
        
        launcherRoot.closeRequested();
    }

    onActiveChanged: {
        if (active) {
            if (allApps.length === 0) appFetcher.running = true;
            searchInput.text = "";
            searchInput.forceActiveFocus();
            pinCacheReader.reload();
            updateModel();
        }
    }

    // --- Visuals & Animations (Maintained perfectly from CalendarPopup) ---
    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.TopLeft
            if (rootShell.barPosition === "right") return Item.TopRight
            if (rootShell.barPosition === "top") return Item.TopLeft
            if (rootShell.barPosition === "bottom") return Item.BottomLeft
            return Item.Center
        }

        states: [
            State {
                name: "hidden"
                when: !launcherRoot.active
                PropertyChanges { target: animatedGroup; opacity: 0.0; scale: 0.0 }
                PropertyChanges { target: layoutContentWrapper; opacity: 0.0 }
                PropertyChanges { 
                    target: animatedGroup
                    x: {
                        switch (rootShell.barPosition) {
                            case "left":   return -40; 
                            case "bottom": return -40; 
                            case "right":  return 40;  
                            case "top":    return -40; 
                            default:       return 0;
                        }
                    }
                    y: {
                        switch (rootShell.barPosition) {
                            case "left":   return -40; 
                            case "bottom": return 40;  
                            case "right":  return -40; 
                            case "top":    return -40; 
                            default:       return 0;
                        }
                    }
                }
            },
            State {
                name: "shown"
                when: launcherRoot.active
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
            
            topLeftRadius: 0
            topRightRadius: rootShell.barPosition === "bottom" ? launcherRoot.radiusValue : 0
            bottomLeftRadius: rootShell.barPosition === "right" ? launcherRoot.radiusValue : 0
            bottomRightRadius: (rootShell.barPosition === "top" || rootShell.barPosition === "left") ? launcherRoot.radiusValue : 0
        }

        // --- Wings Component ---
        Item {
            anchors.fill: parent
            visible: launcherRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"

                Shape {
                    x: 0; y: parent.height
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: launcherRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: launcherRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: 0; y: launcherRoot.wingSize }
                        PathQuad { x: launcherRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"

                Shape {
                    x: 0; y: parent.height
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: launcherRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: launcherRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: 0; y: launcherRoot.wingSize }
                        PathQuad { x: launcherRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "bottom"

                Shape {
                    x: 0; y: -launcherRoot.wingSize
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: launcherRoot.wingSize
                        PathLine { x: launcherRoot.wingSize; y: launcherRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: 0; controlY: launcherRoot.wingSize }
                        PathLine { x: 0; y: launcherRoot.wingSize }
                    }
                }
                Shape {
                    rotation: -90
                    transformOrigin: Item.TopLeft
                    x: parent.width
                    y: parent.height
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: 0; startY: 0
                        PathLine { x: launcherRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: launcherRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                Shape {
                    x: -launcherRoot.wingSize; y: 0
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: launcherRoot.wingSize; startY: 0
                        PathLine { x: launcherRoot.wingSize; y: launcherRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: launcherRoot.wingSize; controlY: 0 }
                        PathLine { x: launcherRoot.wingSize; y: 0 }
                    }
                }
                
                Shape {
                    x: parent.width - launcherRoot.wingSize; y: parent.height
                    width: launcherRoot.wingSize; height: launcherRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground; strokeColor: "transparent"; strokeWidth: 0
                        startX: launcherRoot.wingSize; startY: 0
                        PathLine { x: launcherRoot.wingSize; y: launcherRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: launcherRoot.wingSize; controlY: 0 }
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
        }

        // --- Internal Content ---
        Item {
            id: layoutContentWrapper
            anchors.fill: parent
            anchors.margins: 18
            z: 5

            HoverHandler {
                id: contentHoverHandler
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                TextField {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    placeholderText: "Search applications..."
                    font.family: rootShell.shellFont
                    font.pixelSize: 15
                    color: rootShell.colorText
                    placeholderTextColor: rootShell.colorSubtext
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter
                    
                    background: Rectangle {
                        color: Qt.rgba(0, 0, 0, 0.2)
                        border.color: searchInput.activeFocus ? rootShell.colorAccent : rootShell.colorBorder
                        border.width: 1
                        radius: 8
                    }

                    onTextChanged: launcherRoot.updateModel()

                    onActiveFocusChanged: {
                        if (!activeFocus && launcherRoot.active) {
                            launcherRoot.closeRequested();
                        }
                    }

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Down) {
                            appListView.incrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            appListView.decrementCurrentIndex();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (appListView.currentItem) {
                                launcherRoot.launchApp(appListView.currentItem.appExec);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            launcherRoot.closeRequested();
                            event.accepted = true;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(255,255,255,0.1)
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: appListView
                        spacing: 4
                        keyNavigationEnabled: false
                        model: launcherRoot.filteredApps
                        
                        delegate: ItemDelegate {
                            id: appDelegate
                            width: appListView.width
                            height: 46
                            highlighted: appListView.currentIndex === index
                            
                            // Properties exposed for keyboard activation logic
                            property string appExec: modelData.exec
                            property bool isPinned: launcherRoot.localPins.includes(modelData.path)

                            background: Rectangle {
                                color: appDelegate.highlighted
                                    ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15)
                                    : (appDelegate.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                                radius: 8
                                border.width: appDelegate.highlighted ? 1 : 0
                                border.color: rootShell.colorAccent
                            }

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 12

                                Image {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    source: Quickshell.iconPath(modelData.icon !== "" ? modelData.icon : "application-x-executable")
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }

                                Text {
                                    text: modelData.name
                                    font.family: rootShell.shellFont
                                    font.pixelSize: 14
                                    color: appDelegate.isPinned ? rootShell.colorAccent : rootShell.colorText
                                    font.weight: appDelegate.isPinned ? Font.Bold : Font.Normal
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    text: "keep"
                                    visible: appDelegate.isPinned
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 16
                                    color: rootShell.colorAccent
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true

                                onEntered: appListView.currentIndex = index

                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        launcherRoot.togglePin(modelData.path);
                                    } else {
                                        launcherRoot.launchApp(modelData.exec);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
