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
    property alias windowVisible: settingsWindow.visible

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
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        implicitWidth: 800
        implicitHeight: 580
        
        // This must stay transparent so the window system handles alpha clipping
        color: "transparent"

        anchors {
            left: false; right: false; top: false; bottom: false
        }

        property string currentPosition: "left"
        property string enabledDisplays: "0"
        property string activeCategory: "Layout"
        property string selectedFont: "Rubik"
        property string fontSearchQuery: ""

        readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell/Test"
        readonly property string configFilePath: configDir + "/shell_settings.json"

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

        // Structural canvas buffer wrapper to force clean subpixel vector scaling
        Item {
            anchors.fill: parent
            
            Rectangle {
                anchors.fill: parent
                color: shellTarget ? shellTarget.colorBackground : "#cc11111b" 
                radius: 20
                border.color: shellTarget ? shellTarget.colorBorder : "#313244" 
                border.width: 3

                // Standard, collision-free edge smoothing
                antialiasing: true

                Row {
                    anchors.fill: parent

                    Rectangle {
                        width: 220
                        height: parent.height
                        color: "transparent"

                        Rectangle {
                            anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                            width: 2
                            color: shellTarget ? shellTarget.colorBorder : "#313244"
                        }

                        Column {
                            anchors.fill: parent; anchors.margins: 20
                            spacing: 12

                            Text {
                                text: "Preferences"
                                font.family: settingsWindow.selectedFont
                                font.pixelSize: 14
                                font.bold: true
                                font.letterSpacing: 1
                                color: shellTarget ? shellTarget.colorSubtext : "#a6adc8"
                                height: 30
                                x: 20
                            }

                            component CategoryButton : Button {
                                property string categoryName: ""
                                flat: true
                                width: parent.width
                                height: 44
                                background: Rectangle { 
                                    color: settingsWindow.activeCategory === categoryName ? (shellTarget ? shellTarget.colorBorder : "#313244") : "transparent"
                                    radius: 10 
                                }
                                contentItem: Text { 
                                    text: parent.categoryName
                                    color: settingsWindow.activeCategory === categoryName ? (shellTarget ? shellTarget.colorAccent : "#89b4fa") : (shellTarget ? shellTarget.colorText : "#cdd6f4")
                                    font.family: settingsWindow.selectedFont
                                    font.pixelSize: 16
                                    font.bold: settingsWindow.activeCategory === categoryName
                                    anchors.left: parent.left; anchors.leftMargin: 20
                                    verticalAlignment: Text.AlignVCenter 
                            }
                                onClicked: settingsWindow.activeCategory = categoryName
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                            CategoryButton { categoryName: "Layout" }
                            CategoryButton { categoryName: "Font" }
                            CategoryButton { categoryName: "Modules" }
                            CategoryButton { categoryName: "Behavior" }
                        }
                    }

                    Item {
                        width: parent.width - 220
                        height: parent.height

                        Item {
                            id: contentHeader
                            width: parent.width; height: 70
                            anchors.top: parent.top

                            Text {
                                text: settingsWindow.activeCategory
                                font.family: settingsWindow.selectedFont
                                font.pixelSize: 26; font.bold: true
                                color: shellTarget ? shellTarget.colorText : "#cdd6f4"
                                anchors.left: parent.left; anchors.leftMargin: 30
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                id: closeBtn; flat: true
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 20
                                anchors.rightMargin: 20
                                implicitWidth: 40
                                implicitHeight: 40
                                
                                background: Rectangle { 
                                    anchors.fill: parent
                                    color: closeBtn.hovered ? (shellTarget ? shellTarget.colorBorder : "#313244") : "transparent"
                                    radius: 10 
                                }
                                
                                Text { 
                                    text: "close" 
                                    font.family: "Material Icons" 
                                    font.pixelSize: 22
                                    font.bold: false
                                    color: shellTarget ? shellTarget.colorAccent : "#89b4fa"
                                    anchors.centerIn: parent
                                }
                                
                                onClicked: settingsWindow.visible = false
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
                            
                            Loader {
                                anchors.fill: parent
                                active: settingsWindow.activeCategory !== "Layout" && settingsWindow.activeCategory !== "Font"
                                sourceComponent: Component {
                                    Text { 
                                        text: "Configuration for " + settingsWindow.activeCategory + " is coming soon."
                                        font.family: settingsWindow.selectedFont; font.pixelSize: 20
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
