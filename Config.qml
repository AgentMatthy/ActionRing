import QtQuick

QtObject {
    // Haptic feedback patterns (see mx4haptic.py for available patterns)
    // Available: click, tick, bump, double_click, hold, release, error, success
    readonly property string hapticOpen: ""
    readonly property string hapticHover: "3"
    readonly property string hapticSelect: "1"
    readonly property string hapticClose: "8"
    
    // Visual configuration
    readonly property int menuRadius: 90
    readonly property int circleSize: 58
    readonly property int submenuPullDistance: 58  // Distance to pull outward to confirm submenu navigation
    
    // Colors
    readonly property color itemColor: "#000000"
    readonly property color itemHoverColor: "#333333"
    readonly property color iconColor: "#ffffff"
    
    // Main menu items
    // Each item can have:
    //   - icon: nerdfont glyph
    //   - action: bash command to execute
    //   - submenu: name of submenu to open (instead of action)
    //   - closesubmenu: true to go back to previous menu (instead of action)
    //   - empty: true for an invisible spacer that takes up a slot
    
    
        // { icon: "", action: "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+; paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" },
        // { icon: "", action: "kitty yazi" },
        // { icon: "", action: "kitty" },
        // { icon: "", action: "neovide" },
        // { icon: "", action: "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%-; paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" },
        // { empty: true },
    

    readonly property var items: [
        { icon: "", action: "hyprlock" },
        { icon: "", action: "" },
        { icon: "", submenu: "media" },  // Opens the "apps" submenu
        { icon: "", action: "" },
        { icon: "", action: "" },
        { icon: "", action: "" },
        { icon: "", submenu: "apps" },  // Opens the "apps" submenu
        { icon: "", action: "" },
    ]
    
    // Submenus definition
    // Key is submenu name, value is array of items (same format as main items)
    // Use closesubmenu: true on an item to go back to the previous menu
    readonly property var submenus: {
        "apps": [
            { icon: "", action: "" },
            { icon: "", action: "" },
            { icon: "", closesubmenu: true },  // Back button
            { icon: "", action: "" },
            { icon: "", action: "" },
            { icon: "", action: "kitty yazi" },
            { icon: "", action: "kitty" },
            { icon: "", action: "neovide" },
        ],
        "media": [
            { icon: "", action: "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%+; paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" },
            { icon: "", action: "playerctl next" },
            { icon: "󰐎", action: "playerctl play-pause" },
            { icon: "", action: "playerctl previous" },
            { icon: "", action: "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 2%-; paplay /usr/share/sounds/freedesktop/stereo/audio-volume-change.oga" },
            { icon: "", action: "" },
            { icon: "", closesubmenu: true },  // Back button
            { icon: "", action: "" },
        ]
    }
    
    // Convenience property for item count
    readonly property int itemCount: items.length
}
