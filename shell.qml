import QtQuick
import QtQuick.Layouts
import QtQuick.Controls 
import QtQuick.Shapes 
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "modules"

Scope {
    id: rootShell

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

    function triggerOrientationChange(newEdge) {
        if (barPosition === newEdge) return;
        targetPosition = newEdge;
        orientationAnim.restart();
    }

    // --- Workspace Preview Animations ---
    ParallelAnimation {
        id: showPreviewAnim
        NumberAnimation { target: rootShell; property: "previewProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hidePreviewAnim
        NumberAnimation { target: rootShell; property: "previewProgress"; to: 0.0; duration: 160; easing.type: Easing.InQuad }
        PropertyAction { target: globalWorkspacePreview; property: "targetWorkspace"; value: -1 }
    }

    // --- Calendar Animations ---
    ParallelAnimation {
        id: showCalendarAnim
        NumberAnimation { target: rootShell; property: "calendarProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: hideCalendarAnim
        NumberAnimation { target: rootShell; property: "calendarProgress"; to: 0.0; duration: 350; easing.type: Easing.InQuad }
        PropertyAction { target: globalCalendarPreview; property: "calendarActive"; value: false }
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
        id: dismissTimer
        interval: 150
        running: false
        repeat: false
        onTriggered: hidePreviewAnim.restart()
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
        id: previewDebounceTimer
        interval: 50 
        running: false
        repeat: false
        property int pendingWorkspace: -1
        onTriggered: {
            if (pendingWorkspace !== -1) {
                globalWorkspacePreview.commitWorkspaceChange(pendingWorkspace);
            }
        }
    }

    // --- Workspace Preview Panel ---
    PanelWindow {
        id: globalWorkspacePreview
        property bool mouseOverPreview: false
        
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-workspace-preview"
        WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        visible: targetWorkspace !== -1 || rootShell.previewProgress > 0.0
        color: "transparent"

        mask: Region { item: innerPreviewCard }

        property int targetWorkspace: -1

        onTargetWorkspaceChanged: {
            if (targetWorkspace !== -1) {
                if (targetWorkspace === innerPreviewCard.currentActiveWorkspace) {
                    previewDebounceTimer.stop();
                    return; 
                }
                previewDebounceTimer.pendingWorkspace = targetWorkspace;
                previewDebounceTimer.restart();
            } else {
                previewDebounceTimer.stop();
            }
        }

        function commitWorkspaceChange(ws) {
            dismissTimer.stop();
            showPreviewAnim.restart();
            innerPreviewCard.currentActiveWorkspace = ws;
        }

        function cancelDismiss() { dismissTimer.stop(); previewDebounceTimer.stop(); }
        function requestDismiss() { 
            if (!globalWorkspacePreview.mouseOverPreview) {
                dismissTimer.restart(); 
            }
        }

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

    // --- Calendar Preview Panel ---
    PanelWindow {
        id: globalCalendarPreview
        property bool calendarActive: false
        
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-calendar-preview"
        WlrLayershell.keyboardFocus: WlrLayershell.OnDemand
        WlrLayershell.exclusionMode: WlrLayershell.Ignore

        anchors { left: true; right: true; top: true; bottom: true }
        visible: calendarActive || rootShell.calendarProgress > 0.0
        color: "transparent"

        // FIX: Corrected from innerPreviewCard to innerCalendarCard
        mask: Region { item: innerCalendarCard }

        function showCalendar() {
            calendarDismissTimer.stop();
            calendarActive = true;
            showCalendarAnim.restart();
        }

        function requestDismiss() { 
            if (!innerCalendarCard.isHovered) {
                calendarDismissTimer.restart(); 
            }
        }

        CalendarPopup {
            id: innerCalendarCard
            active: globalCalendarPreview.calendarActive

            onIsHoveredChanged: {
                if (isHovered) {
                    calendarDismissTimer.stop();
                    globalCalendarPreview.showCalendar();
                } else {
                    globalCalendarPreview.requestDismiss();
                }
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

    component LeftPanelBar : PanelWindow {
        id: barL
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: 36 * rootShell.verticalBarProgress
        color: "transparent"
        anchors { left: true; right: false; top: true; bottom: true; }
        implicitWidth: 44.0 * rootShell.verticalBarProgress
        implicitHeight: screen ? screen.height : 0
        property var targetScreen: null

        Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
        Item { anchors.fill: parent
            Column {
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 4
                spacing: 12
                width: 32
                Button {
                    id: settingsLauncherBtnL; flat: true; width: 32; height: 32
                    background: Rectangle { anchors.fill: parent; color: settingsLauncherBtnL.hovered ? rootShell.colorBorder : "transparent"; radius: 6 }
                    Text { text: "settings"; font.family: "Material Icons"; font.pixelSize: 22; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnL.hovered ? rootShell.colorText : rootShell.colorSubtext); anchors.centerIn: parent }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                
                Item {
                    width: parent.width; height: clockColL.implicitHeight
                    Column {
                        id: clockColL
                        width: parent.width; spacing: 2
                        Text { text: Qt.formatDateTime(clockTimer.currentTime, "ddd"); font.family: rootShell.shellFont; font.pixelSize: 11; font.bold: true; color: rootShell.colorAccent; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                        Text { 
                            text: { 
                                let hours = clockTimer.currentTime.getHours() % 12
                                hours = hours === 0 ? 12 : hours
                                return hours + ":" + clockTimer.currentTime.getMinutes().toString().padStart(2, '0')
                            } 
                            font.family: rootShell.shellFont; font.pixelSize: 12; font.bold: true; color: rootShell.colorText; horizontalAlignment: Text.AlignHCenter; width: parent.width 
                        }
                        Text { text: clockTimer.currentTime.getHours() >= 12 ? "pm" : "am"; font.family: rootShell.shellFont; font.pixelSize: 10; font.bold: false; color: rootShell.colorSubtext; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onEntered: globalCalendarPreview.showCalendar()
                        onExited: globalCalendarPreview.requestDismiss()
                    }
                }
                
                Workspaces { width: parent.width; shellTarget: rootShell; parentBarWindow: barL; previewWindowInstance: globalWorkspacePreview }
            }
        }
    }

    component RightPanelBar : PanelWindow {
        id: barR
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: 36 * rootShell.verticalBarProgress
        color: "transparent"
        anchors { left: false; right: true; top: true; bottom: true; }
        implicitWidth: 44.0 * rootShell.verticalBarProgress
        implicitHeight: screen ? screen.height : 0
        property var targetScreen: null

        Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
        Item { anchors.fill: parent
            Column {
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.leftMargin: 4
                spacing: 12
                width: 32
                Button {
                    id: settingsLauncherBtnR; flat: true; width: 32; height: 32
                    background: Rectangle { anchors.fill: parent; color: settingsLauncherBtnR.hovered ? rootShell.colorBorder : "transparent"; radius: 6 }
                    Text { text: "settings"; font.family: "Material Icons"; font.pixelSize: 22; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnR.hovered ? rootShell.colorText : rootShell.colorSubtext); anchors.centerIn: parent }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                
                Item {
                    width: parent.width; height: clockColR.implicitHeight
                    Column {
                        id: clockColR
                        width: parent.width; spacing: 2
                        Text { text: Qt.formatDateTime(clockTimer.currentTime, "ddd"); font.family: rootShell.shellFont; font.pixelSize: 11; font.bold: true; color: rootShell.colorAccent; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                        Text { 
                            text: { 
                                let hours = clockTimer.currentTime.getHours() % 12
                                hours = hours === 0 ? 12 : hours
                                return hours + ":" + clockTimer.currentTime.getMinutes().toString().padStart(2, '0')
                            } 
                            font.family: rootShell.shellFont; font.pixelSize: 12; font.bold: true; color: rootShell.colorText; horizontalAlignment: Text.AlignHCenter; width: parent.width 
                        }
                        Text { text: clockTimer.currentTime.getHours() >= 12 ? "pm" : "am"; font.family: rootShell.shellFont; font.pixelSize: 10; font.bold: false; color: rootShell.colorSubtext; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse) globalCalendarPreview.showCalendar(); else globalCalendarPreview.requestDismiss();
                    }
                }
                
                Workspaces { width: parent.width; shellTarget: rootShell; parentBarWindow: barR; previewWindowInstance: globalWorkspacePreview }
            }
        }
    }

    component TopPanelBar : PanelWindow {
        id: barT
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: 36 * rootShell.horizontalBarProgress
        color: "transparent"
        anchors { left: true; right: true; top: true; bottom: false; }
        implicitWidth: screen ? screen.width : 0
        implicitHeight: 44.0 * rootShell.horizontalBarProgress
        property var targetScreen: null

        Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
        Item { anchors.fill: parent
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                spacing: 12
                height: 32
                Button {
                    id: settingsLauncherBtnT; flat: true; width: 32; height: 32
                    background: Rectangle { anchors.fill: parent; color: settingsLauncherBtnT.hovered ? rootShell.colorBorder : "transparent"; radius: 6 }
                    Text { text: "settings"; font.family: "Material Icons"; font.pixelSize: 22; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnT.hovered ? rootShell.colorText : rootShell.colorSubtext); anchors.centerIn: parent }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: clockRowT.implicitWidth; height: parent.height
                    Row {
                        id: clockRowT
                        spacing: 4; anchors.verticalCenter: parent.verticalCenter
                        Text { text: Qt.formatDateTime(clockTimer.currentTime, "ddd"); font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorAccent; verticalAlignment: Text.AlignVCenter }
                        Text { text: "•"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorSubtext; verticalAlignment: Text.AlignVCenter }
                        Text { 
                            text: { 
                                let date = clockTimer.currentTime
                                let hours = date.getHours() % 12
                                hours = hours === 0 ? 12 : hours
                                return hours + ":" + date.getMinutes().toString().padStart(2, '0')
                            } 
                            font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorText; verticalAlignment: Text.AlignVCenter 
                        }
                        Text { text: clockTimer.currentTime.getHours() >= 12 ? "pm" : "am"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorSubtext; verticalAlignment: Text.AlignVCenter }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse) globalCalendarPreview.showCalendar(); else globalCalendarPreview.requestDismiss();
                    }
                }
                
                Workspaces { anchors.verticalCenter: parent.verticalCenter; shellTarget: rootShell; parentBarWindow: barT; previewWindowInstance: globalWorkspacePreview }
            }
        }
    }

    component BottomPanelBar : PanelWindow {
        id: barB
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: 36 * rootShell.horizontalBarProgress
        color: "transparent"
        anchors { left: true; right: true; top: false; bottom: true; }
        implicitWidth: screen ? screen.width : 0
        implicitHeight: 44.0 * rootShell.horizontalBarProgress
        property var targetScreen: null

        Rectangle { color: rootShell.colorBackground; anchors.fill: parent }
        Item { anchors.fill: parent
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.top: parent.top
                anchors.topMargin: 4
                spacing: 12
                height: 32
                Button {
                    id: settingsLauncherBtnB; flat: true; width: 32; height: 32
                    background: Rectangle { anchors.fill: parent; color: settingsLauncherBtnB.hovered ? rootShell.colorBorder : "transparent"; radius: 6 }
                    Text { text: "settings"; font.family: "Material Icons"; font.pixelSize: 22; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnB.hovered ? rootShell.colorText : rootShell.colorSubtext); anchors.centerIn: parent }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: clockRowB.implicitWidth; height: parent.height
                    Row {
                        id: clockRowB
                        spacing: 4; anchors.verticalCenter: parent.verticalCenter
                        Text { text: Qt.formatDateTime(clockTimer.currentTime, "ddd"); font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorAccent; verticalAlignment: Text.AlignVCenter }
                        Text { text: "•"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorSubtext; verticalAlignment: Text.AlignVCenter }
                        Text { 
                            text: { 
                                let date = clockTimer.currentTime
                                let hours = date.getHours() % 12
                                hours = hours === 0 ? 12 : hours
                                return hours + ":" + date.getMinutes().toString().padStart(2, '0')
                            } 
                            font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorText; verticalAlignment: Text.AlignVCenter 
                        }
                        Text { text: clockTimer.currentTime.getHours() >= 12 ? "pm" : "am"; font.family: rootShell.shellFont; font.pixelSize: 14; font.bold: true; color: rootShell.colorSubtext; verticalAlignment: Text.AlignVCenter }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse) globalCalendarPreview.showCalendar(); else globalCalendarPreview.requestDismiss();
                    }
                }
                
                Workspaces { anchors.verticalCenter: parent.verticalCenter; shellTarget: rootShell; parentBarWindow: barB; previewWindowInstance: globalWorkspacePreview }
            }
        }
    }

    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: LeftPanelBar { 
            targetScreen: modelData
            visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "left" && rootShell.verticalBarProgress > 0.0 
        } 
    }
    
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: RightPanelBar { 
            targetScreen: modelData
            visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "right" && rootShell.verticalBarProgress > 0.0 
        } 
    }
    
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: TopPanelBar { 
            targetScreen: modelData
            visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "top" && rootShell.horizontalBarProgress > 0.0 
        } 
    }
    
    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: BottomPanelBar { 
            targetScreen: modelData
            visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "bottom" && rootShell.horizontalBarProgress > 0.0 
        } 
    }

    component ScreenEdgeFrame : PanelWindow {
        id: frameWindowItem
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-frame"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.exclusionMode: WlrLayershell.Ignore
        color: Qt.rgba(0, 0, 0, 0)
        mask: Region {}
        anchors { 
            left: barPosition !== "left" || !rootShell.isDisplayEnabled(parentIndex)
            right: barPosition !== "right" || !rootShell.isDisplayEnabled(parentIndex)
            top: barPosition !== "top" || !rootShell.isDisplayEnabled(parentIndex)
            bottom: barPosition !== "bottom" || !rootShell.isDisplayEnabled(parentIndex) 
        }
        property var targetScreen: null
        property int parentIndex: 0
        property real currentMargin: rootShell.activeLayoutOrientation === "vertical" ? (36.0 * rootShell.verticalFrameProgress) : (36.0 * rootShell.horizontalFrameProgress)
        implicitWidth: barPosition === "left" || barPosition === "right" ? (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.width - currentMargin : 0) : (screen ? screen.width : 0)) : (screen ? screen.width : 0)
        implicitHeight: barPosition === "top" || barPosition === "bottom" ? (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.height - currentMargin : 0) : (screen ? screen.height : 0)) : (screen ? screen.height : 0)

        Shape {
            anchors.fill: parent
            // Fixed: Corrected layer property assignment syntax block
            layer.enabled: true
            layer.samples: 4
            ShapePath {
                fillColor: rootShell.colorBackground
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathMove { x: 0; y: 0 }
                PathLine { x: frameWindowItem.width; y: 0 }
                PathLine { x: frameWindowItem.width; y: frameWindowItem.height }
                PathLine { x: 0; y: frameWindowItem.height }
                PathLine { x: 0; y: 0 }
                PathMove { x: 8 + borderFrameLine.radius; y: 8 }
                PathLine { x: frameWindowItem.width - 8 - borderFrameLine.radius; y: 8 }
                PathArc { x: frameWindowItem.width - 8; y: 8 + borderFrameLine.radius; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
                PathLine { x: frameWindowItem.width - 8; y: frameWindowItem.height - 8 - borderFrameLine.radius }
                PathArc { x: frameWindowItem.width - 8 - borderFrameLine.radius; y: frameWindowItem.height - 8; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
                PathLine { x: 8 + borderFrameLine.radius; y: frameWindowItem.height - 8 }
                PathArc { x: 8; y: frameWindowItem.height - 8 - borderFrameLine.radius; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
                PathLine { x: 8; y: 8 + borderFrameLine.radius }
                PathArc { x: 8 + borderFrameLine.radius; y: 8; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
            }
        }
        Rectangle { id: borderFrameLine; x: 8; y: 8; width: parent.width - 16; height: parent.height - 16; color: "transparent"; border.color: rootShell.colorBackground; border.width: 2; radius: 16 }
    }

    Instantiator { 
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: ScreenEdgeFrame { 
            targetScreen: modelData
            parentIndex: index 
        } 
    }
}
