import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: radialMenuWindow
    
    // Load configuration
    Config {
        id: config
    }
    
    // Configuration from Config.qml
    property int menuRadius: config.menuRadius
    property int circleSize: config.circleSize
    property int hoveredIndex: -1
    
    // Current menu state
    property var currentItems: config.items
    property int itemCount: currentItems.length
    property var menuStack: []  // Stack of {items, cursorX, cursorY} for submenu navigation
    
    // Submenu pull-to-confirm state
    property int pendingSubmenuIndex: -1  // Index of submenu/closesubmenu item being pulled
    property real pullStartDistance: 0    // Distance from center when pull started
    property real pullProgress: 0.0       // 0.0 to 1.0 progress of pull confirmation
    
    // Repeat item pull-to-pump state
    property int pendingRepeatIndex: -1       // Index of repeat item being pulled
    property real repeatPullStartDistance: 0  // Distance from center when repeat pull started
    property real repeatPullProgress: 0.0     // 0.0 to 1.0 progress of repeat pull
    property bool repeatFireFlash: false      // Triggers flash animation when action fires
    
    // Animation state
    property bool isOpen: false
    property bool isTransitioning: false  // True during submenu transitions
    property int transitionDirection: 1   // 1 = opening submenu, -1 = closing submenu
    
    // Suppress initial mouse movement after menu opens
    property bool ignoreFirstMove: false
    
    // Cursor position when menu was opened (screen-relative)
    property real cursorX: 0
    property real cursorY: 0
    
    // Monitor offset (to convert screen-relative to global coordinates)
    property real monitorOffsetX: 0
    property real monitorOffsetY: 0
    
    // Colors from Config.qml
    property color itemColor: config.itemColor
    property color itemHoverColor: config.itemHoverColor
    
    // Haptic feedback processes (uses daemon via Unix socket for instant response)
    Process {
        id: hapticOpen
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticOpen]
    }
    
    Process {
        id: hapticHover
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticHover]
    }
    
    Process {
        id: hapticSelect
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticSelect]
    }
    
    Process {
        id: hapticClose
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticClose]
    }
    
    Process {
        id: hapticSubmenu
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", config.hapticSubmenu]
    }
    
    // Keepalive control - wakes device when menu opens, sleeps when closes
    Process {
        id: hapticWake
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", "wake"]
    }
    
    Process {
        id: hapticSleep
        command: ["/home/matthy/Dev/ActionMenu/mx4haptic-daemon.py", "sleep"]
    }
    
    // Action execution process
    Process {
        id: actionProcess
        command: ["bash", "-c", ""]
    }
    
    function executeAction(index: int) {
        if (index >= 0 && index < currentItems.length) {
            const item = currentItems[index]
            
            // Check if this is a submenu trigger
            if (item.submenu !== undefined) {
                // Will be handled by hover, not click
                return
            }
            
            // Check if this is a close submenu action
            if (item.closesubmenu === true) {
                // Will be handled by hover, not click
                return
            }
            
            // Execute the action
            if (item.action && item.action !== "") {
                // Use systemd-run to fully detach process with proper user environment
                actionProcess.command = ["systemd-run", "--user", "--no-block", "--", "bash", "-c", "cd ~ && " + item.action]
                actionProcess.running = true
            }
        }
    }
    
    function openSubmenu(submenuName: string, newCursorX: real, newCursorY: real) {
        const submenuItems = config.submenus[submenuName]
        if (submenuItems === undefined) {
            console.log("Submenu not found:", submenuName)
            return
        }
        
        // Push current state to stack
        menuStack.push({
            items: currentItems,
            cursorX: cursorX,
            cursorY: cursorY
        })
        
        // Start transition animation
        transitionDirection = 1
        isTransitioning = true
        
        // Store new state for after animation
        pendingItems = submenuItems
        pendingCursorX = newCursorX
        pendingCursorY = newCursorY
        
        transitionOutTimer.start()
        hapticSubmenu.running = true
    }
    
    function closeSubmenu(newCursorX: real, newCursorY: real) {
        if (menuStack.length === 0) {
            // No parent menu, just close
            close()
            return
        }
        
        // Pop previous state from stack
        const prevState = menuStack.pop()
        
        // Start transition animation
        transitionDirection = -1
        isTransitioning = true
        
        // Store new state for after animation
        pendingItems = prevState.items
        pendingCursorX = newCursorX
        pendingCursorY = newCursorY
        
        transitionOutTimer.start()
        hapticSubmenu.running = true
    }
    
    // Pending state for after transition
    property var pendingItems: []
    property real pendingCursorX: 0
    property real pendingCursorY: 0
    
    // Timer to switch menu content mid-transition
    Timer {
        id: transitionOutTimer
        interval: 80  // Wait for out animation
        onTriggered: {
            // Apply the pending state
            radialMenuWindow.currentItems = radialMenuWindow.pendingItems
            radialMenuWindow.itemCount = radialMenuWindow.currentItems.length
            radialMenuWindow.cursorX = radialMenuWindow.pendingCursorX
            radialMenuWindow.cursorY = radialMenuWindow.pendingCursorY
            radialMenuWindow.hoveredIndex = -1
            radialMenuWindow.ignoreFirstMove = true
            radialMenuWindow.pendingSubmenuIndex = -1  // Reset pull-to-confirm state
            radialMenuWindow.pullStartDistance = 0
            radialMenuWindow.pendingRepeatIndex = -1  // Reset repeat pull-to-pump state
            radialMenuWindow.repeatPullStartDistance = 0
            radialMenuWindow.repeatPullProgress = 0
            
            // Start in animation
            transitionInTimer.start()
        }
    }
    
    Timer {
        id: transitionInTimer
        interval: 10  // Small delay before animating in
        onTriggered: {
            radialMenuWindow.isTransitioning = false
        }
    }
    
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
        
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(", ")
                if (parts.length !== 2) return
                
                const globalX = parseInt(parts[0])
                const globalY = parseInt(parts[1])
                
                for (let i = 0; i < Hyprland.monitors.values.length; i++) {
                    const mon = Hyprland.monitors.values[i]
                    const scaledWidth = mon.width / mon.scale
                    const scaledHeight = mon.height / mon.scale
                    
                    if (globalX >= mon.x && globalX < mon.x + scaledWidth &&
                        globalY >= mon.y && globalY < mon.y + scaledHeight) {
                        for (let j = 0; j < Quickshell.screens.length; j++) {
                            const scr = Quickshell.screens[j]
                            if (scr.name === mon.name) {
                                radialMenuWindow.screen = scr
                                radialMenuWindow.monitorOffsetX = mon.x
                                radialMenuWindow.monitorOffsetY = mon.y
                                radialMenuWindow.cursorX = globalX - mon.x
                                radialMenuWindow.cursorY = globalY - mon.y
                                break
                            }
                        }
                        break
                    }
                }
                
                radialMenuWindow.visible = true
                radialMenuWindow.isOpen = true
                focusItem.forceActiveFocus()
                hapticOpen.running = true
            }
        }
    }
    
    // Process to warp cursor back after repeat action fires
    Process {
        id: cursorWarpProcess
        running: false
    }
    
    function warpCursor(x: real, y: real) {
        cursorWarpProcess.command = ["hyprctl", "dispatch", "movecursor", Math.round(x) + " " + Math.round(y)]
        cursorWarpProcess.running = true
    }
    
    function open() {
        hoveredIndex = -1  // Reset selection state before opening
        ignoreFirstMove = true  // Ignore initial mouse position event
        currentItems = config.items  // Reset to main menu
        itemCount = currentItems.length
        menuStack = []  // Clear submenu stack
        pendingSubmenuIndex = -1  // Reset pull-to-confirm state
        pullStartDistance = 0
        pendingRepeatIndex = -1  // Reset repeat pull-to-pump state
        repeatPullStartDistance = 0
        repeatPullProgress = 0
        repeatFireFlash = false
        hapticWake.running = true  // Wake device immediately before getting cursor
        cursorProcess.running = true
    }
    
    function close() {
        isOpen = false
        hoveredIndex = -1
        menuStack = []  // Clear submenu stack
        pendingSubmenuIndex = -1  // Reset pull-to-confirm state
        pullStartDistance = 0
        pendingRepeatIndex = -1  // Reset repeat pull-to-pump state
        repeatPullStartDistance = 0
        repeatPullProgress = 0
        repeatFireFlash = false
        hapticClose.running = true
        hapticSleep.running = true  // Stop keepalive
    }
    
    // Hide window after close animation completes
    onIsOpenChanged: {
        if (!isOpen) {
            closeTimer.start()
        }
    }
    
    Timer {
        id: closeTimer
        interval: 100
        onTriggered: {
            radialMenuWindow.visible = false
            // Reset to main menu after window is hidden
            radialMenuWindow.currentItems = config.items
            radialMenuWindow.itemCount = radialMenuWindow.currentItems.length
        }
    }
    
    function selectCurrent() {
        if (hoveredIndex >= 0) {
            executeAction(hoveredIndex)
            hapticSelect.running = true
        } else {
            hapticClose.running = true
        }
        isOpen = false
        hoveredIndex = -1
        menuStack = []
        hapticSleep.running = true  // Stop keepalive
    }
    
    function toggle() {
        if (visible) {
            close()
        } else {
            open()
        }
    }
    
    // Get position of a menu item by index (in screen coordinates)
    function getItemPosition(index: int): var {
        const angle = index * (360 / itemCount) - 90
        const angleRad = angle * Math.PI / 180
        return {
            x: cursorX + menuRadius * Math.cos(angleRad),
            y: cursorY + menuRadius * Math.sin(angleRad)
        }
    }
    
    // Get index of circle based on angle (cursor must reach item distance)
    function getHoveredIndex(mouseX: real, mouseY: real): int {
        const dx = mouseX - cursorX
        const dy = mouseY - cursorY
        const distance = Math.sqrt(dx * dx + dy * dy)
        
        // Dead zone: cursor must reach the inner edge of the item circles
        // Items are at menuRadius, circles have radius circleSize/2
        const minDist = menuRadius - circleSize / 2
        if (distance < minDist) {
            return -1
        }
        
        // Calculate angle and find nearest circle (angle-based, no max distance)
        let angle = Math.atan2(dx, -dy) * 180 / Math.PI
        angle = (angle + 360) % 360
        
        const segmentSize = 360 / itemCount
        const index = Math.floor((angle + segmentSize / 2) % 360 / segmentSize)
        
        return index
    }
    
    // Handle submenu navigation on hover - now starts pull-to-confirm
    function handleHover(index: int, mouseX: real, mouseY: real) {
        if (index < 0 || index >= currentItems.length) return
        
        const item = currentItems[index]
        
        // Check if this is a submenu or closesubmenu item
        if (item.submenu !== undefined || item.closesubmenu === true) {
            // Start pull-to-confirm tracking
            const dx = mouseX - cursorX
            const dy = mouseY - cursorY
            pullStartDistance = Math.sqrt(dx * dx + dy * dy)
            pendingSubmenuIndex = index
            return
        }
    }
    
    // Check if pull distance is enough to confirm submenu navigation
    function checkPullConfirm(mouseX: real, mouseY: real) {
        if (pendingSubmenuIndex < 0) return
        
        const dx = mouseX - cursorX
        const dy = mouseY - cursorY
        const currentDistance = Math.sqrt(dx * dx + dy * dy)
        
        // Calculate and update pull progress
        const pullAmount = currentDistance - pullStartDistance
        pullProgress = Math.max(0, Math.min(1, pullAmount / config.submenuPullDistance))
        
        // Check if user has pulled outward by the required amount
        if (pullAmount >= config.submenuPullDistance) {
            const item = currentItems[pendingSubmenuIndex]
            
            // Reset pending state before transition
            pendingSubmenuIndex = -1
            pullStartDistance = 0
            pullProgress = 0
            
            // Use current cursor position as new menu center (where user finished pulling)
            if (item.submenu !== undefined) {
                openSubmenu(item.submenu, mouseX, mouseY)
            } else if (item.closesubmenu === true) {
                closeSubmenu(mouseX, mouseY)
            }
        }
    }
    
    // Cancel pending submenu if user moves away from the item
    function cancelPendingSubmenu() {
        pendingSubmenuIndex = -1
        pullStartDistance = 0
        pullProgress = 0
    }
    
    // Handle repeat item hover - starts pull-to-pump tracking
    function handleRepeatItem(index: int, mouseX: real, mouseY: real) {
        if (index < 0 || index >= currentItems.length) return
        
        const item = currentItems[index]
        if (item.repeat !== true) return
        
        // Start pull-to-pump tracking
        const dx = mouseX - cursorX
        const dy = mouseY - cursorY
        repeatPullStartDistance = Math.sqrt(dx * dx + dy * dy)
        pendingRepeatIndex = index
        repeatPullProgress = 0
    }
    
    // Check if pull distance is enough to fire repeat action (pump gesture)
    function checkRepeatPullConfirm(mouseX: real, mouseY: real) {
        if (pendingRepeatIndex < 0) return
        
        const dx = mouseX - cursorX
        const dy = mouseY - cursorY
        const currentDistance = Math.sqrt(dx * dx + dy * dy)
        
        // Get the pull distance threshold for this item (allow per-item override)
        const item = currentItems[pendingRepeatIndex]
        const pullThreshold = item.repeatPullDistance !== undefined ? item.repeatPullDistance : config.repeatPullDistance
        
        // Calculate and update pull progress
        const pullAmount = currentDistance - repeatPullStartDistance
        repeatPullProgress = Math.max(0, Math.min(1, pullAmount / pullThreshold))
        
        // Check if user has pulled outward by the required amount
        if (pullAmount >= pullThreshold) {
            // Fire the action
            executeAction(pendingRepeatIndex)
            hapticSelect.running = true
            
            // Trigger flash animation
            repeatFireFlash = true
            repeatFlashTimer.start()
            
            // Warp cursor back towards the center of the radial menu
            warpCursor(cursorX + monitorOffsetX, cursorY + monitorOffsetY)
            
            // Reset progress (cursor will physically be back at start)
            repeatPullProgress = 0
        }
    }
    
    // Cancel pending repeat if user moves away from the item
    function cancelPendingRepeat() {
        pendingRepeatIndex = -1
        repeatPullStartDistance = 0
        repeatPullProgress = 0
    }
    
    // Timer to reset flash animation
    Timer {
        id: repeatFlashTimer
        interval: 150
        onTriggered: {
            radialMenuWindow.repeatFireFlash = false
        }
    }
    
    // Focus item for keyboard input
    Item {
        id: focusItem
        focus: true
        Keys.onEscapePressed: radialMenuWindow.close()
    }
    
    // Mouse tracking
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        
        onPositionChanged: mouse => {
            // Ignore the first position change after menu opens (prevents phantom selections)
            if (radialMenuWindow.ignoreFirstMove) {
                radialMenuWindow.ignoreFirstMove = false
                return
            }
            
            const newIndex = radialMenuWindow.getHoveredIndex(mouse.x, mouse.y)
            
            // Check if this is an empty slot (no interaction)
            const isEmptySlot = newIndex >= 0 && newIndex < radialMenuWindow.currentItems.length && 
                                radialMenuWindow.currentItems[newIndex].empty === true
            
            // Check if we're tracking a pull-to-confirm for submenu
            if (radialMenuWindow.pendingSubmenuIndex >= 0) {
                // If still hovering the same submenu item, check pull distance
                if (newIndex === radialMenuWindow.pendingSubmenuIndex) {
                    radialMenuWindow.checkPullConfirm(mouse.x, mouse.y)
                } else {
                    // Moved to a different item, cancel the pending submenu
                    radialMenuWindow.cancelPendingSubmenu()
                }
            }
            
            // Check if we're tracking a pull-to-pump for repeat item
            if (radialMenuWindow.pendingRepeatIndex >= 0) {
                // If still hovering the same repeat item, check pull distance
                if (newIndex === radialMenuWindow.pendingRepeatIndex) {
                    radialMenuWindow.checkRepeatPullConfirm(mouse.x, mouse.y)
                } else {
                    // Moved to a different item, cancel the pending repeat
                    radialMenuWindow.cancelPendingRepeat()
                }
            }
            
            if (newIndex !== radialMenuWindow.hoveredIndex && newIndex >= 0 && !isEmptySlot) {
                hapticHover.running = true
                
                // Check for submenu triggers on hover (starts pull-to-confirm)
                radialMenuWindow.handleHover(newIndex, mouse.x, mouse.y)
                
                // Check for repeat items on hover (starts pull-to-pump)
                radialMenuWindow.handleRepeatItem(newIndex, mouse.x, mouse.y)
            }
            radialMenuWindow.hoveredIndex = newIndex
        }
        
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                radialMenuWindow.close()
                return
            }
            
            if (radialMenuWindow.hoveredIndex >= 0) {
                const item = radialMenuWindow.currentItems[radialMenuWindow.hoveredIndex]
                // Don't close if it's a submenu trigger (already handled by hover)
                if (item.submenu !== undefined || item.closesubmenu === true) {
                    return
                }
                // Execute action but don't close for repeat items
                if (item.repeat === true) {
                    radialMenuWindow.executeAction(radialMenuWindow.hoveredIndex)
                    hapticSelect.running = true
                    // Trigger flash animation
                    radialMenuWindow.repeatFireFlash = true
                    repeatFlashTimer.start()
                    return
                }
                radialMenuWindow.executeAction(radialMenuWindow.hoveredIndex)
            }
            radialMenuWindow.close()
        }
    }
    
    // Visual: circles arranged radially
    Item {
        id: menuVisual
        x: radialMenuWindow.cursorX - radialMenuWindow.menuRadius - radialMenuWindow.circleSize / 2
        y: radialMenuWindow.cursorY - radialMenuWindow.menuRadius - radialMenuWindow.circleSize / 2
        width: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) * 2
        height: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) * 2
        
        // Only animate position during submenu transitions (not initial open)
        Behavior on x {
            enabled: radialMenuWindow.isOpen
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutExpo
            }
        }
        
        Behavior on y {
            enabled: radialMenuWindow.isOpen
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutExpo
            }
        }
        
        // Menu open/close/transition animation
        scale: (radialMenuWindow.isOpen && !radialMenuWindow.isTransitioning) ? 1.0 : 0.75
        opacity: (radialMenuWindow.isOpen && !radialMenuWindow.isTransitioning) ? 1.0 : 0.0
        
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }
        }
        
        Behavior on opacity {
            NumberAnimation {
                duration: 80
                easing.type: Easing.OutQuart
            }
        }
        
        Repeater {
            model: radialMenuWindow.itemCount
            
            Rectangle {
                id: circleItem
                
                required property int index
                
                property real angle: index * (360 / radialMenuWindow.itemCount) - 90
                property real angleRad: angle * Math.PI / 180
                property bool isHovered: radialMenuWindow.hoveredIndex === index
                property var itemData: radialMenuWindow.currentItems[index]
                property bool isPulling: radialMenuWindow.pendingSubmenuIndex === index
                property real currentPullProgress: isPulling ? radialMenuWindow.pullProgress : 0
                property bool isEmpty: itemData && itemData.empty === true
                
                // Repeat item properties
                property bool isRepeatItem: itemData && itemData.repeat === true
                property bool isRepeatPulling: radialMenuWindow.pendingRepeatIndex === index
                property real repeatPullProgress: isRepeatPulling ? radialMenuWindow.repeatPullProgress : 0
                property bool isRepeatFlashing: isRepeatItem && radialMenuWindow.repeatFireFlash && isHovered
                
                // Combined pull offset (submenu or repeat)
                property bool isAnyPulling: (isPulling || isRepeatPulling) && !isEmpty
                property real combinedPullProgress: isPulling ? currentPullProgress : (isRepeatPulling ? repeatPullProgress : 0)
                
                // Base position
                property real baseX: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) + 
                   radialMenuWindow.menuRadius * Math.cos(angleRad) - width / 2
                property real baseY: (radialMenuWindow.menuRadius + radialMenuWindow.circleSize / 2) + 
                   radialMenuWindow.menuRadius * Math.sin(angleRad) - height / 2
                
                // Pull outward animation - moves item outward as you pull (not for empty items)
                property real pullOffset: isAnyPulling ? combinedPullProgress * 15 : 0
                
                x: baseX + pullOffset * Math.cos(angleRad)
                y: baseY + pullOffset * Math.sin(angleRad)
                
                Behavior on pullOffset {
                    NumberAnimation {
                        duration: 50
                        easing.type: Easing.OutQuad
                    }
                }
                
                width: radialMenuWindow.circleSize
                height: radialMenuWindow.circleSize
                radius: width / 2
                
                // Empty items are completely transparent, no hover effect
                visible: !isEmpty
                color: isHovered ? radialMenuWindow.itemHoverColor : radialMenuWindow.itemColor
                scale: (isHovered && !isEmpty) ? 1.15 : 1.0
                
                Behavior on color {
                    ColorAnimation {
                        duration: 80
                        easing.type: Easing.OutQuart
                    }
                }
                
                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutBack
                        easing.overshoot: 4
                    }
                }
                
                // Collapsing ring for submenu pull-to-confirm
                Rectangle {
                    id: collapsingRing
                    anchors.centerIn: parent
                    // Start at 40px larger, collapse to touch the item (0 extra)
                    property real maxExpand: 40
                    width: parent.width + maxExpand * (1 - circleItem.currentPullProgress)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    // Border starts at 0 (invisible) and grows to 3px as it collapses
                    border.width: 3 * circleItem.currentPullProgress
                    border.color: config.iconColor
                    visible: circleItem.isPulling && circleItem.currentPullProgress > 0
                }
                
                // Collapsing ring for repeat item pull-to-pump (dedicated for easy future customization)
                Rectangle {
                    id: repeatCollapsingRing
                    anchors.centerIn: parent
                    // Start at 40px larger, collapse to touch the item (0 extra)
                    property real maxExpand: 40
                    width: parent.width + maxExpand * (1 - circleItem.repeatPullProgress)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    // Border starts at 0 (invisible) and grows to 3px as it collapses
                    border.width: 3 * circleItem.repeatPullProgress
                    border.color: config.iconColor
                    visible: circleItem.isRepeatPulling && circleItem.repeatPullProgress > 0
                }
                
                // Flash overlay for repeat action fire confirmation
                Rectangle {
                    id: repeatFlashOverlay
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: config.iconColor
                    opacity: circleItem.isRepeatFlashing ? 0.4 : 0.0
                    
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutQuart
                        }
                    }
                }
                
                Text {
                    anchors.centerIn: parent
                    text: circleItem.itemData ? circleItem.itemData.icon : ""
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: radialMenuWindow.circleSize * 0.45
                    color: config.iconColor
                    
                    scale: circleItem.isHovered ? 1.1 : 1.0
                    
                    Behavior on scale {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutBack
                            easing.overshoot: 4
                        }
                    }
                }
            }
        }
    }
}
