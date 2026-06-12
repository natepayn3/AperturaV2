import QtQuick
import QtQuick.Layouts
import QtQuick.Controls 
import QtQuick.Shapes 
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "."

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

    SequentialAnimation {
        id: orientationAnim
        
        ParallelAnimation {
            NumberAnimation { target: rootShell; property: "verticalBarProgress"; to: 0.0; duration: 100; easing.type: Easing.InCubic }
            NumberAnimation { target: rootShell; property: "horizontalBarProgress"; to: 0.0; duration: 100; easing.type: Easing.InCubic }
            
            NumberAnimation { target: rootShell; property: "verticalFrameProgress"; to: 0.0; duration: 150; easing.type: Easing.InQuad }
            NumberAnimation { target: rootShell; property: "horizontalFrameProgress"; to: 0.0; duration: 150; easing.type: Easing.InQuad }
        }
        
        PauseAnimation {
            duration: 40
        }
        
        ParallelAnimation {
            PropertyAction { target: rootShell; property: "barPosition"; value: rootShell.targetPosition }
            PropertyAction { 
                target: rootShell
                property: "activeLayoutOrientation"
                value: (rootShell.targetPosition === "left" || rootShell.targetPosition === "right") ? "vertical" : "horizontal" 
            }
        }
        
        ScriptAction {
            script: {
                if (rootShell.activeLayoutOrientation === "vertical") {
                    expandVerticalBar.restart();
                    expandVerticalFrame.restart();
                } else {
                    expandHorizontalBar.restart();
                    expandHorizontalFrame.restart();
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

    function isDisplayEnabled(idx) {
        let items = enabledDisplayStr.split(",");
        return items.indexOf(String(idx)) !== -1;
    }

    function toggleDisplay(idx) {
        if (!safeToLoad) return;
        let items = enabledDisplayStr.split(",").filter(x => x.trim() !== "");
        let sIdx = String(idx);
        let pos = items.indexOf(sIdx);
        if (pos !== -1) {
            if (items.length > 1) items.splice(pos, 1);
        } else {
            items.push(sIdx);
        }
        enabledDisplayStr = items.join(",");
        settingsAppInstance.updateDisplaysFromShell();
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
                    verticalBarProgress = 1.0;
                    verticalFrameProgress = 1.0;
                    horizontalBarProgress = 0.0;
                    horizontalFrameProgress = 0.0;
                } else {
                    verticalBarProgress = 0.0;
                    verticalFrameProgress = 0.0;
                    horizontalBarProgress = 1.0;
                    horizontalFrameProgress = 1.0;
                }
            }
            if (parsed.enabledDisplays !== undefined) enabledDisplayStr = parsed.enabledDisplays;
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
        stdout: StdioCollector {
            onTextChanged: {
                parseConfig(text);
                rootShell.safeToLoad = true;
            }
        }
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
        stdout: StdioCollector {
            onTextChanged: {
                readMatugenProc.output = text;
                parseMatugen(text);
            }
        }
        property string output: ""
    }

    SettingsApp {
        id: settingsAppInstance
        shellTarget: rootShell
    }

    component LeftPanelBar : PanelWindow {
        property var targetScreen: null
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: implicitWidth
        color: Qt.rgba(0, 0, 0, 0)

        anchors { left: true; right: false; top: true; bottom: true; }
        implicitWidth: 36.0 * rootShell.verticalBarProgress
        implicitHeight: screen ? screen.height : 0

        Rectangle {
            color: rootShell.colorBackground
            anchors.fill: parent
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.leftMargin: 10
                anchors.rightMargin: 0
                spacing: 12

                Button {
                    id: settingsLauncherBtnL
                    Layout.fillWidth: true
                    flat: true
                    background: Rectangle { implicitWidth: 26; implicitHeight: 26; color: settingsLauncherBtnL.hovered ? rootShell.colorBorder : "transparent"; radius: 5; anchors.centerIn: parent }
                    contentItem: Text { text: "⚙"; font.pixelSize: 24; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnL.hovered ? rootShell.colorText : rootShell.colorSubtext); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    component RightPanelBar : PanelWindow {
        property var targetScreen: null
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: implicitWidth
        color: Qt.rgba(0, 0, 0, 0)

        anchors { left: false; right: true; top: true; bottom: true; }
        implicitWidth: 36.0 * rootShell.verticalBarProgress
        implicitHeight: screen ? screen.height : 0

        Rectangle {
            color: rootShell.colorBackground
            anchors.fill: parent
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 10
                anchors.leftMargin: 0
                anchors.rightMargin: 10
                spacing: 12

                Button {
                    id: settingsLauncherBtnR
                    Layout.fillWidth: true
                    flat: true
                    background: Rectangle { implicitWidth: 26; implicitHeight: 26; color: settingsLauncherBtnR.hovered ? rootShell.colorBorder : "transparent"; radius: 5; anchors.centerIn: parent }
                    contentItem: Text { text: "⚙"; font.pixelSize: 24; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnR.hovered ? rootShell.colorText : rootShell.colorSubtext); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    component TopPanelBar : PanelWindow {
        property var targetScreen: null
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: implicitHeight
        color: Qt.rgba(0, 0, 0, 0)

        anchors { left: true; right: true; top: true; bottom: false; }
        implicitWidth: screen ? screen.width : 0
        implicitHeight: 36.0 * rootShell.horizontalBarProgress

        Rectangle {
            color: rootShell.colorBackground
            anchors.fill: parent
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.topMargin: 10
                anchors.bottomMargin: 0
                spacing: 12

                Button {
                    id: settingsLauncherBtnT
                    Layout.fillHeight: true
                    flat: true
                    background: Rectangle { implicitWidth: 26; implicitHeight: 26; color: settingsLauncherBtnT.hovered ? rootShell.colorBorder : "transparent"; radius: 5; anchors.centerIn: parent }
                    contentItem: Text { text: "⚙"; font.pixelSize: 24; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnT.hovered ? rootShell.colorText : rootShell.colorSubtext); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    component BottomPanelBar : PanelWindow {
        property var targetScreen: null
        screen: targetScreen
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: WlrLayershell.Exclusive
        exclusiveZone: implicitHeight
        color: Qt.rgba(0, 0, 0, 0)

        anchors { left: true; right: true; top: false; bottom: true; }
        implicitWidth: screen ? screen.width : 0
        implicitHeight: 36.0 * rootShell.horizontalBarProgress

        Rectangle {
            color: rootShell.colorBackground
            anchors.fill: parent
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.topMargin: 0
                anchors.bottomMargin: 10
                spacing: 12

                Button {
                    id: settingsLauncherBtnB
                    Layout.fillHeight: true
                    flat: true
                    background: Rectangle { implicitWidth: 26; implicitHeight: 26; color: settingsLauncherBtnB.hovered ? rootShell.colorBorder : "transparent"; radius: 5; anchors.centerIn: parent }
                    contentItem: Text { text: "⚙"; font.pixelSize: 24; color: settingsAppInstance.windowVisible ? rootShell.colorAccent : (settingsLauncherBtnB.hovered ? rootShell.colorText : rootShell.colorSubtext); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: settingsAppInstance.windowVisible = !settingsAppInstance.windowVisible
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    Instantiator {
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: LeftPanelBar { targetScreen: modelData; visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "left" && rootShell.verticalBarProgress > 0.0 }
    }
    Instantiator {
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: RightPanelBar { targetScreen: modelData; visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "right" && rootShell.verticalBarProgress > 0.0 }
    }
    Instantiator {
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: TopPanelBar { targetScreen: modelData; visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "top" && rootShell.horizontalBarProgress > 0.0 }
    }
    Instantiator {
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: BottomPanelBar { targetScreen: modelData; visible: rootShell.isDisplayEnabled(index) && rootShell.barPosition === "bottom" && rootShell.horizontalBarProgress > 0.0 }
    }

    component ScreenEdgeFrame : PanelWindow {
        id: frameWindowItem
        property var targetScreen: null
        property int parentIndex: 0
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

        property real currentMargin: rootShell.activeLayoutOrientation === "vertical" ? (36.0 * rootShell.verticalFrameProgress) : (36.0 * rootShell.horizontalFrameProgress)

        implicitWidth: barPosition === "left" || barPosition === "right" ? (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.width - currentMargin : 0) : (screen ? screen.width : 0)) : (screen ? screen.width : 0)
        implicitHeight: barPosition === "top" || barPosition === "bottom" ? (rootShell.isDisplayEnabled(parentIndex) ? (screen ? screen.height - currentMargin : 0) : (screen ? screen.height : 0)) : (screen ? screen.height : 0)

        Shape {
            anchors.fill: parent
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
                PathArc  { x: frameWindowItem.width - 8; y: 8 + borderFrameLine.radius; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
                PathLine { x: frameWindowItem.width - 8; y: frameWindowItem.height - 8 - borderFrameLine.radius }
                PathArc  { x: frameWindowItem.width - 8 - borderFrameLine.radius; y: frameWindowItem.height - 8; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
                PathLine { x: 8 + borderFrameLine.radius; y: frameWindowItem.height - 8 }
                PathArc  { x: 8; y: frameWindowItem.height - 8 - borderFrameLine.radius; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
                PathLine { x: 8; y: 8 + borderFrameLine.radius }
                PathArc  { x: 8 + borderFrameLine.radius; y: 8; radiusX: borderFrameLine.radius; radiusY: borderFrameLine.radius }
            }
        }

        Rectangle {
            id: borderFrameLine
            x: 8; y: 8
            width: parent.width - 16
            height: parent.height - 16
            color: "transparent"
            border.color: rootShell.colorBackground
            border.width: 2
            radius: 16
        }
    }

    Instantiator {
        model: rootShell.safeToLoad ? Quickshell.screens : null
        delegate: ScreenEdgeFrame {
            targetScreen: modelData
            parentIndex: index 
        }
    }
}