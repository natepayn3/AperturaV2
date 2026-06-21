import QtQuick
import QtQuick.Layouts
import QtQuick.Controls 
import QtQuick.Shapes 
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "modules"
import "modules/bars"
import "modules/components"
import "modules/windows"

Scope {
    id: rootShell

    // --- Global References for External Modules ---
    readonly property var clockRef: clockTimer
    readonly property var settingsAppRef: settingsAppInstance
    readonly property var calendarRef: globalCalendarPreview
    readonly property var launcherRef: globalAppLauncherPreview
    readonly property var workspaceRef: globalWorkspacePreview
    readonly property var bluetoothRef: globalBluetoothPreview
    readonly property var wallpaperRef: globalWallpaperPreview 

    // --- Modular Theme Provider Integration ---
    MatugenProvider { 
        id: themeProvider 
        isShutterMode: Config.shutterMode // 📸 Safely inject the singleton state here
    }

    // Colors automatically link to the provider changes
    property color colorBackground: themeProvider.background
    property color colorBorder: themeProvider.border
    property color colorAccent: themeProvider.accent
    property string matugenFilePath: themeProvider.matugenFilePath

    // 📸 Changed from 'string' to 'color' to prevent hex parsing failures
    property color colorText: themeProvider.textPrimary
    property color colorSubtext: themeProvider.textSub
    property var matugenPreviews: themeProvider.schemePreviews
    property int matugenPreviewTick: themeProvider.previewUpdateTick
    property color colorClose: "#f38ba8" 
    property string shellFont: "Rubik"

    // --- Window Layout & State Management ---
    property string barPosition: "left"
    property string enabledDisplayStr: "0"
    property string targetPosition: "left"
    property string activeLayoutOrientation: "vertical"
    property bool safeToLoad: false
    property string customBasePath: ""
    property string configFilePath: ""

    property real verticalBarProgress: 1.0
    property real horizontalBarProgress: 0.0
    property real verticalFrameProgress: 1.0
    property real horizontalFrameProgress: 0.0

    // Popup Progress Trackers
    property real previewProgress: 0.0
    property real calendarProgress: 0.0
    property real launcherProgress: 0.0
    property real bluetoothProgress: 0.0
    property real audioProgress: 0.0
    property real wifiProgress: 0.0
    property real dashboardProgress: 0.0

    readonly property var audioRef: globalAudioPreview
    readonly property var wifiRef: globalWifiPreview
    readonly property var dashboardRef: globalDashboardPreview

    onBarPositionChanged: saveConfig()
    onEnabledDisplayStrChanged: saveConfig()
    onShellFontChanged: saveConfig()

    // --- Window Animations ---
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

    ParallelAnimation { id: showCalendarAnim; NumberAnimation { target: rootShell; property: "calendarProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic } }
    ParallelAnimation {
        id: hideCalendarAnim
        NumberAnimation { target: rootShell; property: "calendarProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalCalendarPreview; property: "calendarActive"; value: false }
    }

    ParallelAnimation { id: showLauncherAnim; NumberAnimation { target: rootShell; property: "launcherProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic } }
    ParallelAnimation {
        id: hideLauncherAnim
        NumberAnimation { target: rootShell; property: "launcherProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalAppLauncherPreview; property: "launcherActive"; value: false }
    }

    ParallelAnimation { id: showBluetoothAnim; NumberAnimation { target: rootShell; property: "bluetoothProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic } }
    ParallelAnimation {
        id: hideBluetoothAnim
        NumberAnimation { target: rootShell; property: "bluetoothProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalBluetoothPreview; property: "bluetoothActive"; value: false }
    }

    ParallelAnimation { id: showAudioAnim; NumberAnimation { target: rootShell; property: "audioProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic } }
    ParallelAnimation {
        id: hideAudioAnim
        NumberAnimation { target: rootShell; property: "audioProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalAudioPreview; property: "audioActive"; value: false }
    }

    ParallelAnimation { id: showWifiAnim; NumberAnimation { target: rootShell; property: "wifiProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic } }
    ParallelAnimation {
        id: hideWifiAnim
        NumberAnimation { target: rootShell; property: "wifiProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalWifiPreview; property: "wifiActive"; value: false }
    }

    ParallelAnimation { id: showDashboardAnim; NumberAnimation { target: rootShell; property: "dashboardProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic } }
    ParallelAnimation {
        id: hideDashboardAnim
        NumberAnimation { target: rootShell; property: "dashboardProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalDashboardPreview; property: "dashboardActive"; value: false }
    }

    // --- Control Functions ---
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
        if (globalDashboardPreview.dashboardActive) globalDashboardPreview.forceDismiss();
        if (globalWallpaperPreview.active) globalWallpaperPreview.active = false; 
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
                    verticalBarProgress = 1.0; verticalFrameProgress = 1.0;
                    horizontalBarProgress = 0.0; horizontalFrameProgress = 0.0;
                } else {
                    verticalBarProgress = 0.0; verticalFrameProgress = 0.0;
                    horizontalBarProgress = 1.0; horizontalFrameProgress = 1.0;
                }
            }
            if (parsed.enabledDisplays !== undefined) enabledDisplayStr = parsed.enabledDisplays;
            if (parsed.font !== undefined) shellFont = parsed.font;
        } catch (e) {}
    }

    Process {
        id: startupConfigLoader
        running: false
        stdout: StdioCollector { onTextChanged: { parseConfig(text); rootShell.safeToLoad = true; } }
    }

    Process { id: saveConfigProc; running: false }

    Component.onCompleted: {
        const localUri = Qt.resolvedUrl(".").toString();
        rootShell.customBasePath = localUri.replace("file://", "").trim();
        rootShell.configFilePath = rootShell.customBasePath + "/shell_settings.json";
        
        startupConfigLoader.command = ["cat", rootShell.configFilePath]; 
        startupConfigLoader.running = true;
    }

    // --- Core Engine Window State Cross-Trackers ---
    Connections {
        target: settingsAppInstance; ignoreUnknownSignals: true
        function onWindowVisibleChanged() {
            if (settingsAppInstance.windowVisible) {
                if (globalAppLauncherPreview.active) globalAppLauncherPreview.active = false;
                rootShell.closeAllPopups();
            }
        }
    }

    Connections {
        target: globalAppLauncherPreview; ignoreUnknownSignals: true
        function onActiveChanged() {
            if (globalAppLauncherPreview.active) {
                if (settingsAppInstance.windowVisible) settingsAppInstance.windowVisible = false;
                rootShell.closeAllPopups();
            }
        }
    }

    Connections {
        target: globalWifiPreview; ignoreUnknownSignals: true
        function onWifiActiveChanged() {
            if (globalWifiPreview.wifiActive) {
                if (settingsAppInstance.windowVisible) settingsAppInstance.windowVisible = false;
                if (globalAppLauncherPreview.active) globalAppLauncherPreview.active = false;
                rootShell.closeAllPopups();
            }
        }
    }

    // --- Input Processing Interfaces ---
    IpcHandler { target: "settings"; function toggle(): void { if (settingsAppInstance) settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible; } }
    IpcHandler { target: "launcher"; function toggle(): void { if (globalAppLauncherPreview) globalAppLauncherPreview.active = !globalAppLauncherPreview.active; } }
    IpcHandler { target: "audio"; function updateVolume(): void { if (globalAudioPreview && globalAudioPreview.cardRef) globalAudioPreview.cardRef.showOsd(); } }
    IpcHandler { target: "wallpaper"; function toggle(): void { if (globalWallpaperPreview) globalWallpaperPreview.active = !globalWallpaperPreview.active; } }

    IpcHandler { 
        target: "shutter"; 
        function toggle(): void { 
            Config.saveSetting("shutterMode", !Config.shutterMode); 
        } 
    }

    SettingsApp { id: settingsAppInstance; shellTarget: rootShell }

    Timer { id: clockTimer; interval: 1000; running: true; repeat: true; property var currentTime: new Date(); onTriggered: currentTime = new Date() }

    // --- Dismiss Timers ---
    Timer { id: calendarDismissTimer; interval: 150; running: false; repeat: false; onTriggered: if (globalCalendarPreview.cardRef && !globalCalendarPreview.cardRef.isHovered) hideCalendarAnim.restart() }
    Timer { id: bluetoothDismissTimer; interval: 150; running: false; repeat: false; onTriggered: if (globalBluetoothPreview.cardRef && !globalBluetoothPreview.cardRef.isHovered) hideBluetoothAnim.restart() }
    Timer { id: audioDismissTimer; interval: 150; running: false; repeat: false; onTriggered: if (globalAudioPreview.cardRef && !globalAudioPreview.cardRef.isHovered) hideAudioAnim.restart() }
    Timer { id: dashboardDismissTimer; interval: 200; running: false; repeat: false; onTriggered: if (globalDashboardPreview.cardRef && !globalDashboardPreview.cardRef.isHovered) globalDashboardPreview.forceDismiss() }

    property int hoveredIndicatorWorkspace: -1
    Timer {
        id: previewDebounceTimer; interval: 50; running: false; repeat: false; property int pendingWorkspace: -1
        onTriggered: if (pendingWorkspace !== -1 && globalWorkspacePreview.cardRef) globalWorkspacePreview.cardRef.targetWorkspace = pendingWorkspace
    }
    Timer { id: dismissTimer; interval: 100; running: false; repeat: false; onTriggered: { hoveredIndicatorWorkspace = -1; globalWorkspacePreview.targetWorkspace = -1; } }

    function startDashboardDismissTimer() { dashboardDismissTimer.restart(); }

    // --- Window Module Trigger Handlers via Connections ---
    Connections {
        target: globalWorkspacePreview; ignoreUnknownSignals: true
        function onWorkspaceTargetChanged(ws, screenObj) {
            dismissTimer.stop();
            if (screenObj) globalWorkspacePreview.targetScreen = screenObj;
            hoveredIndicatorWorkspace = ws;
            if (globalWorkspacePreview.cardRef && ws !== globalWorkspacePreview.cardRef.targetWorkspace) {
                previewDebounceTimer.stop(); previewDebounceTimer.pendingWorkspace = ws; previewDebounceTimer.restart();
            }
            showPreviewAnim.restart();
        }
        function onDismissRequested() { dismissTimer.restart(); }
        function onCancelDismissRequested() { dismissTimer.stop(); previewDebounceTimer.stop(); }
        function onCloseRequested() { hidePreviewAnim.restart(); } 
    }

    Connections {
        target: globalCalendarPreview; ignoreUnknownSignals: true
        function onCalendarShowRequested() {
            if (!globalCalendarPreview.calendarActive) {
                if (globalAppLauncherPreview.active) globalAppLauncherPreview.active = false;
                if (settingsAppInstance.windowVisible) settingsAppInstance.windowVisible = false;
                rootShell.closeAllPopups();
                globalCalendarPreview.calendarActive = true;
                showCalendarAnim.restart();
            }
        }
        function onDismissRequested() { calendarDismissTimer.restart(); }
        function onCancelDismissRequested() { calendarDismissTimer.stop(); }
    }

    Connections {
        target: globalDashboardPreview; ignoreUnknownSignals: true
        function onDashboardShowRequested() {
            if (!globalDashboardPreview.dashboardActive) {
                rootShell.closeAllPopups(); dashboardDismissTimer.stop();
                globalDashboardPreview.dashboardActive = true; showDashboardAnim.restart();
            }
        }
        function onDismissRequested() { dashboardDismissTimer.restart(); }
        function onCancelDismissRequested() { dashboardDismissTimer.stop(); }
    }

    Connections {
        target: globalAudioPreview; ignoreUnknownSignals: true
        function onAudioShowRequested() {
            if (!globalAudioPreview.audioActive) {
                rootShell.closeAllPopups(); audioDismissTimer.stop();
                globalAudioPreview.audioActive = true; showAudioAnim.restart();
                if (globalAudioPreview.cardRef) globalAudioPreview.cardRef.forceActiveFocus();
            }
        }
        function onDismissRequested() { audioDismissTimer.restart(); }
        function onCancelDismissRequested() { audioDismissTimer.stop(); }
    }

    Connections {
        target: globalBluetoothPreview; ignoreUnknownSignals: true
        function onBluetoothShowRequested() {
            if (!globalBluetoothPreview.bluetoothActive) {
                rootShell.closeAllPopups(); bluetoothDismissTimer.stop();
                globalBluetoothPreview.bluetoothActive = true; showBluetoothAnim.restart();
                if (globalBluetoothPreview.cardRef) globalBluetoothPreview.cardRef.forceActiveFocus();
            }
        }
        function onDismissRequested() { bluetoothDismissTimer.restart(); }
        function onCancelDismissRequested() { bluetoothDismissTimer.stop(); }
    }

    Connections {
        target: globalWifiPreview; ignoreUnknownSignals: true
        function onWifiShowRequested() {
            if (!globalWifiPreview.wifiActive) {
                rootShell.closeAllPopups();
                globalWifiPreview.wifiActive = true; showWifiAnim.restart();
                if (globalWifiPreview.cardRef) globalWifiPreview.cardRef.forceActiveFocus();
            }
        }
    }

    Connections {
        target: globalWallpaperPreview 
        function onApplyFinished() {
            themeProvider.reloadColors();
        }
    }

    // --- Modular Window Instantiations ---
    WorkspaceWindow { id: globalWorkspacePreview; rootShell: rootShell }
    AppLauncher     { id: globalAppLauncherPreview }
    CalendarWindow  { id: globalCalendarPreview; rootShell: rootShell }
    DashboardWindow { id: globalDashboardPreview; rootShell: rootShell }
    AudioWindow     { id: globalAudioPreview; rootShell: rootShell }
    BluetoothWindow { id: globalBluetoothPreview; rootShell: rootShell }
    WifiWindow      { id: globalWifiPreview; rootShell: rootShell }
    WallpaperWindow { id: globalWallpaperPreview; rootShell: rootShell } 

    // --- Dynamic Instantiators using Unified Modules ---
    Item { id: globalCtx; property var ref: rootShell }

    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: VerticalBar { targetScreen: modelData; edge: "left"; rootShell: globalCtx.ref; visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "left" && globalCtx.ref.verticalBarProgress > 0.0 } 
    }
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: VerticalBar { targetScreen: modelData; edge: "right"; rootShell: globalCtx.ref; visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "right" && globalCtx.ref.verticalBarProgress > 0.0 } 
    }
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: HorizontalBar { targetScreen: modelData; edge: "top"; rootShell: globalCtx.ref; visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "top" && globalCtx.ref.horizontalBarProgress > 0.0 } 
    }
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: HorizontalBar { targetScreen: modelData; edge: "bottom"; rootShell: globalCtx.ref; visible: globalCtx.ref.isDisplayEnabled(index) && globalCtx.ref.barPosition === "bottom" && globalCtx.ref.horizontalBarProgress > 0.0 } 
    }
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: ScreenEdgeFrame { targetScreen: modelData; parentIndex: index; rootShell: globalCtx.ref } 
    }
}
