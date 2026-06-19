import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: calendarWindow
    
    required property var rootShell
    property bool calendarActive: false
    readonly property var cardRef: innerCalendarCard

    // 🎯 Define explicit outbound signals
    signal calendarShowRequested()
    signal dismissRequested()

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-calendar-preview"
    WlrLayershell.keyboardFocus: calendarActive ? WlrLayershell.OnDemand : WlrLayershell.None
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    anchors { left: true; right: true; top: true; bottom: true }
    visible: calendarActive || rootShell.calendarProgress > 0.0
    color: "transparent"

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        enabled: calendarWindow.calendarActive
        onPressed: function(mouse) {
            calendarWindow.forceDismiss();
            mouse.accepted = false; 
        }
    }

    function showCalendar() { calendarWindow.calendarShowRequested(); }
    // 🎯 Notify the shell to run the closing animation path instead of mutating state instantly
    function forceDismiss() { calendarWindow.dismissRequested(); }

    Shortcut {
        sequence: "Escape"
        enabled: calendarWindow.calendarActive
        onActivated: calendarWindow.forceDismiss()
    }

    Calendar {
        id: innerCalendarCard
        active: calendarWindow.calendarActive

        hoverOriginX: {
            if (rootShell.barPosition === "right") return parent.width - 44 - innerCalendarCard.maxCardWidth;
            return rootShell.barPosition === "left" ? 46 : 10; 
        }
        hoverOriginY: {
            if (rootShell.barPosition === "bottom") return parent.height - 46 - innerCalendarCard.maxCardHeight;
            return rootShell.barPosition === "top" ? 46 : 10; 
        }
    }
}
