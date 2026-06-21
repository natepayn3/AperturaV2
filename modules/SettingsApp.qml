import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

Scope {
    id: settingsModuleRoot

    property var shellTarget: null
    
    // 🎯 The Binding Bridge
    // Strongly typed properties force QML to track the dynamic Matugen updates 
    // instead of losing them through the untyped `var` reference.
    property color themeBackground: shellTarget ? shellTarget.colorBackground : "#cc11111b"
    property color themeBorder: shellTarget ? shellTarget.colorBorder : "#313244"
    property color themeAccent: shellTarget ? shellTarget.colorAccent : "#89b4fa"
    property color themeText: shellTarget ? shellTarget.colorText : "#cdd6f4"
    property color themeSubtext: shellTarget ? shellTarget.colorSubtext : "#a6adc8"

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
        
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-settings"
        WlrLayershell.exclusionMode: WlrLayershell.Ignore
        WlrLayershell.keyboardFocus: settingsModuleRoot.windowVisible ? WlrLayershell.OnDemand : WlrLayershell.None

        anchors {
            left: true; right: true; top: true; bottom: true
        }
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            
            onPressed: (mouse) => {
                settingsModuleRoot.windowVisible = false;
                mouse.accepted = false;
            }
        }

        property string currentPosition: "left"
        property string enabledDisplays: "0"
        property string activeCategory: "Layout"
        property string selectedFont: "Rubik"
        property string fontSearchQuery: ""
        property string matugenScheme: "scheme-tonal-spot" 

        readonly property string configDir: shellTarget ? shellTarget.customBasePath : ""
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
                if (shellTarget.activeScheme !== undefined) {
                    matugenScheme = shellTarget.activeScheme;
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
                "font": settingsWindow.selectedFont,
                "matugen_scheme": settingsWindow.matugenScheme
            };
            
            // 🎯 jq merges the new payload with existing keys instead of overwriting the whole file
            writeProc.command = [
                "bash", "-c", 
                "if [ ! -f '" + configFilePath + "' ]; then echo '{}' > '" + configFilePath + "'; fi && " +
                "jq '. + " + JSON.stringify(updatePayload) + "' '" + configFilePath + "' > /tmp/shell_settings.tmp && mv /tmp/shell_settings.tmp '" + configFilePath + "'"
            ];
            writeProc.running = false;
            writeProc.running = true;
        }

        Process {
            id: writeProc
            running: false
        }

        Item {
            id: settingsCardFrame
            width: 800
            height: 580
            anchors.centerIn: parent
            transformOrigin: Item.Center

            MouseArea {
                anchors.fill: parent
                onPressed: (event) => event.accepted = true
                onClicked: (event) => event.accepted = true
            }

            Shortcut {
                sequence: "Escape"
                enabled: settingsModuleRoot.windowVisible
                onActivated: settingsModuleRoot.windowVisible = false
            }

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

                Rectangle {
                    anchors.fill: parent
                    color: settingsModuleRoot.themeBackground 
                    radius: 16
                    border.width: 0 
                    antialiasing: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3 
                        color: "transparent"
                        radius: 19 
                        border.color: settingsModuleRoot.themeAccent
                        border.width: 3
                        antialiasing: true
                        z: 10 
                    }

                    Row {
                        anchors.fill: parent

                        Rectangle {
                            width: 220
                            height: parent.height
                            color: "transparent"

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 3 
                                color: settingsModuleRoot.themeAccent
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
                                    color: settingsModuleRoot.themeSubtext
                                    height: 30
                                    x: 12
                                    verticalAlignment: Text.AlignVCenter
                                }

                                component CategoryButton : Button {
                                    id: catBtnItem
                                    property string categoryName: ""
                                    flat: true
                                    width: parent.width
                                    height: 40
                                    
                                    background: Rectangle { 
                                        color: settingsWindow.activeCategory === categoryName 
                                            ? settingsModuleRoot.themeBorder 
                                            : (catBtnItem.hovered ? Qt.rgba(255/255, 255/255, 255/255, 0.04) : "transparent")
                                        
                                        border.color: catBtnItem.hovered ? settingsModuleRoot.themeAccent : "transparent"
                                        border.width: 1
                                        radius: 8 
                                        
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                        Behavior on border.color { ColorAnimation { duration: 110 } }
                                    }
                                    
                                    contentItem: Text { 
                                        text: parent.categoryName
                                        color: settingsWindow.activeCategory === categoryName ? settingsModuleRoot.themeAccent : settingsModuleRoot.themeText
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
                                CategoryButton { categoryName: "Colors" }
                                CategoryButton { categoryName: "VPN" }
                            }
                        }

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
                                    color: settingsModuleRoot.themeText
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
                                    
                                    background: Rectangle { 
                                        anchors.fill: parent
                                        color: closeBtn.hovered ? settingsModuleRoot.themeBorder : "transparent"
                                        border.color: closeBtn.hovered ? settingsModuleRoot.themeAccent : "transparent"
                                        border.width: 1
                                        radius: 8 
                                        
                                        Behavior on color { ColorAnimation { duration: 110 } }
                                        Behavior on border.color { ColorAnimation { duration: 110 } }
                                    }
                                    
                                    Text { 
                                        text: "close" 
                                        font.family: "Material Symbols Outlined" 
                                        font.pixelSize: 20
                                        color: settingsModuleRoot.themeAccent
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

                                ColorsLayout {
                                    anchors.fill: parent
                                    visible: settingsWindow.activeCategory === "Colors"
                                    shellTarget: settingsModuleRoot.shellTarget
                                    settingsWindow: settingsWindow
                                    
                                    // 🎯 Inject the reactive variables here
                                    themeBorder: settingsModuleRoot.themeBorder
                                    themeAccent: settingsModuleRoot.themeAccent
                                    themeText: settingsModuleRoot.themeText
                                }

                                VpnLayout {
                                    id: vpnLayoutSection
                                    anchors.fill: parent
                                    visible: settingsWindow.activeCategory === "VPN"
                                    shellTarget: settingsModuleRoot.shellTarget
                                    settingsWindow: settingsWindow
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
