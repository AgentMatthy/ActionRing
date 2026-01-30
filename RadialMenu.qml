import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: radialMenuWindow
    
    // Configuration
    property int menuRadius: 120
    property int innerRadius: 40
    property int itemCount: 8
    property real hoverAngle: -1  // The angle being hovered
    property int hoveredIndex: -1
    
    // Cursor position when menu was opened (screen-relative)
    property real cursorX: 0
    property real cursorY: 0
    
    // Colors
    property color backgroundColor: Qt.rgba(0.1, 0.1, 0.12, 0.95)
    property color itemColor: Qt.rgba(0.2, 0.2, 0.25, 0.9)
    property color itemHoverColor: Qt.rgba(0.35, 0.55, 0.95, 0.95)
    property color borderColor: Qt.rgba(0.4, 0.4, 0.5, 0.5)
    
    visible: false
    color: "transparent"
    
    // Full screen overlay
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    
    // Wayland layer shell configuration
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "actionmenu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    
    // Ignore exclusive zones from other panels (like your bar)
    exclusionMode: ExclusionMode.Ignore
    
    // Focus grab for Hyprland - dismisses when clicking outside
    HyprlandFocusGrab {
        id: focusGrab
        active: radialMenuWindow.visible
        windows: [radialMenuWindow]
        onCleared: radialMenuWindow.close()
    }
    
    // Process to get cursor position from hyprctl
    Process {
        id: cursorProcess
        command: ["hyprctl", "cursorpos"]
        running: false
        
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.error("hyprctl cursorpos failed")
                return
            }
        }
        
        stdout: SplitParser {
            onRead: data => {
                // Parse "x, y" format
                const parts = data.trim().split(", ")
                if (parts.length !== 2) return
                
                const globalX = parseInt(parts[0])
                const globalY = parseInt(parts[1])
                
                // Find the monitor that contains the cursor
                for (let i = 0; i < Hyprland.monitors.values.length; i++) {
                    const mon = Hyprland.monitors.values[i]
                    // Monitor bounds in hyprctl coordinate space
                    const scaledWidth = mon.width / mon.scale
                    const scaledHeight = mon.height / mon.scale
                    
                    if (globalX >= mon.x && globalX < mon.x + scaledWidth &&
                        globalY >= mon.y && globalY < mon.y + scaledHeight) {
                        // Find matching QuickShell screen
                        for (let j = 0; j < Quickshell.screens.length; j++) {
                            const scr = Quickshell.screens[j]
                            if (scr.name === mon.name) {
                                radialMenuWindow.screen = scr
                                // Just use raw coordinates relative to monitor
                                // The PanelWindow with exclusionMode.Ignore covers the whole screen
                                radialMenuWindow.cursorX = globalX - mon.x
                                radialMenuWindow.cursorY = globalY - mon.y
                                break
                            }
                        }
                        break
                    }
                }
                
                // Now show the menu
                radialMenuWindow.visible = true
                focusItem.forceActiveFocus()
            }
        }
    }
    
    // Functions to open/close menu
    function open() {
        console.log("open() called")
        // Start the process to get cursor position
        cursorProcess.running = true
    }
    
    function close() {
        visible = false
        hoveredIndex = -1
        hoverAngle = -1
    }
    
    function toggle() {
        if (visible) {
            close()
        } else {
            open()
        }
    }
    
    // Calculate which segment is at a given angle
    function getSegmentIndex(angle: real): int {
        // Normalize angle to 0-360 range, with 0 at top
        let normalizedAngle = (angle + 360) % 360
        const segmentSize = 360 / itemCount
        // Offset by half segment so items are centered
        normalizedAngle = (normalizedAngle + segmentSize / 2) % 360
        return Math.floor(normalizedAngle / segmentSize)
    }
    
    // Focus item for keyboard input
    Item {
        id: focusItem
        focus: true
        Keys.onEscapePressed: radialMenuWindow.close()
    }
    
    // Mouse tracking (full screen)
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        
        onPositionChanged: mouse => {
            const dx = mouse.x - radialMenuWindow.cursorX
            const dy = mouse.y - radialMenuWindow.cursorY
            const distance = Math.sqrt(dx * dx + dy * dy)
            
            if (distance >= radialMenuWindow.innerRadius && distance <= radialMenuWindow.menuRadius) {
                // Calculate angle (0 is up, clockwise positive)
                let angle = Math.atan2(dx, -dy) * 180 / Math.PI
                radialMenuWindow.hoverAngle = angle
                radialMenuWindow.hoveredIndex = radialMenuWindow.getSegmentIndex(angle)
            } else {
                radialMenuWindow.hoveredIndex = -1
                radialMenuWindow.hoverAngle = -1
            }
        }
        
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                radialMenuWindow.close()
                return
            }
            
            if (radialMenuWindow.hoveredIndex >= 0) {
                console.log("Selected item:", radialMenuWindow.hoveredIndex)
                // TODO: Execute action for selected item
            }
            radialMenuWindow.close()
        }
    }
    
    // Visual representation of the radial menu (positioned at cursor)
    Item {
        id: menuVisual
        x: radialMenuWindow.cursorX - radialMenuWindow.menuRadius
        y: radialMenuWindow.cursorY - radialMenuWindow.menuRadius
        width: radialMenuWindow.menuRadius * 2
        height: radialMenuWindow.menuRadius * 2
        
        // Background circle (outer ring) with segments
        Repeater {
            model: radialMenuWindow.itemCount
            
            Shape {
                id: segmentShape
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 8
                
                required property int index
                
                property real segmentAngle: 360 / radialMenuWindow.itemCount
                property real startAngle: index * segmentAngle - 90 - segmentAngle / 2
                property real endAngle: startAngle + segmentAngle
                property bool isHovered: radialMenuWindow.hoveredIndex === index
                
                property real centerX: radialMenuWindow.menuRadius
                property real centerY: radialMenuWindow.menuRadius
                property real outerR: radialMenuWindow.menuRadius - 5
                property real innerR: radialMenuWindow.innerRadius
                
                // Convert angles to radians
                property real startRad: startAngle * Math.PI / 180
                property real endRad: endAngle * Math.PI / 180
                
                ShapePath {
                    fillColor: segmentShape.isHovered ? radialMenuWindow.itemHoverColor : radialMenuWindow.itemColor
                    strokeColor: radialMenuWindow.borderColor
                    strokeWidth: 1
                    
                    // Outer arc start point
                    startX: segmentShape.centerX + segmentShape.outerR * Math.cos(segmentShape.startRad)
                    startY: segmentShape.centerY + segmentShape.outerR * Math.sin(segmentShape.startRad)
                    
                    PathArc {
                        x: segmentShape.centerX + segmentShape.outerR * Math.cos(segmentShape.endRad)
                        y: segmentShape.centerY + segmentShape.outerR * Math.sin(segmentShape.endRad)
                        radiusX: segmentShape.outerR
                        radiusY: segmentShape.outerR
                        useLargeArc: segmentShape.segmentAngle > 180
                    }
                    
                    // Line to inner arc
                    PathLine {
                        x: segmentShape.centerX + segmentShape.innerR * Math.cos(segmentShape.endRad)
                        y: segmentShape.centerY + segmentShape.innerR * Math.sin(segmentShape.endRad)
                    }
                    
                    // Inner arc (reverse direction)
                    PathArc {
                        x: segmentShape.centerX + segmentShape.innerR * Math.cos(segmentShape.startRad)
                        y: segmentShape.centerY + segmentShape.innerR * Math.sin(segmentShape.startRad)
                        radiusX: segmentShape.innerR
                        radiusY: segmentShape.innerR
                        useLargeArc: segmentShape.segmentAngle > 180
                        direction: PathArc.Counterclockwise
                    }
                    
                    // Close path back to start
                    PathLine {
                        x: segmentShape.centerX + segmentShape.outerR * Math.cos(segmentShape.startRad)
                        y: segmentShape.centerY + segmentShape.outerR * Math.sin(segmentShape.startRad)
                    }
                }
            }
        }
        
        // Center circle
        Rectangle {
            anchors.centerIn: parent
            width: radialMenuWindow.innerRadius * 2 - 10
            height: width
            radius: width / 2
            color: radialMenuWindow.backgroundColor
            border.color: radialMenuWindow.borderColor
            border.width: 1
        }
    }
}
