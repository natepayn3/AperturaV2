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

    // Baseline grid footprint
    implicitWidth: isVertical ? 32 : (layoutLoader.item ? layoutLoader.item.implicitWidth : 0)
    implicitHeight: isVertical ? (layoutLoader.item ? layoutLoader.item.implicitHeight : 0) : 32

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

    // Unified Subtle Module Background Container Card
    Rectangle {
        id: wholeModuleBackground
        anchors.fill: parent
        radius: 8
        // Uses a tight white overlay tint over your theme bar to stay light and clean
        color: Qt.rgba(1, 1, 1, 0.03)
        border.width: 0
        border.color: workspaceContainer.shellTarget ? workspaceContainer.shellTarget.colorBorder : "transparent"
        z: 0
    }

    Flickable {
        id: scrollContainer
        anchors.fill: parent
        contentWidth: isVertical ? parent.width : (layoutLoader.item ? layoutLoader.item.implicitWidth : parent.width)
        contentHeight: isVertical ? (layoutLoader.item ? layoutLoader.item.implicitHeight : parent.height) : parent.height
        flickableDirection: isVertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        z: 1

        Loader {
            id: layoutLoader
            width: isVertical ? parent.width : implicitWidth
            height: isVertical ? implicitHeight : parent.height
            
            // 🎯 FIX: Forces the loader box canvas to lock strictly to the horizontal midpoint axis
            anchors.horizontalCenter: isVertical ? parent.horizontalCenter : undefined
            anchors.verticalCenter: !isVertical ? parent.verticalCenter : undefined
            
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
            spacing: 4
            anchors.centerIn: parent 
            Repeater {
                model: workspaceContainer.activeWorkspaceList
                delegate: workspaceButtonDelegate
            }
        }
    }

    Component {
        id: horizontalLayoutComponent
        RowLayout {
            spacing: 4
            anchors.centerIn: parent 
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
            
            property int targetWidth: isSpecialNode ? 32 : (workspaceContainer.isVertical ? 32 : (isActive ? 54 : 32))
            property int targetHeight: isSpecialNode ? 32 : (workspaceContainer.isVertical ? (isActive ? 54 : 32) : 32)

            implicitWidth: targetWidth
            implicitHeight: targetHeight
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true

            Behavior on targetWidth { NumberAnimation { duration: 180; easing.type: Easing.OutExpo } }
            Behavior on targetHeight { NumberAnimation { duration: 180; easing.type: Easing.OutExpo } }

            onEntered: {
                if (isSpecialNode) return;
                if (workspaceContainer.shellTarget && workspaceContainer.shellTarget.launcherRef) {
                    if (workspaceContainer.shellTarget.launcherRef.launcherActive) {
                        workspaceContainer.shellTarget.launcherRef.forceDismiss();
                    }
                }

                let popup = workspaceContainer.previewWindowInstance;
                if (popup) {
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

            // 🎨 FIX: Pure white highlight sheen that lightens your translucent bar into the perfect slate-blue from image_5a6dbf.png
            Rectangle {
                id: hoverBackground
                anchors.fill: parent
                radius: 6
                color: workspaceButton.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                z: 1
            }

            // --- Unified Standard Node Rendering Canvas ---
            Rectangle {
                id: indicatorShape
                anchors.centerIn: parent
                visible: !isSpecialNode
                
                property int shapeWidth: workspaceContainer.isVertical ? (workspaceButton.isActive ? 8 : 8) : (workspaceButton.isActive ? 38 : 8)
                property int shapeHeight: workspaceContainer.isVertical ? (workspaceButton.isActive ? 38 : 8) : (workspaceButton.isActive ? 8 : 8)
                
                width: shapeWidth
                height: shapeHeight
                radius: height / 2
                z: 2

                Behavior on shapeWidth { NumberAnimation { duration: 180; easing.type: Easing.OutExpo } }
                Behavior on shapeHeight { NumberAnimation { duration: 180; easing.type: Easing.OutExpo } }

                color: {
                    if (!workspaceContainer.shellTarget) return "#ffffff";
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
            }

            // --- Star Layer Icon Section ---
            Text {
                id: specialIconLayer
                visible: isSpecialNode
                anchors.centerIn: parent
                text: "star"
                
                font.family: "Material Symbols Outlined"
                font.pixelSize: workspaceButton.isActive ? 18 : 14
                font.bold: true
                z: 2
                
                color: {
                    if (!workspaceContainer.shellTarget) return workspaceButton.isActive ? "#f5c2e7" : "#ffffff";
                    return workspaceButton.isActive 
                        ? workspaceContainer.shellTarget.colorAccent 
                        : workspaceContainer.shellTarget.colorText;
                }
                
                Behavior on font.pixelSize { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            }
        }
    }
}
