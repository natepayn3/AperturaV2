import QtQuick
import Quickshell
import Quickshell.Wayland
import "../" // Step up to access core modules like Dashboard

PanelWindow {
    id: dashboardWindow

    required property var rootShell
    property bool dashboardActive: false

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dashboard-preview"
    WlrLayershell.keyboardFocus: WlrLayershell.None 
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    anchors { left: true; right: true; top: true; bottom: true }
    visible: dashboardActive || rootShell.dashboardProgress > 0.0
    color: "transparent"

    mask: Region { 
        item: innerDashboardCard.active ? innerDashboardCard : null 
    }

    function cancelDismiss() { dashboardDismissTimer.stop(); }
    function requestDismiss() { dashboardDismissTimer.restart(); }

    function showDashboard() { 
        if (!dashboardActive) {
            rootShell.closeAllPopups();
            cancelDismiss();
            dashboardActive = true; 
            showDashboardAnim.restart(); 
        }
    }
    
    function forceDismiss() { 
        dashboardActive = false; 
        hideDashboardAnim.restart(); 
    }

    Timer {
        id: dashboardDismissTimer
        interval: 200 
        running: false
        repeat: false
        onTriggered: {
            if (!innerDashboardCard.isHovered) {
                dashboardWindow.forceDismiss();
            }
        }
    }

    ParallelAnimation {
        id: showDashboardAnim
        NumberAnimation { target: rootShell; property: "dashboardProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideDashboardAnim
        NumberAnimation { target: rootShell; property: "dashboardProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: dashboardWindow; property: "dashboardActive"; value: false }
    }

    Dashboard {
        id: innerDashboardCard
        active: dashboardWindow.dashboardActive
    }
}
