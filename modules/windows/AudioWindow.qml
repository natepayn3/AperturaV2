import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: audioWindow
    
    required property var rootShell
    property bool audioActive: false
    readonly property var cardRef: innerAudioCard

    screen: Quickshell.screens[0] 
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-audio-preview"
    WlrLayershell.keyboardFocus: audioActive ? WlrLayershell.OnDemand : WlrLayershell.None
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    anchors { left: true; right: true; top: true; bottom: true }
    visible: audioActive || rootShell.audioProgress > 0.0
    color: "transparent"

    property int hoverOriginX: 0
    property int hoverOriginY: 0

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        enabled: audioWindow.audioActive
        onPressed: (mouse) => {
            audioWindow.forceDismiss();
            mouse.accepted = false;
        }
    }

    function showAudio() { 
        if (!audioActive) {
            rootShell.closeAllPopups();
            rootShell.audioDismissTimer.stop(); 
            audioActive = true; 
            showAudioAnim.restart();
            innerAudioCard.forceActiveFocus();
        }
    }
    
    function forceDismiss() {
        audioActive = false;
        hideAudioAnim.restart();
    }

    Shortcut {
        sequence: "Escape"
        enabled: audioWindow.audioActive
        onActivated: audioWindow.forceDismiss()
    }

    ParallelAnimation {
        id: showAudioAnim
        NumberAnimation { target: rootShell; property: "audioProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideAudioAnim
        NumberAnimation { target: rootShell; property: "audioProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: audioWindow; property: "audioActive"; value: false }
    }

    Audio {
        id: innerAudioCard
        active: audioWindow.audioActive
        hoverOriginX: audioWindow.hoverOriginX
        hoverOriginY: audioWindow.hoverOriginY
    }
}
