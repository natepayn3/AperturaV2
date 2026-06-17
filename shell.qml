import QtQuick
import QtQuick.Layouts
import QtQuick.Controls 
import QtQuick.Shapes 
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "modules"
import "modules/bars"

Scope {
    id: rootShell

    // --- Global References for External Modules ---
    readonly property var clockRef: clockTimer
    readonly property var settingsAppRef: settingsAppInstance
    readonly property var calendarRef: globalCalendarPreview
    readonly property var launcherRef: globalAppLauncherPreview
    readonly property var workspaceRef: globalWorkspacePreview
    readonly property var bluetoothRef: globalBluetoothPreview

    property string barPosition: "left"
    property string enabledDisplayStr: "0"
    
    property string colorBackground: "#cc11111b"
    property string colorBorder: "#313244"
    property string colorAccent: "#89b4fa"
    property string colorText: "#cdd6f4"
    property string colorSubtext: "#a6adc8"
    property string colorClose: "#f38ba8"

    property string targetPosition: "left"
    property string activeLayoutOrientation: "vertical"
    property bool safeToLoad: false

    property string customBasePath: ""
    property string configFilePath: ""
    property string matugenFilePath: ""

    property real verticalBarProgress: 1.0
    property real horizontalBarProgress: 0.0

    property real verticalFrameProgress: 1.0
    property real horizontalFrameProgress: 0.0

    property string shellFont: "Rubik"

    property real previewProgress: 0.0
    property real calendarProgress: 0.0
    property real launcherProgress: 0.0
    property real bluetoothProgress: 0.0

    readonly property var audioRef: globalAudioPreview
    property real audioProgress: 0.0

    readonly property var wifiRef: globalWifiPreview
    property real wifiProgress: 0.0

    onBarPositionChanged: saveConfig()
    onEnabledDisplayStrChanged: saveConfig()
    onShellFontChanged: saveConfig()

    SequentialAnimation {
        id: orientationAnim
        ParallelAnimation {
            NumberAnimation { target: rootShell; property: "verticalBarProgress"; to: 0.0; duration: 100; easing.type: Easing.InCubic }
            NumberAnimation { target: rootShell; property: "horizontalBarProgress"; to: 0.0; duration: 100; easing.type: Easing.InCubic }
            NumberAnimation { target: rootShell; property: "verticalFrameProgress"; to: 0.0; duration: 150; easing.type: Easing.InQuad }
            NumberAnimation { target: rootShell; property: "horizontalFrameProgress"; to: 0.0; duration: 150; easing.type: Easing.OutQuad }
        }
        PauseAnimation { duration: 40 }
        ParallelAnimation {
            PropertyAction { target: rootShell; property: "barPosition"; value: rootShell.targetPosition }
            PropertyAction { target: rootShell; property: "activeLayoutOrientation"; value: (rootShell.targetPosition === "left" || rootShell.targetPosition === "right") ? "vertical" : "horizontal" }
        }
        ScriptAction {
            script: {
                if (rootShell.activeLayoutOrientation === "vertical") {
                    expandVerticalBar.restart()
                    expandVerticalFrame.restart()
                } else {
                    expandHorizontalBar.restart()
                    expandHorizontalFrame.restart()
                }
            }
        }
    }

    NumberAnimation { id: expandVerticalBar; target: rootShell; property: "verticalBarProgress"; to: 1.0; duration: 120; easing.type: Easing.OutCubic }
    NumberAnimation { id: expandHorizontalBar; target: rootShell; property: "horizontalBarProgress"; to: 1.0; duration: 120; easing.type: Easing.OutCubic }
    NumberAnimation { id: expandVerticalFrame; target: rootShell; property: "verticalFrameProgress"; to: 1.0; duration: 150; easing.type: Easing.OutQuad }
    NumberAnimation { id: expandHorizontalFrame; target: rootShell; property: "horizontalFrameProgress"; to: 1.0; duration: 150; easing.type: Easing.OutQuad }

    ParallelAnimation {
        id: showPreviewAnim
        NumberAnimation { target: rootShell; property: "previewProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hidePreviewAnim
        NumberAnimation { target: rootShell; property: "previewProgress"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
        PropertyAction { target: globalWorkspacePreview; property: "targetWorkspace"; value: -1 }
    }

    ParallelAnimation {
        id: showCalendarAnim
        NumberAnimation { target: rootShell; property: "calendarProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideCalendarAnim
        NumberAnimation { target: rootShell; property: "calendarProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalCalendarPreview; property: "calendarActive"; value: false }
    }

    ParallelAnimation {
        id: showLauncherAnim
        NumberAnimation { target: rootShell; property: "launcherProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideLauncherAnim
        NumberAnimation { target: rootShell; property: "launcherProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalAppLauncherPreview; property: "launcherActive"; value: false }
    }

    ParallelAnimation {
        id: showBluetoothAnim
        NumberAnimation { target: rootShell; property: "bluetoothProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideBluetoothAnim
        NumberAnimation { target: rootShell; property: "bluetoothProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalBluetoothPreview; property: "bluetoothActive"; value: false }
    }

    ParallelAnimation {
        id: showAudioAnim
        NumberAnimation { target: rootShell; property: "audioProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideAudioAnim
        NumberAnimation { target: rootShell; property: "audioProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalAudioPreview; property: "audioActive"; value: false }
    }

    ParallelAnimation {
        id: showWifiAnim
        NumberAnimation { target: rootShell; property: "wifiProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideWifiAnim
        NumberAnimation { target: rootShell; property: "wifiProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalWifiPreview; property: "wifiActive"; value: false }
    }

    function triggerOrientationChange(newEdge) {
        if (barPosition === newEdge) return;
        targetPosition = newEdge;
        orientationAnim.restart();
    }

    function closeAllPopups() {
        if (globalCalendarPreview.calendarActive) globalCalendarPreview.forceDismiss();
        if (globalBluetoothPreview.bluetoothActive) globalBluetoothPreview.forceDismiss();
        if (globalAudioPreview.audioActive) globalAudioPreview.forceDismiss();
        if (globalWifiPreview.wifiActive) globalWifiPreview.forceDismiss();
        
        if (globalAppLauncherPreview.active) globalAppLauncherPreview.active = false;
        if (settingsAppInstance.windowVisible) settingsAppInstance.windowVisible = false;
    }

    function isDisplayEnabled(idx) {
        let items = enabledDisplayStr.split(",");
        return items.indexOf(String(idx)) !== -1;
    }

    function toggleDisplay(idx) {
        if (!safeToLoad) return;
        let items = enabledDisplayStr.split(",").filter(x => x.trim() !== "");
        let sIdx = String(idx);
        if (items.indexOf(sIdx) !== -1) { 
            if (items.length > 1) items.splice(items.indexOf(sIdx), 1); 
        } else { 
            items.push(sIdx); 
        }
        enabledDisplayStr = items.join(",");
        settingsAppInstance.updateDisplaysFromShell();
    }

    function saveConfig() {
        if (!safeToLoad || !configFilePath) return;
        let configObj = {
            "position": barPosition,
            "enabledDisplays": enabledDisplayStr,
            "font": shellFont
        };
        saveConfigProc.command = ["sh", "-c", "echo '" + JSON.stringify(configObj) + "' > " + configFilePath];
        saveConfigProc.running = true;
    }

    function parseConfig(rawJson) {
        if (!rawJson || rawJson.trim() === "") return;
        try {
            let parsed = JSON.parse(rawJson);
            if (parsed.position !== undefined) {
                barPosition = parsed.position; 
                targetPosition = parsed.position; 
                activeLayoutOrientation = (parsed.position === "left" || parsed.position === "right") ? "vertical" : "horizontal";
                if (activeLayoutOrientation === "vertical") {
                    verticalBarProgress = 1.0
                    verticalFrameProgress = 1.0
                    horizontalBarProgress = 0.0
                    horizontalFrameProgress = 0.0
                } else {
                    verticalBarProgress = 0.0
                    verticalFrameProgress = 0.0
                    horizontalBarProgress = 1.0
                    horizontalFrameProgress = 1.0
                }
            }
            if (parsed.enabledDisplays !== undefined) enabledDisplayStr = parsed.enabledDisplays;
            if (parsed.font !== undefined) shellFont = parsed.font;
        } catch (e) {}
    }

    function parseMatugen(rawJson) {
        if (!rawJson || rawJson.trim() === "") return;
        try {
            let parsed = JSON.parse(rawJson);
            if (parsed.colors.background !== undefined) colorBackground = parsed.colors.background;
            if (parsed.colors.border !== undefined) colorBorder = parsed.colors.border;
            if (parsed.colors.accent !== undefined) colorAccent = parsed.colors.accent;
            if (parsed.colors.text !== undefined) colorText = parsed.colors.text;
            if (parsed.colors.subtext !== undefined) colorSubtext = parsed.colors.subtext;
            if (parsed.colors.close !== undefined) colorClose = parsed.colors.close;
        } catch (e) {}
    }

    Process {
        id: startupConfigLoader
        running: false
        stdout: StdioCollector { onTextChanged: { parseConfig(text); rootShell.safeToLoad = true; } }
    }

    Process {
        id: saveConfigProc
        running: false
    }

    Component.onCompleted: {
        const localUri = Qt.resolvedUrl(".").toString();
        rootShell.customBasePath = localUri.replace("file://", "").trim();
        rootShell.configFilePath = rootShell.customBasePath + "/shell_settings.json";
        rootShell.matugenFilePath = rootShell.customBasePath + "/matugen.json";
        startupConfigLoader.command = ["cat", rootShell.configFilePath]; 
        startupConfigLoader.running = true;
        readMatugenProc.command = ["cat", rootShell.matugenFilePath]; 
        readMatugenProc.running = true;
    }

    Process { 
        id: readMatugenProc
        running: false
        property string output: ""
        stdout: StdioCollector { onTextChanged: { readMatugenProc.output = text; parseMatugen(text); } }
    }

    // --- Core Engine Window State Cross-Trackers ---
    Connections {
        target: settingsAppInstance
        ignoreUnknownSignals: true
        function onWindowVisibleChanged() {
            if (settingsAppInstance.windowVisible) {
                if (globalAppLauncherPreview.active) globalAppLauncherPreview.active = false;
                if (globalCalendarPreview.calendarActive) globalCalendarPreview.forceDismiss();
                if (globalBluetoothPreview.bluetoothActive) globalBluetoothPreview.forceDismiss();
                if (globalAudioPreview.audioActive) globalAudioPreview.forceDismiss();
            }
        }
    }

    Connections {
        target: globalAppLauncherPreview
        ignoreUnknownSignals: true
        function onActiveChanged() {
            if (globalAppLauncherPreview.active) {
                if (settingsAppInstance.windowVisible) settingsAppInstance.windowVisible = false;
                if (globalCalendarPreview.calendarActive) globalCalendarPreview.forceDismiss();
                if (globalBluetoothPreview.bluetoothActive) globalBluetoothPreview.forceDismiss();
                if (globalAudioPreview.audioActive) globalAudioPreview.forceDismiss();
            }
        }
    }

    Connections {
        target: globalWifiPreview
        ignoreUnknownSignals: true
        function onWifiActiveChanged() {
            if (globalWifiPreview.wifiActive) {
                if (settingsAppInstance.windowVisible) settingsAppInstance.windowVisible = false;
                if (globalAppLauncherPreview.active) globalAppLauncherPreview.active = false;
                if (globalCalendarPreview.calendarActive) globalCalendarPreview.forceDismiss();
                if (globalBluetoothPreview.bluetoothActive) globalBluetoothPreview.forceDismiss();
                if (globalAudioPreview.audioActive) globalAudioPreview.forceDismiss();
            }
        }
    }

    // --- Input Processing Interfaces ---
    IpcHandler {
        target: "settings"
        function toggle(): void {
            if (settingsAppInstance) {
                settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible;
            }
        }
    }
    
    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (globalAppLauncherPreview) {
                globalAppLauncherPreview.active = !globalAppLauncherPreview.active;
            }
        }
    }

    IpcHandler {
        target: "audio"
        function updateVolume(): void {
            if (globalAudioPreview && globalAudioPreview.cardRef) {
                globalAudioPreview.cardRef.showOsd();
            }
        }
    }

    SettingsApp { id: settingsAppInstance; shellTarget: rootShell }

    Timer { 
        id: clockTimer
        interval: 1000
        running: true
        repeat: true
        property var currentTime: new Date()
        onTriggered: currentTime = new Date() 
    }

    Timer {
        id: calendarDismissTimer
        interval: 150
        running: false
        repeat: false
        onTriggered: {
            if (!innerCalendarCard.isHovered) {
                hideCalendarAnim.restart();
            }
        }
    }

    Timer {
        id: bluetoothDismissTimer
        interval: 150
        running: false
        repeat: false
        onTriggered: {
            if (!innerBluetoothCard.isHovered) {
                hideBluetoothAnim.restart();
            }
        }
    }

    Timer {
        id: audioDismissTimer
        interval: 150
        running: false
        repeat: false
        onTriggered: {
            if (!innerAudioCard.isHovered) {
                hideAudioAnim.restart();
            }
        }
    }

    property int hoveredIndicatorWorkspace: -1

    Timer {
        id: previewDebounceTimer
        interval: 50
        running: false
        repeat: false
        property int pendingWorkspace: -1
        onTriggered: {
            if (pendingWorkspace !== -1) {
                innerPreviewCard.targetWorkspace = pendingWorkspace;
            }
        }
    }

    Timer {
        id: dismissTimer
        interval: 100
        running: false
        repeat: false
        onTriggered: {
            hoveredIndicatorWorkspace = -1;
            innerPreviewCard.targetWorkspace = -1;
        }
    }

    // --- Global Popup Instances ---
    PanelWindow {
        id: globalWorkspacePreview

        screen: targetScreen
        property var targetScreen: null
        
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-workspace-preview"
        WlrLayershell.keyboardFocus: WlrLayershell.None
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        visible: innerPreviewCard.active || globalWorkspacePreview.targetWorkspace !== -1 || rootShell.previewProgress > 0.0
        color: "transparent"

        mask: Region { 
            item: innerPreviewCard.active ? innerPreviewCard : null 
        }
        property int targetWorkspace: -1

        onTargetWorkspaceChanged: {
            if (targetWorkspace !== -1) {
                if (targetWorkspace === innerPreviewCard.targetWorkspace) {
                    previewDebounceTimer.stop();
                    return; 
                }
                previewDebounceTimer.pendingWorkspace = targetWorkspace;
                previewDebounceTimer.restart();
            } else {
                previewDebounceTimer.stop();
                innerPreviewCard.targetWorkspace = -1;
            }
        }

        function commitWorkspaceChange(ws, monitorScreen) {
            dismissTimer.stop();
            if (monitorScreen) globalWorkspacePreview.targetScreen = monitorScreen;
            hoveredIndicatorWorkspace = ws;
            globalWorkspacePreview.targetWorkspace = ws;
            showPreviewAnim.restart();
        }

        function cancelDismiss() { dismissTimer.stop(); previewDebounceTimer.stop(); }
        function requestDismiss() { dismissTimer.restart(); }

        WorkspacePreview {
            id: innerPreviewCard
            targetWorkspace: globalWorkspacePreview.targetWorkspace

            onCloseRequested: {
                globalWorkspacePreview.targetWorkspace = -1;
                hidePreviewAnim.restart();
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

    AppLauncher { id: globalAppLauncherPreview }

    PanelWindow {
        id: globalCalendarPreview
        property bool calendarActive: false
        
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
            enabled: globalCalendarPreview.calendarActive
            
            onPressed: (mouse) => {
                globalCalendarPreview.forceDismiss();
                mouse.accepted = false; 
            }
        }

        function showCalendar() { 
            if (!calendarActive) {
                closeAllPopups();
                calendarActive = true; 
                showCalendarAnim.restart(); 
            }
        }
        function forceDismiss() { calendarActive = false; hideCalendarAnim.restart(); }

        Shortcut {
            sequence: "Escape"
            enabled: globalCalendarPreview.calendarActive
            onActivated: globalCalendarPreview.forceDismiss()
        }

        CalendarPopup {
            id: innerCalendarCard
            active: globalCalendarPreview.calendarActive

            hoverOriginX: {
                if (rootShell.barPosition === "right") return parent.width - 44 - maxCardWidth;
                return rootShell.barPosition === "left" ? 46 : 10; 
            }
            hoverOriginY: {
                if (rootShell.barPosition === "bottom") return parent.height - 44 - maxCardHeight;
                return rootShell.barPosition === "top" ? 46 : 10; 
            }
        }
    }

    PanelWindow {
        id: globalAudioPreview
        property bool audioActive: false
        property alias cardRef: innerAudioCard

        screen: Quickshell.screens[0] 
        
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-audio-preview"
        WlrLayershell.keyboardFocus: globalAudioPreview.audioActive ? WlrLayershell.OnDemand : WlrLayershell.None
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        visible: audioActive || rootShell.audioProgress > 0.0
        color: "transparent"

        property int hoverOriginX: 0
        property int hoverOriginY: 0

        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            enabled: globalAudioPreview.audioActive
            
            onPressed: (mouse) => {
                globalAudioPreview.forceDismiss();
                mouse.accepted = false;
            }
        }

        function showAudio() { 
            if (!audioActive) {
                closeAllPopups();
                audioDismissTimer.stop(); 
                audioActive = true; 
                showAudioAnim.restart();
                innerAudioCard.forceActiveFocus();
            }
        }
        
        function requestDismiss() { }
        
        function forceDismiss() {
            audioActive = false;
            hideAudioAnim.restart();
        }

        Shortcut {
            sequence: "Escape"
            enabled: globalAudioPreview.audioActive
            onActivated: globalAudioPreview.forceDismiss()
        }

        Audio {
            id: innerAudioCard
            active: globalAudioPreview.audioActive
            hoverOriginX: globalAudioPreview.hoverOriginX
            hoverOriginY: globalAudioPreview.hoverOriginY
        }
    }

    PanelWindow {
        id: globalBluetoothPreview
        property bool bluetoothActive: false
        property alias cardRef: innerBluetoothCard

        screen: Quickshell.screens[0]
        
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-bluetooth-preview"
        WlrLayershell.keyboardFocus: globalBluetoothPreview.bluetoothActive ? WlrLayershell.OnDemand : WlrLayershell.None
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        visible: bluetoothActive || rootShell.bluetoothProgress > 0.0
        color: "transparent"

        property int hoverOriginX: 0
        property int hoverOriginY: 0

        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            enabled: globalBluetoothPreview.bluetoothActive
            
            onPressed: (mouse) => {
                globalBluetoothPreview.forceDismiss();
                mouse.accepted = false;
            }
        }

        function showBluetooth() { 
            if (!bluetoothActive) {
                closeAllPopups();
                bluetoothDismissTimer.stop(); 
                bluetoothActive = true; 
                showBluetoothAnim.restart();
                innerBluetoothCard.forceActiveFocus();
            }
        }
        
        function requestDismiss() { }
        
        function forceDismiss() {
            bluetoothActive = false;
            hideBluetoothAnim.restart();
        }

        Shortcut {
            sequence: "Escape"
            enabled: globalBluetoothPreview.bluetoothActive
            onActivated: globalBluetoothPreview.forceDismiss()
        }

        Bluetooth {
            id: innerBluetoothCard
            active: globalBluetoothPreview.bluetoothActive
            hoverOriginX: globalBluetoothPreview.hoverOriginX
            hoverOriginY: globalBluetoothPreview.hoverOriginY
        }
    }

    PanelWindow {
        id: globalWifiPreview
        property bool wifiActive: false
        property alias cardRef: innerWifiCard

        screen: Quickshell.screens[0]
        
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-wifi-preview"
        WlrLayershell.keyboardFocus: globalWifiPreview.wifiActive ? WlrLayershell.OnDemand : WlrLayershell.None
        WlrLayershell.exclusionMode: WlrLayershell.Ignore



        anchors { left: true; right: true; top: true; bottom: true }
        visible: wifiActive || rootShell.wifiProgress > 0.0
        color: "transparent"

        property int hoverOriginX: 0
        property int hoverOriginY: 0

        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            enabled: globalWifiPreview.wifiActive
            
            onPressed: (mouse) => {
                globalWifiPreview.forceDismiss();
                mouse.accepted = false;
            }
        }

        function showWifi() { 
            if (!wifiActive) {
                closeAllPopups();
                wifiActive = true; 
                showWifiAnim.restart();
                innerWifiCard.forceActiveFocus();
            }
        }
        
        function forceDismiss() {
            wifiActive = false;
            hideWifiAnim.restart();
        }

        Shortcut {
            sequence: "Escape"
            enabled: globalWifiPreview.wifiActive
            onActivated: globalWifiPreview.forceDismiss()
        }

        Wifi {
            id: innerWifiCard
            active: globalWifiPreview.wifiActive
            
            MouseArea {
                anchors.fill: parent
                onPressed: (event) => event.accepted = true
                onClicked: (event) => event.accepted = true
            }

            hoverOriginX: globalWifiPreview.hoverOriginX
            hoverOriginY: globalWifiPreview.hoverOriginY
        }
    }

    // --- Dynamic Instantiators using Unified Modules ---
    Item {
        id: globalCtx
        property var ref: rootShell
    }

    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: VerticalBar { 
            targetScreen: modelData; edge: "left"; rootShell: globalCtx.ref
            visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "left" && globalCtx.ref.verticalBarProgress > 0.0 
        } 
    }
    
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: VerticalBar { 
            targetScreen: modelData; edge: "right"; rootShell: globalCtx.ref
            visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "right" && globalCtx.ref.verticalBarProgress > 0.0 
        } 
    }
    
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: HorizontalBar { 
            targetScreen: modelData; edge: "top"; rootShell: globalCtx.ref
            visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "top" && globalCtx.ref.horizontalBarProgress > 0.0 
        } 
    }
    
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: HorizontalBar { 
            targetScreen: modelData; edge: "bottom"; rootShell: globalCtx.ref
            visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "bottom" && globalCtx.ref.horizontalBarProgress > 0.0 
        } 
    }

    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: ScreenEdgeFrame { 
            targetScreen: modelData; parentIndex: index; rootShell: globalCtx.ref 
        } 
    }
}
