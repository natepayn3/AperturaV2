import QtQuick
import QtQuick.Layouts

Item {
    id: mediaRoot
    Layout.fillWidth: true
    Layout.preferredHeight: 48

    // Pass actions up to the main Process handlers
    signal playPauseClicked()
    signal prevClicked()
    signal nextClicked()

    RowLayout {
        anchors.fill: parent
        spacing: 16

        Rectangle { 
            width: 48; height: 48; radius: 8
            color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.2)
            Text { anchors.centerIn: parent; text: "music_note"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 24 } 
        }

        ColumnLayout {
            spacing: 2; Layout.fillWidth: true
            Text { text: dashboardRoot.mediaTitle; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
            Text { text: dashboardRoot.mediaArtist; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
        }

        RowLayout {
            spacing: 8
            MouseArea { 
                width: 24; height: 24; cursorShape: Qt.PointingHandCursor
                onClicked: mediaRoot.prevClicked()
                Text { anchors.centerIn: parent; text: "skip_previous"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20 }
            }
            Rectangle { 
                width: 36; height: 36; radius: 18; color: rootShell.colorText
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mediaRoot.playPauseClicked() }
                Text { anchors.centerIn: parent; text: dashboardRoot.mediaStatus === "Playing" ? "pause" : "play_arrow"; font.family: "Material Symbols Outlined"; color: rootShell.colorBackground; font.pixelSize: 20 } 
            }
            MouseArea { 
                width: 24; height: 24; cursorShape: Qt.PointingHandCursor
                onClicked: mediaRoot.nextClicked()
                Text { anchors.centerIn: parent; text: "skip_next"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20 }
            }
        }
    }
}
