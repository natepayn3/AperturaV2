import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Rectangle {
    id: previewContainer
    
    property var workspaceWindows: Hyprland.toplevels.values.filter(t => t.lastIpcObject && t.lastIpcObject.workspace && t.lastIpcObject.workspace.id === globalWorkspacePreview.targetWorkspace)
    
    property var calculatedBounds: {
        if (workspaceWindows.length === 0) {
            return { "w": 1920, "h": 1080, "isVertical": false, "originX": 0, "originY": 0 };
        }
        let minX = Infinity, minY = Infinity;
        let maxX = -Infinity, maxY = -Infinity;
        
        for (let i = 0; i < workspaceWindows.length; i++) {
            let ipc = workspaceWindows[i].lastIpcObject;
            if (!ipc || !ipc.at || !ipc.size) continue;
            if (ipc.at[0] < minX) minX = ipc.at[0];
            if (ipc.at[1] < minY) minY = ipc.at[1];
            if ((ipc.at[0] + ipc.size[0]) > maxX) maxX = ipc.at[0] + ipc.size[0];
            if ((ipc.at[1] + ipc.size[1]) > maxY) maxY = ipc.at[1] + ipc.size[1];
        }
        
        let spanX = maxX - minX;
        let spanY = maxY - minY;
        let verticalDetected = spanY > spanX;
        
        let normW = verticalDetected ? 1080 : (workspaceWindows.length > 2 ? 2880 : 1920);
        let normH = verticalDetected ? 1920 : 1080;
        
        if (spanX > 0 && Math.abs(spanX - normW) > 100) normW = spanX;
        if (spanY > 0 && Math.abs(spanY - normH) > 100) normH = spanY;
        
        return { "w": normW, "h": normH, "isVertical": verticalDetected, "originX": minX, "originY": minY };
    }

    width: calculatedBounds.isVertical ? 240 : (workspaceWindows.length > 2 ? 480 : 320)
    height: calculatedBounds.isVertical ? 380 : 200
    
    color: rootShell.colorBackground
    border.color: rootShell.colorBorder
    border.width: 2
    radius: 12
    clip: true

    MouseArea { 
        anchors.fill: parent 
        hoverEnabled: true 
        onEntered: globalWorkspacePreview.cancelDismiss()
        onExited: globalWorkspacePreview.requestDismiss() 
    }

    Text { 
        id: popupTitle
        text: "Workspace " + globalWorkspacePreview.targetWorkspace
        font.family: rootShell.shellFont
        font.pixelSize: 13
        font.bold: true
        color: rootShell.colorAccent
        x: 14; y: 10 
    }

    Rectangle { 
        id: dividerLine
        width: parent.width - 28; height: 1
        color: rootShell.colorBorder
        x: 14; y: 30 
    }

    Rectangle {
        id: viewportFrame
        anchors.top: dividerLine.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        
        width: Math.round(height * (previewContainer.calculatedBounds.w / previewContainer.calculatedBounds.h))
        color: Qt.rgba(0, 0, 0, 0.2)
        radius: 4
        clip: true

        property real scaleX: width / previewContainer.calculatedBounds.w
        property real scaleY: height / previewContainer.calculatedBounds.h

        Repeater {
            model: previewContainer.workspaceWindows

            delegate: Rectangle {
                property var ipc: modelData.lastIpcObject
                
                x: (ipc && ipc.at ? (ipc.at[0] - previewContainer.calculatedBounds.originX) : 0) * viewportFrame.scaleX
                y: (ipc && ipc.at ? (ipc.at[1] - previewContainer.calculatedBounds.originY) : 0) * viewportFrame.scaleY
                width: Math.max(4, (ipc && ipc.size ? ipc.size[0] : 0) * viewportFrame.scaleX)
                height: Math.max(4, (ipc && ipc.size ? ipc.size[1] : 0) * viewportFrame.scaleY)

                color: Qt.rgba(0, 0, 0, 0.6)
                border.color: rootShell.colorBorder
                border.width: 1
                radius: 2

                Loader {
                    anchors.fill: parent
                    active: modelData.wayland !== null
                    sourceComponent: ScreencopyView { 
                        captureSource: modelData.wayland
                        live: true
                        paintCursor: false
                        onCaptureSourceChanged: { if (captureSource) { rootShell.safeToLoad = rootShell.safeToLoad } }
                    }
                }
            }
        }
    }
}
