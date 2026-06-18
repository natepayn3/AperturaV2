import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: workspaceWindow

    required property var rootShell
    readonly property var cardRef: innerPreviewCard

    screen: targetScreen
    property var targetScreen: null
    
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-workspace-preview"
    WlrLayershell.keyboardFocus: WlrLayershell.None
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    anchors { left: true; right: true; top: true; bottom: true }
    visible: innerPreviewCard.active || workspaceWindow.targetWorkspace !== -1 || rootShell.previewProgress > 0.0
    color: "transparent"

    mask: Region { 
        item: innerPreviewCard.active ? innerPreviewCard : null 
    }
    property int targetWorkspace: -1

    // 🎯 Clean outbound communication channels
    signal workspaceTargetChanged(int ws, var screenObj)
    signal dismissRequested()
    signal cancelDismissRequested()
    signal closeRequested()

    onTargetWorkspaceChanged: {
        if (targetWorkspace !== -1) {
            // Let the shell handle the preview debounce timer setup cleanly
            workspaceWindow.workspaceTargetChanged(targetWorkspace, targetScreen);
        } else {
            workspaceWindow.cancelDismissRequested();
            innerPreviewCard.targetWorkspace = -1;
        }
    }

    function commitWorkspaceChange(ws, monitorScreen) {
        if (monitorScreen) workspaceWindow.targetScreen = monitorScreen;
        workspaceWindow.targetWorkspace = ws;
    }

    function cancelDismiss() { workspaceWindow.cancelDismissRequested(); }
    function requestDismiss() { workspaceWindow.dismissRequested(); }

    WorkspacePreview {
        id: innerPreviewCard
        targetWorkspace: workspaceWindow.targetWorkspace

        onCloseRequested: {
            workspaceWindow.targetWorkspace = -1;
            workspaceWindow.closeRequested(); // 🎯 Signal the shell to run hidePreviewAnim safely
        }
        
        hoverOriginX: {
            if (rootShell.barPosition === "right") return parent.width - 44 - maxCardWidth;
            return rootShell.barPosition === "left" ? 44 : 8; 
        }
        hoverOriginY: {
            if (rootShell.barPosition === "bottom") return parent.height - 44 - maxCardHeight;
            return rootShell.barPosition === "top" ? 44 : 8; 
        }
    }
}
