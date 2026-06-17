import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: settingsModuleRoot

    property var shellTarget: null
    
    property alias settingsWindowObject: settingsWindow
    
    property bool windowVisible: false
    onWindowVisibleChanged: {
        if (windowVisible) {
            settingsWindow.visible = true;
        }
    }

    function updateDisplaysFromShell() {
        if (shellTarget) {
            settingsWindow.enabledDisplays = shellTarget.enabledDisplayStr;
        }
    }

    PanelWindow {
        id: settingsWindow
        visible: false
        
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-settings"
        WlrLayershell.exclusionMode: WlrLayershell.Ignore
        WlrLayershell.keyboardFocus: settingsModuleRoot.windowVisible ? WlrLayershell.OnDemand : WlrLayershell.None

        anchors {
            left: true; right: true; top: true; bottom: true
        }
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            enabled: settingsModuleRoot.windowVisible
            onPressed: settingsModuleRoot.windowVisible = false
        }

        property string currentPosition: "left"
        property string enabledDisplays: "0"
        property string activeCategory: "Layout"
        property string selectedFont: "Rubik"
        property string fontSearchQuery: ""

        readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell/Test"
        readonly property string configFilePath: configDir + "/shell_settings.json"

        function getGeometricallySortedScreens() {
            let screensList = [];
            if (!Quickshell.screens) return screensList;

            for (let i = 0; i < Quickshell.screens.length; i++) {
                let scr = Quickshell.screens[i];
                if (scr) {
                    screensList.push({ "obj": scr, "index": i });
                }
            }

            let maxDeltaX = 0;
            let maxDeltaY = 0;
            if (screensList.length > 1) {
                let minX = Math.min(...screensList.map(s => s.obj.x));
                let maxX = Math.max(...screensList.map(s => s.obj.x));
                let minY = Math.min(...screensList.map(s => s.obj.y));
                let maxY = Math.max(...screensList.map(s => s.obj.y));
                maxDeltaX = maxX - minX;
                maxDeltaY = maxY - minY;
            }

            screensList.sort((a, b) => {
                if (maxDeltaY > maxDeltaX) {
                    return a.obj.y - b.obj.y;
                } else {
                    return a.obj.x - b.obj.x;
                }
            });
            return screensList;
        }

        Component.onCompleted: {
            if (shellTarget) {
                currentPosition = shellTarget.barPosition;
                enabledDisplays = shellTarget.enabledDisplayStr;
                if (shellTarget.shellFont !== undefined) {
                    selectedFont = shellTarget.shellFont;
                }
            }
        }

        Connections {
            target: settingsModuleRoot.shellTarget
            ignoreUnknownSignals: true

            function onBarPositionChanged() {
                if (settingsModuleRoot.shellTarget) {
                    settingsWindow.currentPosition = settingsModuleRoot.shellTarget.barPosition;
                }
            }

            function onEnabledDisplayStrChanged() {
                if (settingsModuleRoot.shellTarget) {
                    settingsWindow.enabledDisplays = settingsModuleRoot.shellTarget.enabledDisplayStr;
                }
            }
        }

        function isLocalDisplayActive(idx) {
            let items = enabledDisplays.split(",");
            return items.indexOf(String(idx)) !== -1;
        }

        function pushUpdate() {
            let updatePayload = {
                "position": settingsWindow.currentPosition,
                "enabledDisplays": settingsWindow.enabledDisplays,
                "font": settingsWindow.selectedFont
            };
            
            writeProc.command = [
                "bash", "-c", 
                "mkdir -p '" + configDir + "' && echo '" + JSON.stringify(updatePayload) + "' > '" + configFilePath + "'"
            ];
            writeProc.running = false;
            writeProc.running = true;
        }

        Process {
            id: writeProc
            running: false
        }

        // --- Fullscreen Input Backdrop Catcher ---
        MouseArea {
            id: settingsBackdropCatcher
            anchors.fill: parent
            
            onClicked: {
                if (settingsWindow.activeCategory === "VPN" && vpnLayoutSection.showFileBrowser) {
                    return;
                }
                settingsModuleRoot.windowVisible = false;
            }

            // Centralized container tracking settings layout bounds
            Item {
                id: settingsCardFrame
                width: 800
                height: 580
                anchors.centerIn: parent
                transformOrigin: Item.Center

                MouseArea {
                    anchors.fill: parent
                    // This consumes the click so it doesn't hit the background shield
                    onPressed: (event) => event.accepted = true
                    onClicked: (event) => event.accepted = true
                }

                Shortcut {
                    sequence: "Escape"
                    enabled: settingsModuleRoot.windowVisible
                    onActivated: settingsModuleRoot.windowVisible = false
                }

                // --- Animation States ---
                states: [
                    State {
                        name: "hidden"
                        when: !settingsModuleRoot.windowVisible
                        PropertyChanges { target: settingsCardFrame; opacity: 0.0; scale: 0.0 }
                    },
                    State {
                        name: "shown"
                        when: settingsModuleRoot.windowVisible
                        PropertyChanges { target: settingsCardFrame; opacity: 1.0; scale: 1.0 }
                    }
                ]

                // --- Animation Transitions ---
                transitions: [
                    Transition {
                        from: "hidden"; to: "shown"
                        ParallelAnimation {
                            NumberAnimation { target: settingsCardFrame; property: "scale"; duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                            NumberAnimation { target: settingsCardFrame; property: "opacity"; duration: 250; easing.type: Easing.OutQuad }
                        }
                    },
                    Transition {
                        from: "shown"; to: "hidden"
                        SequentialAnimation {
                            ParallelAnimation {
                                NumberAnimation { target: settingsCardFrame; property: "scale"; duration: 350; easing.type: Easing.InBack; easing.overshoot: 1.1 }
                                NumberAnimation { target: settingsCardFrame; property: "opacity"; duration: 250; easing.type: Easing.InQuad }
                            }
                            ScriptAction {
                                script: settingsWindow.visible = false
                            }
                        }
                    }
                ]

                // Floor input blocker sits behind interactive content elements
                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true; }
                }

                // Focus Scope grabs active window interactions cleanly to evaluate hotkeys
                FocusScope {
                    anchors.fill: parent
                    Component.onCompleted: forceActiveFocus()
                    
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            if (settingsWindow.activeCategory === "VPN" && vpnLayoutSection.showFileBrowser) {
                                event.accepted = true;
                                return;
                            }
                            settingsModuleRoot.windowVisible = false;
                            event.accepted = true;
                        }
                    }

                    // Main Framework Window Plate
                    Rectangle {
                        anchors.fill: parent
                        // Matugen Hook: Dynamic translucent container color matching your blurred windows
                        color: shellTarget ? shellTarget.colorBackground : "#cc11111b" 
                        radius: 16
                        border.width: 0 
                        antialiasing: true

                        // Outer 3px Border Wrapper Overlay (Matches text color)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3 // Forces the 3px border to sit strictly on the outside
                            color: "transparent"
                            radius: 19 // Scaled radius (16 + 3) to preserve clean corner uniformity
                            border.color: shellTarget ? shellTarget.colorText : "#cdd6f4" 
                            border.width: 3
                            antialiasing: true
                            z: 10 // Ensures layout edges don't bleed through the outer frame
                        }

                        Row {
                            anchors.fill: parent

                            // --- Left Navigation Sidebar Panel ---
                            Rectangle {
                                width: 220
                                height: parent.height
                                color: "transparent"

                                // Updated 3px minimal split dividing segment (Matches text color)
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 3 
                                    color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                }

                                Column {
                                    anchors.fill: parent; anchors.margins: 20
                                    spacing: 8

                                    Text {
                                        text: "Preferences"
                                        font.family: settingsWindow.selectedFont
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                                        height: 30
                                        x: 12
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    // Component Prototype: Sidebar Category Button
                                    component CategoryButton : Button {
                                        id: catBtnItem
                                        property string categoryName: ""
                                        flat: true
                                        width: parent.width
                                        height: 40
                                        
                                        // Matugen Hook: Unified translucent card hover border highlights 
                                        background: Rectangle { 
                                            color: settingsWindow.activeCategory === categoryName 
                                                ? (shellTarget ? shellTarget.colorBorder : "#313244") 
                                                : (catBtnItem.hovered ? Qt.rgba(255/255, 255/255, 255/255, 0.04) : "transparent")
                                            
                                            border.color: catBtnItem.hovered 
                                                ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                                                : "transparent"
                                            border.width: 1
                                            radius: 8 
                                            
                                            Behavior on color { ColorAnimation { duration: 110 } }
                                            Behavior on border.color { ColorAnimation { duration: 110 } }
                                        }
                                        
                                        contentItem: Text { 
                                            text: parent.categoryName
                                            color: settingsWindow.activeCategory === categoryName 
                                                ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") 
                                                : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                                            font.family: settingsWindow.selectedFont
                                            font.pixelSize: 14
                                            font.bold: settingsWindow.activeCategory === categoryName
                                            anchors.left: parent.left; anchors.leftMargin: 16
                                            verticalAlignment: Text.AlignVCenter 
                                        }
                                        
                                        onClicked: settingsWindow.activeCategory = categoryName
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    }
                                    
                                    CategoryButton { categoryName: "Layout" }
                                    CategoryButton { categoryName: "Font" }
                                    CategoryButton { categoryName: "VPN" }
                                    CategoryButton { categoryName: "Modules" }
                                    CategoryButton { categoryName: "Behavior" }
                                }
                            }

                            // --- Right Content Area ---
                            Item {
                                width: parent.width - 223 
                                height: parent.height

                                Item {
                                    id: contentHeader
                                    width: parent.width; height: 70
                                    anchors.top: parent.top

                                    Text {
                                        text: settingsWindow.activeCategory
                                        font.family: settingsWindow.selectedFont
                                        font.pixelSize: 24; font.bold: true
                                        color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                        anchors.left: parent.left; anchors.leftMargin: 30
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Button {
                                        id: closeBtn; flat: true
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.topMargin: 18
                                        anchors.rightMargin: 25
                                        implicitWidth: 36
                                        implicitHeight: 36
                                        
                                        // Matugen Hook: Unified close button hover outline border
                                        background: Rectangle { 
                                            anchors.fill: parent
                                            color: closeBtn.hovered ? (shellTarget ? shellTarget.colorBorder : "#313244") : "transparent"
                                            border.color: closeBtn.hovered ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : "transparent"
                                            border.width: 1
                                            radius: 8 
                                            
                                            Behavior on color { ColorAnimation { duration: 110 } }
                                            Behavior on border.color { ColorAnimation { duration: 110 } }
                                        }
                                        
                                        Text { 
                                            text: "close" 
                                            font.family: "Material Symbols Outlined" 
                                            font.pixelSize: 20
                                            color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                                            anchors.centerIn: parent
                                        }
                                        
                                        onClicked: settingsModuleRoot.windowVisible = false
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    }
                                }

                                Item {
                                    anchors.top: contentHeader.bottom; anchors.bottom: parent.bottom
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 30

                                    MonitorLayout {
                                        anchors.fill: parent
                                        visible: settingsWindow.activeCategory === "Layout"
                                        shellTarget: settingsModuleRoot.shellTarget
                                        settingsWindow: settingsWindow
                                    }

                                    Fonts {
                                        anchors.fill: parent
                                        visible: settingsWindow.activeCategory === "Font"
                                        shellTarget: settingsModuleRoot.shellTarget
                                        settingsWindow: settingsWindow
                                    }

                                    VpnLayout {
                                        id: vpnLayoutSection
                                        anchors.fill: parent
                                        visible: settingsWindow.activeCategory === "VPN"
                                        shellTarget: settingsModuleRoot.shellTarget
                                        settingsWindow: settingsWindow
                                    }
                                    
                                    Loader {
                                        anchors.fill: parent
                                        active: settingsWindow.activeCategory !== "Layout" && settingsWindow.activeCategory !== "Font" && settingsWindow.activeCategory !== "VPN"
                                        sourceComponent: Component {
                                            Text { 
                                                text: "Configuration for " + settingsWindow.activeCategory + " is coming soon."
                                                font.family: settingsWindow.selectedFont; font.pixelSize: 18
                                                color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
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
    }
}
