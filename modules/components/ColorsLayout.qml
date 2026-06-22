import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: colorsLayoutRoot
    
    property var shellTarget: null
    property var settingsWindow: null

    property color themeBorder: "transparent"
    property color themeAccent: "transparent"
    property color themeText: "transparent"

    Binding {
        target: settingsWindow
        property: "matugenScheme"
        value: shellTarget && shellTarget.wallpaperRef ? shellTarget.wallpaperRef.currentScheme : "scheme-tonal-spot"
    }

    ScrollView {
        id: scrollContainer
        anchors.fill: parent
        clip: true
        topPadding: 0
        leftPadding: 10
        rightPadding: 10
        bottomPadding: 16
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        
        ColumnLayout {
            width: scrollContainer.availableWidth
            spacing: 12 

            component ProfileCard : Button {
                id: cardBtn
                property string schemeId: ""
                property string schemeLabel: ""
 
                property var customPalette: shellTarget && shellTarget.matugenPreviews && shellTarget.matugenPreviewTick >= 0 ? 
                    (shellTarget.matugenPreviews[schemeId] || []) : []

                Layout.fillWidth: true
                Layout.preferredHeight: 48
                flat: true

                background: Rectangle {
                    color: settingsWindow.matugenScheme === schemeId 
                        ? Qt.rgba(themeBorder.r, themeBorder.g, themeBorder.b, 0.1) 
                        : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                    border.color: settingsWindow.matugenScheme === schemeId 
                        ? themeAccent 
                        : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                    border.width: settingsWindow.matugenScheme === schemeId ? 2 : 1
                    radius: 8
                }

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Item {
                        Layout.preferredWidth: 26
                        Layout.fillHeight: true

                        Text {
                            anchors.centerIn: parent
                            text: "palette"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 22 
                            color: settingsWindow.matugenScheme === schemeId ? themeAccent : themeText
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: schemeLabel
                        font.family: settingsWindow.selectedFont
                        font.pixelSize: 15
                        font.bold: true
                        color: themeText
                        verticalAlignment: Text.AlignVCenter
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        spacing: 12
                        visible: true
                        opacity: settingsWindow.matugenScheme === schemeId ? 1.0 : 0.4
                        
                        Repeater {
                            model: cardBtn.customPalette.length > 0 
                                 ? cardBtn.customPalette 
                                 : [themeText, themeText, themeText]
                            
                            RowLayout {
                                spacing: 6
                                
                                Rectangle {
                                    width: 14 
                                    height: 14
                                    radius: 4
                                    color: cardBtn.customPalette.length > 0 ? modelData : Qt.rgba(1, 1, 1, 0.1)
                                    border.color: Qt.rgba(1, 1, 1, 0.2)
                                    border.width: 1
                                }
                                
                                Text {
                                    text: cardBtn.customPalette.length > 0 ? String(modelData).substring(0, 7).toUpperCase() : "..."
                                    font.family: "monospace"
                                    font.pixelSize: 11
                                    color: themeText
                                }
                            }
                        }
                    }
                }

                onClicked: {
                    settingsWindow.matugenScheme = schemeId;
                    settingsWindow.pushUpdate();
                    if (shellTarget && shellTarget.wallpaperRef) {
                        let activeWallpaper = shellTarget.wallpaperRef.currentWallpaperPath || "";
                        shellTarget.wallpaperRef.apply(activeWallpaper, false, schemeId);
                    }
                }
                
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            Button {
                id: shutterBtn
                Layout.fillWidth: false
                Layout.preferredWidth: 240
                Layout.preferredHeight: 56
                Layout.alignment: Qt.AlignLeft
                flat: true
                readonly property bool isActive: shellTarget ? shellTarget.shutterModeActive : false

                background: Rectangle {
                    color: shutterBtn.isActive 
                        ? Qt.rgba(themeAccent.r, themeAccent.g, themeAccent.b, 0.08)
                        : (shutterBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                    border.color: shutterBtn.isActive ? themeAccent : (shutterBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                    border.width: shutterBtn.isActive ? 2 : 1
                    radius: 8
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                contentItem: RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Item {
                        Layout.preferredWidth: 26
                        Layout.fillHeight: true

                        Text {
                            anchors.centerIn: parent
                            text: shutterBtn.isActive ? "control_camera" : "camera"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 22
                            color: shutterBtn.isActive ? themeAccent : themeText
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0 
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                        Text {
                            text: "Shutter Mode"
                            font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                            font.pixelSize: 15
                            font.bold: true
                            color: themeText
                            Layout.fillWidth: true               
                            horizontalAlignment: Text.AlignLeft  
                        }
            
                        Text {
                            text: shutterBtn.isActive ? "Transparency OFF" : "Transparency ON"
                            font.family: settingsWindow ? settingsWindow.selectedFont : "sans"
                            font.pixelSize: 11
                            color: themeText
                            opacity: shutterBtn.isActive ? 0.6 : 0.4
                            Layout.fillWidth: true               
                            horizontalAlignment: Text.AlignLeft  
                        }
                    }
                    
                    Rectangle {
                        width: 20
                        height: 20
                        radius: 6
                        color: shutterBtn.isActive ? themeAccent : "transparent"
                        border.color: shutterBtn.isActive ? themeAccent : Qt.rgba(themeText.r, themeText.g, themeText.b, 0.3)
                        border.width: shutterBtn.isActive ? 0 : 1
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Text {
                            text: "done"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 14
                            font.bold: true
                            color: "#0B0F19"
                            anchors.centerIn: parent
                            visible: shutterBtn.isActive
                        }
                    }
                }

                onClicked: {
                    if (shellTarget && typeof shellTarget.toggleShutterMode === "function") {
                        shellTarget.toggleShutterMode();
                    }
                }
                
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }

            ProfileCard { schemeId: "scheme-tonal-spot"; schemeLabel: "Tonal Spot" }
            ProfileCard { schemeId: "scheme-expressive"; schemeLabel: "Expressive" }
            ProfileCard { schemeId: "scheme-fruit-salad"; schemeLabel: "Fruit Salad" }
            ProfileCard { schemeId: "scheme-rainbow"; schemeLabel: "Rainbow" }
            ProfileCard { schemeId: "scheme-neutral"; schemeLabel: "Neutral" }
            ProfileCard { schemeId: "scheme-monochrome"; schemeLabel: "Monochrome" }
        }
    }
}
