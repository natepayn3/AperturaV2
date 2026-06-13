import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: workspacesModuleRoot

    property var shellTarget: null
    property var parentBarWindow: null
    property var previewWindowInstance: null
    
    implicitWidth: rootShell.activeLayoutOrientation === "vertical" ? 32 : (workspaceFlow.width + 8)
    implicitHeight: rootShell.activeLayoutOrientation === "vertical" ? (workspaceFlow.height + 8) : 32

    property int activeWorkspace: 1
    property var activeWorkspaceList: [1, 2]
    property var occupiedMap: ({})
    property bool isSpecialOccupied: false
    property bool isSpecialActive: false

    Process {
        id: queryWorkspaceList; command: ["hyprctl", "workspaces", "-j"]; running: rootShell.safeToLoad
        stdout: StdioCollector {
            onTextChanged: {
                try {
                    const cleaned = text.trim(); if (!cleaned || cleaned === "[]") return;
                    const json = JSON.parse(cleaned);
                    if (Array.isArray(json)) {
                        let ids = json.map(ws => ws.id).filter(id => id > 0);
                        let occupied = {}; let specialHasWindows = false;
                        json.forEach(ws => { 
                            if (ws.windows > 0) {
                                if (ws.id > 0) occupied[ws.id] = true;
                                else if (ws.name.startsWith("special") || ws.id < 0) specialHasWindows = true;
                            }
                        });
                        workspacesModuleRoot.occupiedMap = occupied; workspacesModuleRoot.isSpecialOccupied = specialHasWindows;
                        if (!ids.includes(1)) ids.push(1); if (!ids.includes(workspacesModuleRoot.activeWorkspace)) ids.push(workspacesModuleRoot.activeWorkspace);
                        let maxId = Math.max(...ids, 0); if (!ids.includes(maxId + 1)) ids.push(maxId + 1);
                        for (let i = 1; i <= maxId + 1; i++) { if (!ids.includes(i)) ids.push(i); }
                        ids.sort((a, b) => a - b);
                        if (workspacesModuleRoot.isSpecialOccupied || workspacesModuleRoot.isSpecialActive) { if (!ids.includes(-99)) ids.push(-99); }
                        workspacesModuleRoot.activeWorkspaceList = ids;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: queryActiveWorkspace; command: ["hyprctl", "activeworkspace", "-j"]; running: rootShell.safeToLoad
        stdout: StdioCollector {
            onTextChanged: {
                try {
                    const cleaned = text.trim(); if (!cleaned) return;
                    const json = JSON.parse(cleaned);
                    if (json && json.id !== undefined) {
                        workspacesModuleRoot.activeWorkspace = json.id;
                        queryWorkspaceList.running = false; queryWorkspaceList.running = true;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: querySpecialMonitorState; command: ["hyprctl", "monitors", "-j"]; running: rootShell.safeToLoad
        stdout: StdioCollector {
            onTextChanged: {
                try {
                    const cleaned = text.trim(); if (!cleaned) return;
                    const json = JSON.parse(cleaned);
                    if (Array.isArray(json)) {
                        let foundActive = false;
                        for (let i = 0; i < json.length; i++) {
                            if (json[i].focused === true) { if (json[i].specialWorkspace && json[i].specialWorkspace.id !== 0) foundActive = true; break; }
                        }
                        workspacesModuleRoot.isSpecialActive = foundActive;
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 150; running: rootShell.safeToLoad; repeat: true
        onTriggered: {
            queryActiveWorkspace.running = false; queryActiveWorkspace.running = true;
            querySpecialMonitorState.running = false; querySpecialMonitorState.running = true;
        }
    }

    Process { id: dispatchWorkspaceCmd; running: false }

    Grid {
        id: workspaceFlow; anchors.centerIn: parent; spacing: 6
        columns: rootShell.activeLayoutOrientation === "vertical" ? 1 : workspacesModuleRoot.activeWorkspaceList.length
        rows: rootShell.activeLayoutOrientation === "vertical" ? workspacesModuleRoot.activeWorkspaceList.length : 1

        Repeater {
            model: workspacesModuleRoot.activeWorkspaceList
            delegate: Item {
                id: wsButtonWrapper
                property int wsId: modelData
                property bool isSpecialNode: wsId === -99
                property bool isActive: isSpecialNode ? workspacesModuleRoot.isSpecialActive : (workspacesModuleRoot.activeWorkspace === wsId && !workspacesModuleRoot.isSpecialActive)
                property bool isOccupied: isSpecialNode ? workspacesModuleRoot.isSpecialOccupied : workspacesModuleRoot.occupiedMap[wsId] === true
                property bool isNewIndicatorSlot: (workspacesModuleRoot.isSpecialOccupied || workspacesModuleRoot.isSpecialActive) ? index === (workspacesModuleRoot.activeWorkspaceList.length - 2) : index === (workspacesModuleRoot.activeWorkspaceList.length - 1)

                property int targetWidth: isSpecialNode ? 24 : (rootShell.activeLayoutOrientation === "vertical" ? 24 : (isActive ? 48 : 24))
                property int targetHeight: isSpecialNode ? 24 : (rootShell.activeLayoutOrientation === "vertical" ? (isActive ? 48 : 24) : 24)
                implicitWidth: targetWidth; implicitHeight: targetHeight

                Behavior on targetWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on targetHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent; radius: 6
                    color: wsButtonWrapper.isActive ? rootShell.colorAccent : (wsMouseArea.containsMouse ? rootShell.colorBorder : "transparent")
                    border.color: wsButtonWrapper.isOccupied && !wsButtonWrapper.isActive ? rootShell.colorSubtext : "transparent"; border.width: 1

                    Text {
                        text: wsButtonWrapper.isNewIndicatorSlot ? "+" : wsButtonWrapper.wsId.toString()
                        font.family: rootShell.shellFont; font.pixelSize: wsButtonWrapper.isNewIndicatorSlot ? 14 : 11; font.bold: true
                        color: wsButtonWrapper.isActive ? "#11111b" : (wsButtonWrapper.isOccupied ? rootShell.colorText : rootShell.colorSubtext)
                        anchors.centerIn: parent; visible: !wsButtonWrapper.isSpecialNode; anchors.verticalCenterOffset: wsButtonWrapper.isNewIndicatorSlot ? -1 : 0
                    }
                    Text { text: "star"; font.family: "Material Icons"; font.pixelSize: 14; color: wsButtonWrapper.isActive ? "#11111b" : rootShell.colorAccent; anchors.centerIn: parent; visible: wsButtonWrapper.isSpecialNode }

                    MouseArea {
                        id: wsMouseArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (wsButtonWrapper.isSpecialNode || !wsButtonWrapper.isOccupied || !previewWindowInstance) return;
                            let globalCoords = wsMouseArea.mapToItem(null, 0, 0);
                            previewWindowInstance.cancelDismiss();
                            if (rootShell.activeLayoutOrientation === "vertical") {
                                previewWindowInstance.marginLeft = rootShell.barPosition === "left" ? 54 : (parentBarWindow ? parentBarWindow.x - 332 : 0);
                                previewWindowInstance.marginTop = globalCoords.y - (200 / 2) + 12;
                            } else {
                                previewWindowInstance.marginLeft = globalCoords.x - (320 / 2) + 12;
                                previewWindowInstance.marginTop = rootShell.barPosition === "top" ? 54 : (parentBarWindow ? parentBarWindow.y - 212 : 0);
                            }
                            Qt.callLater(function() { previewWindowInstance.targetWorkspace = wsButtonWrapper.wsId; });
                        }
                        onExited: { if (previewWindowInstance) previewWindowInstance.requestDismiss(); }
                        onClicked: {
                            if (wsButtonWrapper.isSpecialNode) dispatchWorkspaceCmd.command = ["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special(\"magic\")"];
                            else dispatchWorkspaceCmd.command = ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + wsButtonWrapper.wsId + "\" })"];
                            dispatchWorkspaceCmd.running = false; dispatchWorkspaceCmd.running = true;
                        }
                    }
                }
            }
        }
    }
}
