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

    Component.onCompleted: {
        if (shellTarget && shellTarget.currentScheme) {
            settingsWindow.matugenScheme = shellTarget.currentScheme;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 12

        component ProfileCard : Button {
            id: cardBtn
            property string schemeId: ""
            property string schemeLabel: ""
            
            property var customPalette: [] 
            
            Layout.fillWidth: true
            Layout.preferredHeight: 60
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
                spacing: 12

                Text {
                    text: "palette"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    color: settingsWindow.matugenScheme === schemeId ? themeAccent : themeText
                }

                Text {
                    Layout.fillWidth: true
                    text: schemeLabel
                    font.family: settingsWindow.selectedFont
                    font.pixelSize: 14
                    font.bold: true
                    color: themeText
                    verticalAlignment: Text.AlignVCenter
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 12
                    
                    visible: settingsWindow.matugenScheme === schemeId || cardBtn.customPalette.length > 0
                    
                    Repeater {
                        model: cardBtn.customPalette.length > 0 ? cardBtn.customPalette : [themeAccent, themeBorder, themeText]
                        
                        RowLayout {
                            spacing: 4
                            
                            Rectangle {
                                width: 14
                                height: 14
                                radius: 4
                                color: modelData
                                border.color: Qt.rgba(1, 1, 1, 0.2)
                                border.width: 1
                            }
                            
                            Text {
                                text: String(modelData).substring(0, 7).toUpperCase()
                                font.family: "monospace"
                                font.pixelSize: 10
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
                    // Removed the assignment to currentScheme here to prevent QML execution halt
                    let activeWallpaper = shellTarget.wallpaperRef.currentWallpaperPath || "";
                    shellTarget.wallpaperRef.apply(activeWallpaper, false, schemeId);
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
        
        Item { Layout.fillHeight: true }
    }
}
