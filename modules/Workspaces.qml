import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: workspaceContainer
    
    property var previewWindowInstance: null
    property var parentBarWindow: null
    property var shellTarget: null

    property bool isVertical: shellTarget ? (shellTarget.activeLayoutOrientation === "vertical") : true

    implicitWidth: isVertical ? 28 : (layoutLoader.item ? layoutLoader.item.implicitWidth : 0)
    implicitHeight: isVertical ? (layoutLoader.item ? layoutLoader.item.implicitHeight : 0) : 28

    property int activeWorkspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    property var activeWorkspaceList: [1, 2]
    property var occupiedMap: ({})

    property bool isSpecialOccupied: false
    property bool isSpecialActive: false

    function rebuildWorkspaceData() {
        let occupied = {};
        let specialHasWindows = false;
        let ids = [];

        for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
            let ws = Hyprland.workspaces.values[i];
            if (ws.id > 0) {
                occupied[ws.id] = true;
                ids.push(ws.id);
            } else if (ws.name && (ws.name.startsWith("special") || ws.id < 0)) {
                specialHasWindows = true;
            }
        }

        workspaceContainer.occupiedMap = occupied;
        workspaceContainer.isSpecialOccupied = specialHasWindows;

        if (!ids.includes(1)) ids.push(1);
        if (!ids.includes(workspaceContainer.activeWorkspace)) ids.push(workspaceContainer.activeWorkspace);

        let maxId = Math.max(...ids, 0);
        if (!ids.includes(maxId + 1)) ids.push(maxId + 1);

        for (let i = 1; i <= maxId + 1; i++) {
            if (!ids.includes(i)) ids.push(i);
        }

        ids.sort((a, b) => a - b);

        // FIX: Stripped conditional checks so the special node index is unconditionally appended
        if (!ids.includes(-99)) ids.push(-99);

        workspaceContainer.activeWorkspaceList = ids;
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { rebuildWorkspaceData(); }
    }

    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { rebuildWorkspaceData(); }
        
        function onRawEvent(event) {
            if (event.name === "activespecial" || event.name === "activespecialv2") {
                const wsName = event.data.split(',')[0];
                workspaceContainer.isSpecialActive = (wsName !== "");
                rebuildWorkspaceData();
            }
            if (event.name === "destroyworkspace") {
                rebuildWorkspaceData();
            }
        }
    }

    Component.onCompleted: rebuildWorkspaceData()

    Flickable {
        id: scrollContainer
        anchors.fill: parent
        contentWidth: isVertical ? parent.width : (layoutLoader.item ? layoutLoader.item.implicitWidth : parent.width)
        contentHeight: isVertical ? (layoutLoader.item ? layoutLoader.item.implicitHeight : parent.height) : parent.height
        flickableDirection: isVertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Loader {
            id: layoutLoader
            width: isVertical ? parent.width : implicitWidth
            height: isVertical ? implicitHeight : parent.height
            sourceComponent: workspaceContainer.isVertical ? verticalLayoutComponent : horizontalLayoutComponent
        }
    }

    Connections {
        target: workspaceContainer
        function onIsVerticalChanged() {
            layoutLoader.sourceComponent = workspaceContainer.isVertical
                ? verticalLayoutComponent
                : horizontalLayoutComponent
        }
    }

    Component {
        id: verticalLayoutComponent
        ColumnLayout {
            spacing: 10
            Repeater {
                model: workspaceContainer.activeWorkspaceList
                delegate: workspaceButtonDelegate
            }
        }
    }

    Component {
        id: horizontalLayoutComponent
        RowLayout {
            spacing: 10
            Repeater {
                model: workspaceContainer.activeWorkspaceList
                delegate: workspaceButtonDelegate
            }
        }
    }

    Component {
        id: workspaceButtonDelegate
        MouseArea {
            id: workspaceButton
            property int wsId: modelData
            property bool isSpecialNode: wsId === -99
            property bool isActive: isSpecialNode ? workspaceContainer.isSpecialActive : (workspaceContainer.activeWorkspace === wsId && !workspaceContainer.isSpecialActive)
            property bool isOccupied: isSpecialNode ? workspaceContainer.isSpecialOccupied : workspaceContainer.occupiedMap[wsId] === true
            property bool isNewIndicatorSlot: index === (workspaceContainer.activeWorkspaceList.length - 1)

            property int targetWidth: isSpecialNode ? 28 : (workspaceContainer.isVertical ? 28 : (isActive ? 58 : 28))
            property int targetHeight: isSpecialNode ? 28 : (workspaceContainer.isVertical ? (isActive ? 58 : 28) : 28)

            implicitWidth: targetWidth
            implicitHeight: targetHeight
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            Behavior on targetWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on targetHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            onEntered: {
                if (isSpecialNode) return;

                // 1. Force close the app launcher across the module boundary
                if (workspaceContainer.shellTarget && workspaceContainer.shellTarget.launcherRef) {
                    if (workspaceContainer.shellTarget.launcherRef.launcherActive) {
                        workspaceContainer.shellTarget.launcherRef.forceDismiss();
                    }
                }

                let popup = workspaceContainer.previewWindowInstance;
                if (popup) {
                    // Instantly kill the delayed dismiss timer from the previous onExited event
                    if (typeof popup.cancelDismiss === "function") {
                        popup.cancelDismiss();
                    }

                    if (isOccupied) {
                        popup.targetWorkspace = -1;
                        popup.commitWorkspaceChange(wsId, workspaceContainer.parentBarWindow ? workspaceContainer.parentBarWindow.screen : null);
                    } else {
                        if (workspaceContainer.shellTarget) {
                            workspaceContainer.shellTarget.hoveredIndicatorWorkspace = -1;
                        }
                        popup.targetWorkspace = -1;
                        popup.requestDismiss();
                    }
                }
            }

            onExited: {
                if (isSpecialNode) return;
                let popup = workspaceContainer.previewWindowInstance;
                if (popup) {
                    popup.requestDismiss();
                }
            }

            onClicked: {
                if (isSpecialNode) {
                    Hyprland.dispatch(`hl.dsp.workspace.toggle_special("magic")`);
                } else {
                    Hyprland.dispatch(`hl.dsp.focus({ workspace = "${wsId}" })`);
                }
            }

            Rectangle {
                id: hoverBackground
                width: parent.width
                height: parent.height
                radius: 6
                anchors.centerIn: parent
                color: workspaceContainer.shellTarget ? workspaceContainer.shellTarget.colorAccent : "#89b4fa"
                opacity: workspaceButton.containsMouse ? 0.3 : 0.0
                z: 1
            }

            Rectangle {
                id: indicatorShape
                anchors.centerIn: parent
                visible: !isSpecialNode
                
                property int shapeWidth: workspaceContainer.isVertical ? (workspaceButton.isActive ? 14 : 12) : (workspaceButton.isActive ? 44 : 12)
                property int shapeHeight: workspaceContainer.isVertical ? (workspaceButton.isActive ? 44 : 12) : (workspaceButton.isActive ? 14 : 12)
                
                width: shapeWidth
                height: shapeHeight
                radius: height / 2
                z: 2

                Behavior on shapeWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on shapeHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                color: {
                    if (!workspaceContainer.shellTarget) return "transparent";
                    if (workspaceButton.isActive) return workspaceContainer.shellTarget.colorAccent;
                    if (workspaceButton.isOccupied) return workspaceContainer.shellTarget.colorText;
                    return "transparent";
                }

                border.width: (!workspaceButton.isActive && !workspaceButton.isOccupied) ? 1.5 : 0
                border.color: {
                    if (!workspaceContainer.shellTarget) return "transparent";
                    return (!workspaceButton.isActive && !workspaceButton.isOccupied)
                        ? workspaceContainer.shellTarget.colorSubtext
                        : "transparent";
                }

                Text {
                    text: wsId.toString()
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: workspaceContainer.shellTarget ? workspaceContainer.shellTarget.shellFont : "Rubik"
                    font.pixelSize: 11
                    font.bold: true
                    
                    color: {
                        if (!workspaceContainer.shellTarget) return "#ffffff";
                        return workspaceButton.isActive
                            ? workspaceContainer.shellTarget.colorBackground
                            : workspaceContainer.shellTarget.colorText;
                    }
                    opacity: workspaceButton.isActive ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
            }

            Text {
                id: specialIconLayer
                visible: isSpecialNode
                anchors.centerIn: parent
                text: "star"
                
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
                font.bold: true
                z: 2
                
                font.letterSpacing: workspaceButton.isActive ? 0.01 : 0.0
                
                color: {
                    if (!workspaceContainer.shellTarget) return workspaceButton.isActive ? "#f5c2e7" : "#ffffff";
                    return workspaceButton.isActive 
                        ? workspaceContainer.shellTarget.colorAccent 
                        : workspaceContainer.shellTarget.colorText;
                }
            }
        }
    }
}
