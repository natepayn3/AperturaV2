import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import QtQuick.Controls
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Item {
    id: previewRoot

    signal closeRequested()

    property int targetWorkspace: -1 
    property bool active: false
    
    property int stagedWorkspace: -1
    property var liveClientJson: []

    property int currentActiveWorkspace: -1
    property int workingWorkspace: -1

    property real radiusValue: 12
    property real wingSize: 14

    property int hoverOriginX: 0
    property int hoverOriginY: 0

    property bool isHovered: globalTrackingArea.containsMouse || contentHoverHandler.hovered

    property real maxCardWidth: viewportFrame.width + 28
    property real maxCardHeight: viewportFrame.calculatedBounds.isVertical ? 500 : 270

    implicitWidth: Math.round(maxCardWidth)
    implicitHeight: viewportFrame.calculatedBounds.isVertical ? 500 : 270

    // Smooth frame interpolators for fluidly reshaping between vertical/horizontal aspect ratios
    width: implicitWidth
    height: implicitHeight
    
    Behavior on width { 
        id: widthMorphBehavior
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic } 
    }
    Behavior on height { 
        id: heightMorphBehavior
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic } 
    }

    opacity: 1.0
    
    // FIXED: Match CalendarPopup — keep the root visible so it relies entirely on the parent PanelWindow mapping
    visible: true
    clip: false

    x: {
        if (rootShell.barPosition === "top") return hoverOriginX + 2;
        if (rootShell.barPosition === "bottom") return hoverOriginX + 2;
        if (rootShell.barPosition === "left") return hoverOriginX + 2;
        if (rootShell.barPosition === "right") return hoverOriginX - 2;
        return hoverOriginX;
    }
    
    y: {
        if (rootShell.barPosition === "top") return hoverOriginY + 2;
        if (rootShell.barPosition === "bottom") return hoverOriginY - 2;
        if (rootShell.barPosition === "left") return hoverOriginY + 2;
        if (rootShell.barPosition === "right") return hoverOriginY + 2;
        return hoverOriginY;
    }

    onTargetWorkspaceChanged: {
        if (targetWorkspace !== -1) {
            debounceTimer.restart();
        } else {
            debounceTimer.stop();
            previewRoot.active = false;
        }
    }

    Timer {
        id: debounceTimer
        interval: 50
        running: false
        repeat: false
        onTriggered: {
            if (previewRoot.targetWorkspace !== -1) {
                // Force Quickshell to fetch new Wayland surface proxies from the compositor
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
                
                previewRoot.workingWorkspace = previewRoot.targetWorkspace;
                clientQueryProcess.running = true;
                previewRoot.active = true;
            }
        }
    }

    Timer {
        id: jsonRefreshTimer
        interval: 100
        running: false
        onTriggered: clientQueryProcess.running = true
    }

    Connections {
        target: Hyprland
        ignoreUnknownSignals: true
        function onRawEvent(event) { 
            // Restarting the timer absorbs the spam of rapid raw events
            if (previewRoot.active) jsonRefreshTimer.restart();
        }
    }

    Process {
        id: clientQueryProcess
        command: ["hyprctl", "clients", "-j"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                let cleanText = text.trim();
                if (!cleanText || cleanText === "[]") return;
                try { previewRoot.liveClientJson = JSON.parse(cleanText);
                } catch(e) {}
            }
        }
    }

    function getCleanIconName(className) {
        if (!className) return "application-x-executable";
        let lowerClass = className.toLowerCase().trim();
        if (lowerClass.includes("chrome")) return "google-chrome";
        if (lowerClass.includes("kitty")) return "kitty";
        if (lowerClass.includes("terminal")) return "utilities-terminal";
        if (lowerClass.includes("codium")) return "vscodium";
        if (lowerClass.includes("code")) return "vscode";
        if (lowerClass.includes("signal")) return "signal-desktop";
        return lowerClass;
    }

    Item {
        id: animatedGroup
        anchors.fill: parent

        transformOrigin: {
            if (rootShell.barPosition === "left") return Item.TopLeft
            if (rootShell.barPosition === "right") return Item.TopRight
            if (rootShell.barPosition === "top") return Item.TopLeft
            if (rootShell.barPosition === "bottom") return Item.BottomLeft
            return Item.Center
        }

        // --- Streamlined Fluid Behavior Hooks matching Audio/Bluetooth Modules ---
        opacity: previewRoot.active ? 1.0 : 0.0
        scale: previewRoot.active ? 1.0 : 0.0
        x: previewRoot.active ? 0 : (rootShell.barPosition === "right" ? 40 : -40)
        y: previewRoot.active ? 0 : (rootShell.barPosition === "top" ? -40 : 40)
        
        visible: opacity > 0.01

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
        Behavior on scale { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on x { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on y { NumberAnimation { duration: 350; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        
        Rectangle {
            id: cardMainBody
            anchors.fill: parent
            anchors.margins: -1 // 🎯 Push visual boundary out 1px to absorb fractional gap
            color: rootShell.colorBackground
            z: 2
            
            // 🎯 Add a physical border in the background color to bleed the straight edges
            border.width: 1
            border.color: rootShell.colorBackground
            
            topLeftRadius: 0
            topRightRadius: rootShell.barPosition === "bottom" ? previewRoot.radiusValue : 0
            bottomLeftRadius: rootShell.barPosition === "right" ? previewRoot.radiusValue : 0
            bottomRightRadius: (rootShell.barPosition === "top" || rootShell.barPosition === "left") ? previewRoot.radiusValue : 0
        }

        Item {
            id: borderClippingMask
            anchors.fill: parent
            anchors.margins: -1
            clip: false 
            z: 4

            Rectangle {
                id: borderFrame
                anchors.fill: parent
                
                anchors.leftMargin: rootShell.barPosition === "left" ? -2 : 0
                anchors.topMargin: rootShell.barPosition === "top" ? -2 : 0
                anchors.rightMargin: rootShell.barPosition === "right" ? -2 : 0
                anchors.bottomMargin: rootShell.barPosition === "bottom" ? -2 : 0

                color: "transparent"
                border.color: rootShell.colorBorder
                border.width: 0

                topLeftRadius: cardMainBody.topLeftRadius
                topRightRadius: cardMainBody.topRightRadius
                bottomLeftRadius: cardMainBody.bottomLeftRadius
                bottomRightRadius: cardMainBody.bottomRightRadius
            }
        }

        Item {
            anchors.fill: parent
            anchors.margins: -1 // 🎯 Align the wing grid with the expanded main body
            visible: previewRoot.width > 30
            z: 2 

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "top"

                Shape {
                    x: 0; y: parent.height
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1 // 🎯 Anti-aliasing bleed
                        startX: 0; startY: 0
                        PathLine { x: previewRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: 0; startY: 0
                        PathLine { x: 0; y: previewRoot.wingSize }
                        PathQuad { x: previewRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "left"

                Shape {
                    x: 0; y: parent.height
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: 0; startY: 0
                        PathLine { x: previewRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    x: parent.width; y: 0
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: 0; startY: 0
                        PathLine { x: 0; y: previewRoot.wingSize }
                        PathQuad { x: previewRoot.wingSize; y: 0; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "bottom"

                Shape {
                    rotation: -90
                    x: 0; y: -previewRoot.wingSize
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: 0; startY: 0
                        PathLine { x: previewRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Shape {
                    rotation: -90
                    transformOrigin: Item.TopLeft
                    x: parent.width
                    y: parent.height
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: 0; startY: 0
                        PathLine { x: previewRoot.wingSize; y: 0 }
                        PathQuad { x: 0; y: previewRoot.wingSize; controlX: 0; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: rootShell.barPosition === "right"

                Shape {
                    x: -previewRoot.wingSize; y: 0
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: previewRoot.wingSize; startY: 0
                        PathLine { x: previewRoot.wingSize; y: previewRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: previewRoot.wingSize; controlY: 0 }
                        PathLine { x: previewRoot.wingSize; y: 0 }
                    }
                }
                
                Shape {
                    x: parent.width - previewRoot.wingSize; y: parent.height
                    width: previewRoot.wingSize; height: previewRoot.wingSize
                    ShapePath {
                        fillColor: rootShell.colorBackground;
                        strokeColor: rootShell.colorBackground; strokeWidth: 1
                        startX: previewRoot.wingSize; startY: 0
                        PathLine { x: previewRoot.wingSize; y: previewRoot.wingSize }
                        PathQuad { x: 0; y: 0; controlX: previewRoot.wingSize; controlY: 0 }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        MouseArea { 
            id: globalTrackingArea
            anchors.fill: parent 
            hoverEnabled: true 
            acceptedButtons: Qt.LeftButton 
            onClicked: {
                Hyprland.dispatch(`hl.dsp.focus({ workspace = "${previewRoot.workingWorkspace}" })`);
                previewRoot.closeRequested();
            }
            z: 4
        }

        Item {
            id: layoutContentWrapper
            width: Math.round(previewRoot.maxCardWidth)
            height: Math.round(previewRoot.maxCardHeight)
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            opacity: previewRoot.active ? 1.0 : 0.0 
            z: 5

            // Unified Content Data Smooth Fade In/Out Reflow Behavior
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

            HoverHandler {
                id: contentHoverHandler
            }

            Item {
                anchors.fill: parent
                anchors.margins: 14

                Text {
                    id: titleLabel
                    text: previewRoot.workingWorkspace !== -1 ? "Workspace " + previewRoot.workingWorkspace : ""
                    font.family: rootShell.shellFont
                    font.pixelSize: 13
                    font.bold: true
                    color: rootShell.colorAccent
                    x: 0; y: 0
                }

                RowLayout {
                    x: titleLabel.x + titleLabel.implicitWidth + 24
                    y: 2; height: titleLabel.implicitHeight; spacing: 8
                    
                    Repeater {
                        model: viewportFrame.workspaceWindows
                        delegate: Image {
                            visible: (modelData.class || "") !== "" && modelData.mapped
                            source: Quickshell.iconPath(getCleanIconName(modelData.class))
                            Layout.preferredWidth: 16; Layout.preferredHeight: 16
                            fillMode: Image.PreserveAspectFit
                        }
                    }
                }

                Rectangle {
                    id: headerDivider
                    width: parent.width - 4; height: 1
                    color: rootShell.colorBorder
                    x: 0; y: 20
                }

                Rectangle {
                    id: viewportFrame
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: headerDivider.bottom; anchors.topMargin: 8
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    color: "transparent" 
                    radius: 4; clip: true

                    property var workspaceWindows: previewRoot.liveClientJson.filter(w => w.workspace.id === previewRoot.workingWorkspace)
                    property bool isTargetActiveWorkspace: !!(Hyprland.activeWorkspace && (previewRoot.workingWorkspace === Hyprland.activeWorkspace.id))

                    property var calculatedBounds: {
                        if (previewRoot.workingWorkspace === -1 || !workspaceWindows || workspaceWindows.length === 0) {
                            let mX = 0, mY = 0, mWidth = 1920, mHeight = 1080;
                            let wsObj = Hyprland.workspaces.values.find(w => w.id === previewRoot.workingWorkspace);
                            let targetMonitor = wsObj ? wsObj.monitor : Hyprland.activeMonitor;
                            if (targetMonitor) {
                                let scale = targetMonitor.scale > 0 ? targetMonitor.scale : 1.0;
                                mWidth = Math.round(targetMonitor.width / scale);
                                mHeight = Math.round(targetMonitor.height / scale);
                                mX = targetMonitor.x;
                                mY = targetMonitor.y;
                                let barThickness = 44;
                                if (rootShell.barPosition === "left") { mX += barThickness; mWidth -= barThickness; }
                                else if (rootShell.barPosition === "right") { mWidth -= barThickness; }
                                else if (rootShell.barPosition === "top") { mY += barThickness; mHeight -= barThickness; }
                                else if (rootShell.barPosition === "bottom") { mHeight -= barThickness; }
                            }
                            return { "w": mWidth, "h": mHeight, "isVertical": mHeight > mWidth, "originX": mX, "originY": mY };
                        }

                        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                        for (let i = 0; i < workspaceWindows.length; i++) {
                            let win = workspaceWindows[i];
                            if (!win.at || !win.size) continue;
                            if (win.at[0] < minX) minX = win.at[0];
                            if (win.at[1] < minY) minY = win.at[1];
                            if ((win.at[0] + win.size[0]) > maxX) maxX = win.at[0] + win.size[0];
                            if ((win.at[1] + win.size[1]) > maxY) maxY = win.at[1] + win.size[1];
                        }

                        let spanX = maxX - minX;
                        let spanY = maxY - minY;
                        let verticalDetected = spanY > spanX;
                        
                        let normW = verticalDetected ? 1080 : 1920;
                        let normH = verticalDetected ? 1920 : 1080;
                        
                        if (spanX > 0 && Math.abs(spanX - normW) > 100) normW = spanX;
                        if (spanY > 0 && Math.abs(spanY - normH) > 100) normH = spanY;
                        return { "w": normW, "h": normH, "isVertical": verticalDetected, "originX": minX, "originY": minY };
                    }

                    width: Math.round(height * (calculatedBounds.w / calculatedBounds.h))
                    property real scaleX: width / calculatedBounds.w
                    property real scaleY: height / calculatedBounds.h

                    Repeater {
                        model: viewportFrame.workspaceWindows
                        delegate: Rectangle {
                            id: windowDelegate
                        
                            x: Math.round((modelData.at[0] - viewportFrame.calculatedBounds.originX) * viewportFrame.scaleX)
                            y: Math.round((modelData.at[1] - viewportFrame.calculatedBounds.originY) * viewportFrame.scaleY)
                            width: Math.max(4, Math.round(modelData.size[0] * viewportFrame.scaleX))
                            height: Math.max(4, Math.round(modelData.size[1] * viewportFrame.scaleY))
                            visible: modelData.mapped
                            
                            color: viewportFrame.isTargetActiveWorkspace ? Qt.rgba(rootShell.colorAccent.r, rootShell.colorAccent.g, rootShell.colorAccent.b, 0.15) : Qt.rgba(0, 0, 0, 0.6)
                            border.color: viewportFrame.isTargetActiveWorkspace ? rootShell.colorAccent : rootShell.colorBorder
                            border.width: 1; radius: 2; clip: true

                            property var wlToplevel: {
                                if (!modelData || !modelData.address) return null;
                                let tracker = clientQueryProcess.running;
                                let targetAddr = modelData.address.trim().toLowerCase();

                                let match = Hyprland.toplevels.values.find(t => {
                                    if (!t.lastIpcObject || !t.lastIpcObject.address) return false;
                                    return t.lastIpcObject.address.trim().toLowerCase() === targetAddr;
                                 });
                                if (match && match.wayland) return match.wayland;
                                
                                if (Hyprland.activeWorkspace) {
                                    let localMatch = Hyprland.activeWorkspace.toplevels.values.find(t => {
                                        if (!t.lastIpcObject || !t.lastIpcObject.address) return false;
                                        return t.lastIpcObject.address.trim().toLowerCase() === targetAddr;
                                    });
                                    if (localMatch && localMatch.wayland) return localMatch.wayland;
                                }
                                return null;
                            }

                            Loader {
                                anchors.fill: parent
                                active: windowDelegate.wlToplevel !== null && !viewportFrame.isTargetActiveWorkspace
                                asynchronous: true 
                                
                                opacity: status === Loader.Ready ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                sourceComponent: Component {
                                    ScreencopyView {
                                        captureSource: windowDelegate.wlToplevel
                                        live: true
                                        paintCursor: false
                                    }
                                }
                            }

                            Rectangle {
                                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                height: Math.min(14, parent.height * 0.25)
                                color: viewportFrame.isTargetActiveWorkspace ? rootShell.colorAccent : "#cc11111b"
                                visible: parent.height > 20 && parent.width > 35; z: 10

                                Text {
                                    text: (modelData.title && modelData.title.trim() !== "" && modelData.title !== "~") ? modelData.title : (modelData.class || "")
                                    font.family: rootShell.shellFont; font.pixelSize: 8; font.bold: true; 
                                    color: viewportFrame.isTargetActiveWorkspace ? rootShell.colorBackground : "#ffffff"
                                    anchors.centerIn: parent; width: parent.width - 4; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
