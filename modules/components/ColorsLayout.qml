import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: colorsLayoutRoot
    
    property var shellTarget: null
    property var settingsWindow: null

    // 🎯 Define the expected color properties locally
    property color themeBorder: "transparent"
    property color themeAccent: "transparent"
    property color themeText: "transparent"

    Grid {
        anchors.fill: parent
        anchors.margins: 10
        columns: 2
        spacing: 12

        component ProfileCard : Button {
            id: cardBtn
            property string schemeId: ""
            property string schemeLabel: ""
            
            width: (parent.width - 12) / 2
            height: 60
            flat: true

            background: Rectangle {
                // 🎯 Reference the local properties directly
                color: settingsWindow.matugenScheme === schemeId 
                    ? themeBorder 
                    : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                
                border.color: settingsWindow.matugenScheme === schemeId 
                    ? themeAccent 
                    : (cardBtn.hovered ? Qt.rgba(1, 1, 1, 0.2) : "transparent")
                border.width: 0
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
            }

            onClicked: {
                settingsWindow.matugenScheme = schemeId;
                settingsWindow.pushUpdate();
                
                if (shellTarget && shellTarget.wallpaperRef) {
                    // 🎯 Read the reliable root property we just exposed
                    let activeWallpaper = shellTarget.wallpaperRef.currentWallpaperPath || "";
                    
                    // Force the apply pipeline using the new scheme layout ID
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
    }
}
