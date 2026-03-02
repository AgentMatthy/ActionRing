import QtQuick
import Quickshell.Io

QtObject {
    // All configuration is loaded from ~/.config/ActionRing/config.jsonc
    // Properties below are fallback defaults when the config file is missing or incomplete.
    
    // Installation path
    property string installPath: ""
    
    // Haptic feedback patterns
    property string hapticOpen: ""
    property string hapticHover: ""
    property string hapticSelect: ""
    property string hapticClose: ""
    property string hapticSubmenu: ""
    
    // Visual configuration
    property int menuRadius: 90
    property int circleSize: 58
    property int submenuPullDistance: 68
    property int repeatPullDistance: 50
    
    // Colors
    property color itemColor: "#000000"
    property color itemHoverColor: "#3C3836"
    property color iconColor: "#D5C4A1"
    
    // Menu items and submenus
    property var items: []
    property var submenus: ({})
    
    // Convenience property
    readonly property int itemCount: items.length
    
    function applyConfig(jsonStr) {
        try {
            var c = JSON.parse(jsonStr)
            if (c.installPath !== undefined) installPath = c.installPath
            if (c.hapticOpen !== undefined) hapticOpen = c.hapticOpen
            if (c.hapticHover !== undefined) hapticHover = c.hapticHover
            if (c.hapticSelect !== undefined) hapticSelect = c.hapticSelect
            if (c.hapticClose !== undefined) hapticClose = c.hapticClose
            if (c.hapticSubmenu !== undefined) hapticSubmenu = c.hapticSubmenu
            if (c.menuRadius !== undefined) menuRadius = c.menuRadius
            if (c.circleSize !== undefined) circleSize = c.circleSize
            if (c.submenuPullDistance !== undefined) submenuPullDistance = c.submenuPullDistance
            if (c.repeatPullDistance !== undefined) repeatPullDistance = c.repeatPullDistance
            if (c.itemColor !== undefined) itemColor = c.itemColor
            if (c.itemHoverColor !== undefined) itemHoverColor = c.itemHoverColor
            if (c.iconColor !== undefined) iconColor = c.iconColor
            if (c.items !== undefined) items = c.items
            if (c.submenus !== undefined) submenus = c.submenus
        } catch (e) {
            console.log("ActionRing: Failed to parse config: " + e)
        }
    }
}
