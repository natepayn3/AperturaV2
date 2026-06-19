import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: notifRoot
    Layout.fillWidth: true
    
    // Dropped the empty-state height from 104 to 64 to match the geometry layer
    Layout.preferredHeight: notifList.count <= 0 ? 64 : (notifList.count === 1 ? 104 : 176)
    
    Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
    spacing: 12

    property var notificationModel: notifServer.trackedNotifications

    RowLayout {
        Layout.fillWidth: true
        // Hides the entire row, removing its layout footprint when empty
        visible: notifList.count > 0 
        
        Item { Layout.fillWidth: true } 
        
        Item {
            implicitWidth: clearText.width + 10; implicitHeight: 20
            
            Text { 
                id: clearText
                text: "Clear all"
                font.family: rootShell.shellFont
                font.pixelSize: 11
                anchors.centerIn: parent
                color: clearMouse.containsMouse ? rootShell.colorText : rootShell.colorAccent 
            }
            
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                
                onClicked: {
                    let arr = notifRoot.notificationModel.values;
                    if (arr && arr.length > 0) {
                        for (let i = arr.length - 1; i >= 0; i--) {
                            if (arr[i]) arr[i].dismiss();
                        }
                    }
                }
            }
        }
    }
    
    // Geometry isolation layer to prevent empty-state snapping layout bugs
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: notifList.count <= 0 ? 64 : (notifList.count === 1 ? 64 : 136)
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

        // Centered Empty State Frame
        Rectangle {
            id: emptyStateBox
            anchors.fill: parent
            radius: 16
            color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
            
            transformOrigin: Item.Center
            opacity: notifList.count === 0 ? 1.0 : 0.0
            scale: notifList.count === 0 ? 1.0 : 0.8
            visible: opacity > 0.01

            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            Text { 
                text: "No notifications" 
                anchors.centerIn: parent 
                font.family: rootShell.shellFont 
                color: rootShell.colorSubtext 
                font.pixelSize: 12 
            }
        }

        // Notification Stream View
        ListView {
            id: notifList
            anchors.fill: parent
            clip: true
            spacing: 8
            model: notifRoot.notificationModel
            opacity: notifList.count > 0 ? 1.0 : 0.0
            
            Behavior on opacity { NumberAnimation { duration: 150 } }

            remove: Transition { ParallelAnimation { NumberAnimation { property: "opacity"; to: 0; duration: 200 } } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic } }

            delegate: Rectangle {
                required property var modelData
                width: notifList.width
                height: 64
                radius: 12
                color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.05)
                
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 12
                    Rectangle {
                        width: 40; height: 40; radius: 8; color: Qt.rgba(rootShell.colorText.r, rootShell.colorText.g, rootShell.colorText.b, 0.1)
                        Text { anchors.centerIn: parent; text: "notifications"; font.family: "Material Symbols Outlined"; color: rootShell.colorText; font.pixelSize: 20; visible: notifImg.status !== Image.Ready }
                        Image { id: notifImg; anchors.fill: parent; anchors.margins: 4; source: (modelData.image && modelData.image.startsWith("/")) ? modelData.image : ""; visible: source !== ""; fillMode: Image.PreserveAspectFit }
                    }
                    ColumnLayout {
                        spacing: 2; Layout.fillWidth: true
                        Text { text: modelData.summary; color: rootShell.colorText; font.family: rootShell.shellFont; font.bold: true; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text { text: modelData.body; color: rootShell.colorSubtext; font.family: rootShell.shellFont; font.pixelSize: 11; elide: Text.ElideRight; maximumLineCount: 1; Layout.fillWidth: true }
                    }
                    MouseArea { 
                        width: 24; height: 24; cursorShape: Qt.PointingHandCursor; onClicked: modelData.dismiss()
                        Text { anchors.centerIn: parent; text: "close"; font.family: "Material Symbols Outlined"; color: rootShell.colorSubtext; font.pixelSize: 16 }
                    }
                }
            }
        }
    }
}
