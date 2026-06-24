import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: editorWindow

    // The script directory is supplied by the parent so we can find the helpers.
    property string scriptDir: ""
    // Optional reference to the live RadialMenu so we can hot-reload after saving.
    property var radialMenu: null

    // ---- Live ring colors, pulled dynamically from the user's config ----
    // These mirror exactly what the real RadialMenu renders.
    readonly property color ringItemColor:  fullConfig.itemColor      || "#000000"
    readonly property color ringHoverColor: fullConfig.itemHoverColor || "#3C3836"
    readonly property color ringIconColor:  fullConfig.iconColor      || "#D5C4A1"
    readonly property int   ringRadius:     fullConfig.menuRadius     || 90
    readonly property int   ringCircleSize: fullConfig.circleSize     || 58

    // ---- UI chrome design tokens (derived from the config accent) ----
    readonly property color colBg:        "#000000"   // pure black background (requested)
    readonly property color colSurface:   "#121212"   // panels / cards
    readonly property color colSurface2:  "#1A1A1A"   // raised surface
    readonly property color colHover:     ringHoverColor
    readonly property color colBorder:    Qt.rgba(ringIconColor.r, ringIconColor.g, ringIconColor.b, 0.18)
    readonly property color colText:      "#EBDBB2"
    readonly property color colTextDim:   "#8A8579"
    readonly property color colAccent:    ringIconColor   // dynamic accent = menu icon color
    readonly property color colGreen:     "#B8BB26"
    readonly property color colRed:       "#FB4934"
    readonly property color colYellow:    "#FABD2F"
    readonly property color colBlue:      "#83A598"

    readonly property int radiusXl: 25   // outer window corners (requested)
    readonly property int radiusLg: 16
    readonly property int radiusMd: 10
    readonly property int radiusSm: 7

    // ---- Working config state (the in-memory model being edited) ----
    // fullConfig: the entire parsed config object (so we preserve colors/haptics/etc).
    property var fullConfig: ({})
    // items: array of entry objects for the menu currently being edited.
    property var items: []
    // submenuNames: list of submenu keys.
    property var submenuNames: []
    // currentMenu: "" => main menu, otherwise the submenu name.
    property string currentMenu: ""
    property int selectedIndex: -1
    property bool dirty: false
    property string statusText: ""

    // ---------------------------------------------------------------
    // Config loading
    // ---------------------------------------------------------------
    Process {
        id: loader
        command: ["python3", editorWindow.scriptDir + "/parse-config.py"]
        property string _output: ""
        stdout: SplitParser {
            onRead: data => loader._output += data + "\n"
        }
        onRunningChanged: {
            if (!running) {
                editorWindow._applyLoaded(loader._output)
            }
        }
    }

    function _applyLoaded(jsonStr) {
        try {
            var c = JSON.parse(jsonStr)
            fullConfig = c
            if (c.submenus === undefined) fullConfig.submenus = {}
            submenuNames = Object.keys(fullConfig.submenus || ({}))
            // Load the main menu directly WITHOUT committing the (stale/empty)
            // previous working array back into fullConfig.
            currentMenu = ""
            items = JSON.parse(JSON.stringify(fullConfig.items || []))
            selectedIndex = items.length > 0 ? 0 : -1
            dirty = false
            statusText = ""
        } catch (e) {
            statusText = "Failed to load config: " + e
        }
    }

    function loadConfig() {
        loader._output = ""
        loader.running = true
    }

    // ---------------------------------------------------------------
    // Config saving
    // ---------------------------------------------------------------
    Process {
        id: saver
        property string _payload: ""
        stdinEnabled: true
        onStarted: {
            write(_payload)
            stdinEnabled = false  // close stdin -> EOF so the writer proceeds
        }
        stdout: SplitParser {
            onRead: data => { /* "ok" */ }
        }
        onRunningChanged: {
            if (!running) {
                editorWindow.statusText = "Saved"
                editorWindow.dirty = false
                if (editorWindow.radialMenu) editorWindow.radialMenu.reloadConfig()
                savedFlashTimer.restart()
            }
        }
    }

    Timer {
        id: savedFlashTimer
        interval: 1600
        onTriggered: editorWindow.statusText = ""
    }

    function commitCurrentMenu() {
        // Write the working `items` back into fullConfig for the active menu.
        if (currentMenu === "") {
            fullConfig.items = items
        } else {
            var subs = fullConfig.submenus || ({})
            subs[currentMenu] = items
            fullConfig.submenus = subs
        }
    }

    function save() {
        commitCurrentMenu()
        saver._payload = JSON.stringify(fullConfig)
        saver.command = ["python3", editorWindow.scriptDir + "/write-config.py"]
        saver.stdinEnabled = true
        saver.running = true
    }

    // ---------------------------------------------------------------
    // Menu / entry model helpers
    // ---------------------------------------------------------------
    function loadMenu(name) {
        // Commit edits to the menu we're leaving.
        commitCurrentMenu()
        currentMenu = name
        var src = (name === "") ? (fullConfig.items || []) : ((fullConfig.submenus || ({}))[name] || [])
        // Deep copy so edits don't mutate fullConfig until commit.
        items = JSON.parse(JSON.stringify(src))
        selectedIndex = items.length > 0 ? 0 : -1
    }

    // Determine an entry's type string from its fields.
    function entryType(item) {
        if (!item) return "empty"
        if (item.empty === true) return "empty"
        if (item.closesubmenu === true) return "exit"
        if (item.submenu !== undefined) return "submenu"
        return "command"
    }

    function typeLabel(t) {
        if (t === "command") return "Command"
        if (t === "submenu") return "Submenu"
        if (t === "exit") return "Exit Submenu"
        return "Empty"
    }

    function typeColor(t) {
        if (t === "command") return colBlue
        if (t === "submenu") return colYellow
        if (t === "exit") return colRed
        return colTextDim
    }

    function typeIcon(t) {
        if (t === "command") return "\uf120"      // terminal
        if (t === "submenu") return "\uf0da"       // caret-right
        if (t === "exit") return "\uf060"          // arrow-left
        return "\uf111"                              // circle (empty)
    }

    // Mutate the working items array (reassign to trigger bindings).
    function updateItems(fn) {
        var copy = items.slice()
        fn(copy)
        items = copy
        dirty = true
    }

    function setEntryField(idx, field, value) {
        if (idx < 0 || idx >= items.length) return
        updateItems(function (arr) {
            var e = Object.assign({}, arr[idx])
            if (value === undefined || value === null) delete e[field]
            else e[field] = value
            arr[idx] = e
        })
    }

    // Convert the entry at idx to a given type, cleaning up incompatible fields.
    function setEntryType(idx, t) {
        if (idx < 0 || idx >= items.length) return
        updateItems(function (arr) {
            var e = Object.assign({}, arr[idx])
            delete e.empty; delete e.closesubmenu; delete e.submenu
            delete e.action; delete e.repeat
            if (t === "command") {
                e.icon = e.icon || ""
                e.action = ""
            } else if (t === "submenu") {
                e.icon = e.icon || ""
                e.submenu = (editorWindow.submenuNames.length > 0) ? editorWindow.submenuNames[0] : ""
            } else if (t === "exit") {
                e.icon = e.icon || "\uf060"
            } else {
                // empty
                e = { empty: true }
            }
            arr[idx] = e
        })
    }

    function addEntry() {
        updateItems(function (arr) {
            arr.push({ icon: "", action: "" })
        })
        selectedIndex = items.length - 1
    }

    function removeEntry(idx) {
        if (idx < 0 || idx >= items.length) return
        updateItems(function (arr) {
            arr.splice(idx, 1)
        })
        if (selectedIndex >= items.length) selectedIndex = items.length - 1
    }

    function moveEntry(idx, dir) {
        var j = idx + dir
        if (idx < 0 || idx >= items.length || j < 0 || j >= items.length) return
        updateItems(function (arr) {
            var tmp = arr[idx]; arr[idx] = arr[j]; arr[j] = tmp
        })
        selectedIndex = j
    }

    // ---- Submenu management ----
    function addSubmenu(name) {
        name = (name || "").trim()
        if (name === "" || (fullConfig.submenus && fullConfig.submenus[name] !== undefined)) return
        commitCurrentMenu()
        var subs = fullConfig.submenus || ({})
        subs[name] = [{ icon: "\uf060", closesubmenu: true }]
        fullConfig.submenus = subs
        submenuNames = Object.keys(subs)
        dirty = true
        loadMenu(name)
    }

    function deleteSubmenu(name) {
        if (!fullConfig.submenus || fullConfig.submenus[name] === undefined) return
        var subs = fullConfig.submenus
        delete subs[name]
        fullConfig.submenus = subs
        submenuNames = Object.keys(subs)
        dirty = true
        if (currentMenu === name) {
            currentMenu = ""
            loadMenu("")
        }
    }

    // ---------------------------------------------------------------
    // Window setup
    // ---------------------------------------------------------------
    function openEditor() {
        loadConfig()
        visible = true
        rootFocus.forceActiveFocus()
    }

    function closeEditor() {
        visible = false
    }

    visible: false
    color: "transparent"

    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "actionmenu-editor"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    HyprlandFocusGrab {
        active: editorWindow.visible
        windows: [editorWindow]
        onCleared: editorWindow.closeEditor()
    }

    // Dim backdrop; click outside the card closes.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: editorWindow.visible ? 0.5 : 0.0
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuart } }
        MouseArea {
            anchors.fill: parent
            onClicked: editorWindow.closeEditor()
        }
    }

    Item {
        id: rootFocus
        focus: true
        Keys.onEscapePressed: editorWindow.closeEditor()
    }

    // ================================================================
    //  Main card — pure black, 25px outer corners
    // ================================================================
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(1000, parent.width - 80)
        height: Math.min(680, parent.height - 80)
        radius: editorWindow.radiusXl
        color: editorWindow.colBg
        border.width: 1
        border.color: editorWindow.colBorder
        clip: true

        scale: editorWindow.visible ? 1.0 : 0.94
        opacity: editorWindow.visible ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.05 } }
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutQuart } }

        // Swallow clicks so they don't reach the backdrop.
        MouseArea { anchors.fill: parent; onClicked: {} }

        // ---------- Header ----------
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 26
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: "\uf013"  // gear
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: 20
                    color: editorWindow.colAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: "Action Ring"
                        font.family: "Inter, sans-serif"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        color: editorWindow.colText
                    }
                    Text {
                        text: editorWindow.currentMenu === "" ? "Main menu" : ("Submenu · " + editorWindow.currentMenu)
                        font.pixelSize: 11
                        color: editorWindow.colTextDim
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: editorWindow.statusText
                    color: editorWindow.statusText === "Saved" ? editorWindow.colGreen : editorWindow.colTextDim
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: editorWindow.statusText !== "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                PillButton {
                    text: editorWindow.dirty ? "Save" : "Saved"
                    accent: editorWindow.colGreen
                    filled: editorWindow.dirty
                    enabled: editorWindow.dirty
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: editorWindow.save()
                }

                IconButton {
                    glyph: "\uf00d"  // close
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: editorWindow.closeEditor()
                }
            }
        }

        // header separator
        Rectangle {
            anchors { top: header.bottom; left: parent.left; right: parent.right }
            height: 1
            color: editorWindow.colBorder
            opacity: 0.6
        }

        // ---------- Body ----------
        Item {
            anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }

            // =====================================================
            //  LEFT: live ring preview
            // =====================================================
            Item {
                id: ringPane
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: parent.width - 360

                // Menu selector chips (top of the ring pane)
                Flow {
                    id: menuChips
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: 18
                    spacing: 6

                    Chip {
                        text: "Main"
                        active: editorWindow.currentMenu === ""
                        onClicked: editorWindow.loadMenu("")
                    }
                    Repeater {
                        model: editorWindow.submenuNames
                        Chip {
                            required property var modelData
                            text: modelData
                            active: editorWindow.currentMenu === modelData
                            deletable: true
                            onClicked: editorWindow.loadMenu(modelData)
                            onDeleteClicked: editorWindow.deleteSubmenu(modelData)
                        }
                    }
                    Chip {
                        text: "+ Submenu"
                        accentText: true
                        onClicked: newSubmenuPopup.open()
                    }
                }

                // The ring itself, centered in the remaining space
                Item {
                    id: ringArea
                    anchors { top: menuChips.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }

                    // ring container sized to fit the radius + circle
                    Item {
                        id: ringVisual
                        anchors.centerIn: parent
                        // scale the live ring up a touch so it reads as a hero element
                        property real previewScale: 1.35
                        property real ringR: editorWindow.ringRadius * previewScale
                        property real ringC: editorWindow.ringCircleSize * previewScale
                        width: (ringR + ringC / 2) * 2
                        height: width

                        // subtle guide circle showing the ring path
                        Rectangle {
                            anchors.centerIn: parent
                            width: ringVisual.ringR * 2
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: editorWindow.colBorder
                            opacity: 0.5
                        }

                        // center hub: add entry
                        Rectangle {
                            id: hub
                            anchors.centerIn: parent
                            width: ringVisual.ringC * 0.92
                            height: width
                            radius: width / 2
                            color: hubHover.hovered ? editorWindow.colHover : editorWindow.colSurface
                            border.width: 1
                            border.color: editorWindow.colBorder
                            Behavior on color { ColorAnimation { duration: 120 } }
                            HoverHandler { id: hubHover }
                            TapHandler { onTapped: editorWindow.addEntry() }
                            Text {
                                anchors.centerIn: parent
                                text: "\uf067"  // plus
                                font.family: "Symbols Nerd Font"
                                font.pixelSize: ringVisual.ringC * 0.34
                                color: editorWindow.colAccent
                            }
                        }

                        // the radial entries — replicates RadialMenu geometry exactly
                        Repeater {
                            model: editorWindow.items

                            Item {
                                id: slot
                                required property int index
                                required property var modelData

                                property int count: editorWindow.items.length
                                property real angle: index * (360 / Math.max(count, 1)) - 90
                                property real angleRad: angle * Math.PI / 180
                                property bool sel: editorWindow.selectedIndex === index
                                property string t: editorWindow.entryType(modelData)
                                property bool isEmpty: t === "empty"

                                width: ringVisual.ringC
                                height: ringVisual.ringC
                                x: (ringVisual.width / 2) + ringVisual.ringR * Math.cos(angleRad) - width / 2
                                y: (ringVisual.height / 2) + ringVisual.ringR * Math.sin(angleRad) - height / 2

                                // pop selected/hovered outward slightly
                                property real lift: sel ? 10 : (slotHover.hovered ? 5 : 0)
                                transform: Translate {
                                    x: slot.lift * Math.cos(slot.angleRad)
                                    y: slot.lift * Math.sin(slot.angleRad)
                                }
                                Behavior on lift { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 3 } }

                                // the circle (dashed outline for empty slots so they stay editable)
                                Rectangle {
                                    id: circle
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: slot.isEmpty
                                           ? "transparent"
                                           : (slotHover.hovered ? editorWindow.ringHoverColor : editorWindow.ringItemColor)
                                    border.width: slot.sel ? 2 : (slot.isEmpty ? 1 : 0)
                                    border.color: slot.sel ? editorWindow.colAccent
                                                  : (slot.isEmpty ? Qt.rgba(editorWindow.colTextDim.r, editorWindow.colTextDim.g, editorWindow.colTextDim.b, 0.5) : "transparent")
                                    scale: (slotHover.hovered || slot.sel) ? 1.12 : 1.0
                                    Behavior on color { ColorAnimation { duration: 90; easing.type: Easing.OutQuart } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 4 } }

                                    // glyph
                                    Text {
                                        anchors.centerIn: parent
                                        text: (slot.modelData && slot.modelData.icon)
                                              ? slot.modelData.icon
                                              : (slot.isEmpty ? "" : editorWindow.typeIcon(slot.t))
                                        font.family: "Symbols Nerd Font"
                                        font.pixelSize: ringVisual.ringC * 0.42
                                        color: slot.isEmpty ? editorWindow.colTextDim : editorWindow.ringIconColor
                                        opacity: (slot.modelData && slot.modelData.icon) ? 1.0 : 0.55
                                    }

                                    // type tint dot (top-right) so types are distinguishable at a glance
                                    Rectangle {
                                        visible: !slot.isEmpty
                                        width: 12; height: 12; radius: 6
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 2
                                        color: editorWindow.typeColor(slot.t)
                                        border.width: 2
                                        border.color: editorWindow.colBg
                                    }

                                    // repeat indicator (bottom-right)
                                    Rectangle {
                                        visible: slot.modelData && slot.modelData.repeat === true
                                        width: 16; height: 16; radius: 8
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 0
                                        color: editorWindow.colGreen
                                        border.width: 2
                                        border.color: editorWindow.colBg
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\uf01e"
                                            font.family: "Symbols Nerd Font"
                                            font.pixelSize: 8
                                            color: editorWindow.colBg
                                        }
                                    }
                                }

                                HoverHandler { id: slotHover }
                                TapHandler { onTapped: editorWindow.selectedIndex = slot.index }

                                // slot number label, just outside the circle
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (slot.index + 1)
                                    font.pixelSize: 9
                                    color: editorWindow.colTextDim
                                    opacity: 0
                                }
                            }
                        }
                    }

                }
            }

            // vertical divider
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom }
                x: ringPane.width
                width: 1
                color: editorWindow.colBorder
                opacity: 0.6
            }

            // =====================================================
            //  RIGHT: inspector
            // =====================================================
            Item {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: 359

                // Empty state
                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    width: parent.width - 48
                    visible: editorWindow.selectedIndex < 0 || editorWindow.selectedIndex >= editorWindow.items.length
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\uf192"  // dot-circle
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: 40
                        color: editorWindow.colBorder
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Select an entry in the ring to edit it, or use the center hub to add one."
                        color: editorWindow.colTextDim
                        font.pixelSize: 13
                    }
                }

                // Inspector
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 22
                    contentHeight: inspectorCol.height
                    clip: true
                    visible: editorWindow.selectedIndex >= 0 && editorWindow.selectedIndex < editorWindow.items.length
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    property var entry: (editorWindow.selectedIndex >= 0 && editorWindow.selectedIndex < editorWindow.items.length)
                                        ? editorWindow.items[editorWindow.selectedIndex] : null
                    property string etype: editorWindow.entryType(entry)
                    id: inspector

                    Column {
                        id: inspectorCol
                        width: parent.width
                        spacing: 18

                        // header row with move/delete
                        Row {
                            width: parent.width
                            Column {
                                spacing: 2
                                Text {
                                    text: "ENTRY " + (editorWindow.selectedIndex + 1)
                                    color: editorWindow.colTextDim
                                    font.pixelSize: 11
                                    font.letterSpacing: 1.5
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: editorWindow.typeLabel(inspector.etype)
                                    color: editorWindow.typeColor(inspector.etype)
                                    font.pixelSize: 20
                                    font.weight: Font.DemiBold
                                }
                            }
                            Item { width: parent.width - 320; height: 1 }
                            Row {
                                spacing: 8
                                anchors.verticalCenter: parent.verticalCenter
                                IconButton {
                                    glyph: "\uf0d9"  // prev (counter-clockwise)
                                    small: true
                                    enabled: editorWindow.selectedIndex > 0
                                    onClicked: editorWindow.moveEntry(editorWindow.selectedIndex, -1)
                                }
                                IconButton {
                                    glyph: "\uf0da"  // next (clockwise)
                                    small: true
                                    enabled: editorWindow.selectedIndex < editorWindow.items.length - 1
                                    onClicked: editorWindow.moveEntry(editorWindow.selectedIndex, 1)
                                }
                                IconButton {
                                    glyph: "\uf1f8"  // trash
                                    small: true
                                    danger: true
                                    onClicked: editorWindow.removeEntry(editorWindow.selectedIndex)
                                }
                            }
                        }

                        // Type selector
                        Column {
                            width: parent.width
                            spacing: 8
                            FieldLabel { text: "Type" }
                            Grid {
                                width: parent.width
                                columns: 2
                                rowSpacing: 8
                                columnSpacing: 8
                                Repeater {
                                    model: ["command", "submenu", "exit", "empty"]
                                    TypeButton {
                                        required property var modelData
                                        typeId: modelData
                                        label: editorWindow.typeLabel(modelData)
                                        glyph: editorWindow.typeIcon(modelData)
                                        accent: editorWindow.typeColor(modelData)
                                        active: inspector.etype === modelData
                                        width: (inspector.width - 8) / 2
                                        onClicked: editorWindow.setEntryType(editorWindow.selectedIndex, modelData)
                                    }
                                }
                            }
                        }

                        // Icon field (hidden for empty)
                        Column {
                            width: parent.width
                            spacing: 8
                            visible: inspector.etype !== "empty"
                            FieldLabel { text: "Icon (Nerd Font glyph)" }
                            Row {
                                width: parent.width
                                spacing: 12
                                Rectangle {
                                    width: 54; height: 54; radius: 27
                                    color: editorWindow.ringItemColor
                                    border.width: 1; border.color: editorWindow.colBorder
                                    Text {
                                        anchors.centerIn: parent
                                        text: (inspector.entry && inspector.entry.icon) ? inspector.entry.icon : ""
                                        font.family: "Symbols Nerd Font"
                                        font.pixelSize: 24
                                        color: editorWindow.ringIconColor
                                    }
                                }
                                TextFieldBox {
                                    width: parent.width - 66
                                    placeholder: "Paste a glyph, e.g.  \uf013"
                                    text: (inspector.entry && inspector.entry.icon) ? inspector.entry.icon : ""
                                    onTextEdited: t => editorWindow.setEntryField(editorWindow.selectedIndex, "icon", t)
                                }
                            }
                        }

                        // Command field (command type only)
                        Column {
                            width: parent.width
                            spacing: 8
                            visible: inspector.etype === "command"
                            FieldLabel { text: "Command" }
                            TextFieldBox {
                                width: parent.width
                                placeholder: "e.g.  playerctl play-pause"
                                multiline: true
                                text: (inspector.entry && inspector.entry.action !== undefined) ? inspector.entry.action : ""
                                onTextEdited: t => editorWindow.setEntryField(editorWindow.selectedIndex, "action", t)
                            }
                        }

                        // Repeat toggle (command type only)
                        Row {
                            width: parent.width
                            spacing: 14
                            visible: inspector.etype === "command"
                            Column {
                                width: parent.width - 70
                                spacing: 2
                                FieldLabel { text: "Repeated action" }
                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    text: "Pull outward and pump to fire repeatedly (volume, brightness…). The menu stays open."
                                    color: editorWindow.colTextDim
                                    font.pixelSize: 11
                                }
                            }
                            ToggleSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: inspector.entry && inspector.entry.repeat === true
                                onToggled: v => editorWindow.setEntryField(editorWindow.selectedIndex, "repeat", v ? true : undefined)
                            }
                        }

                        // Submenu target selector (submenu type only)
                        Column {
                            width: parent.width
                            spacing: 8
                            visible: inspector.etype === "submenu"
                            FieldLabel { text: "Opens submenu" }
                            Flow {
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    model: editorWindow.submenuNames
                                    Chip {
                                        required property var modelData
                                        text: modelData
                                        active: inspector.entry && inspector.entry.submenu === modelData
                                        onClicked: editorWindow.setEntryField(editorWindow.selectedIndex, "submenu", modelData)
                                    }
                                }
                                Chip {
                                    text: "+ New"
                                    accentText: true
                                    onClicked: newSubmenuPopup.open()
                                }
                            }
                            Text {
                                visible: editorWindow.submenuNames.length === 0
                                text: "No submenus yet — create one first."
                                color: editorWindow.colTextDim
                                font.pixelSize: 12
                            }
                        }

                        // Exit submenu info
                        Column {
                            width: parent.width
                            spacing: 8
                            visible: inspector.etype === "exit"
                            Rectangle {
                                width: parent.width
                                height: infoText.height + 24
                                radius: editorWindow.radiusMd
                                color: editorWindow.colSurface
                                border.width: 1; border.color: editorWindow.colBorder
                                Text {
                                    id: infoText
                                    anchors.left: parent.left; anchors.leftMargin: 14
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    wrapMode: Text.WordWrap
                                    text: "This entry returns to the parent menu when pulled. Only the icon is configurable."
                                    color: editorWindow.colTextDim
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Item { width: 1; height: 8 }
                    }
                }
            }
        }

        // ---- New submenu popup ----
        Rectangle {
            id: newSubmenuPopup
            anchors.centerIn: parent
            width: 360
            height: 170
            radius: editorWindow.radiusLg
            color: editorWindow.colSurface
            border.width: 1; border.color: editorWindow.colBorder
            visible: false
            z: 100

            function open() { nameInput.text = ""; visible = true; nameInput.forceActiveFocus() }
            function dismiss() { visible = false }

            // dim behind the popup + swallow clicks
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                Text {
                    text: "New submenu"
                    color: editorWindow.colText
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                TextFieldBox {
                    id: nameInput
                    width: parent.width
                    placeholder: "submenu name (e.g. media)"
                    onAccepted: { editorWindow.addSubmenu(nameInput.text); newSubmenuPopup.dismiss() }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 10
                    PillButton {
                        text: "Cancel"
                        filled: false
                        accent: editorWindow.colTextDim
                        onClicked: newSubmenuPopup.dismiss()
                    }
                    PillButton {
                        text: "Create"
                        filled: true
                        accent: editorWindow.colGreen
                        onClicked: { editorWindow.addSubmenu(nameInput.text); newSubmenuPopup.dismiss() }
                    }
                }
            }
        }
    }

    // ===================================================================
    // Reusable UI components
    // ===================================================================
    component FieldLabel: Text {
        color: editorWindow.colTextDim
        font.pixelSize: 12
        font.letterSpacing: 0.5
        font.weight: Font.DemiBold
    }

    component PillButton: Rectangle {
        id: pb
        property string text: ""
        property color accent: editorWindow.colAccent
        property bool filled: true
        property bool enabled: true
        signal clicked()
        implicitWidth: pbText.implicitWidth + 34
        implicitHeight: 34
        radius: height / 2
        color: !enabled ? editorWindow.colSurface
               : filled ? (pbHover.hovered ? Qt.lighter(accent, 1.12) : accent)
               : (pbHover.hovered ? editorWindow.colHover : "transparent")
        border.width: filled ? 0 : 1
        border.color: editorWindow.colBorder
        opacity: enabled ? 1.0 : 0.5
        Behavior on color { ColorAnimation { duration: 110 } }
        HoverHandler { id: pbHover; enabled: pb.enabled }
        TapHandler { enabled: pb.enabled; onTapped: pb.clicked() }
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.text
            font.pixelSize: 13
            font.weight: Font.Medium
            color: pb.filled ? editorWindow.colBg : editorWindow.colText
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string glyph: ""
        property bool small: false
        property bool danger: false
        property bool enabled: true
        signal clicked()
        implicitWidth: small ? 32 : 36
        implicitHeight: small ? 32 : 36
        radius: editorWindow.radiusSm
        color: ibHover.hovered && enabled
               ? (danger ? Qt.rgba(0.98, 0.29, 0.20, 0.18) : editorWindow.colHover)
               : "transparent"
        opacity: enabled ? 1.0 : 0.4
        Behavior on color { ColorAnimation { duration: 110 } }
        HoverHandler { id: ibHover; enabled: ib.enabled }
        TapHandler { enabled: ib.enabled; onTapped: ib.clicked() }
        Text {
            anchors.centerIn: parent
            text: ib.glyph
            font.family: "Symbols Nerd Font"
            font.pixelSize: ib.small ? 13 : 15
            color: ib.danger ? editorWindow.colRed : editorWindow.colTextDim
        }
    }

    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool active: false
        property bool deletable: false
        property bool accentText: false
        signal clicked()
        signal deleteClicked()
        implicitWidth: chipRow.implicitWidth + 22
        implicitHeight: 30
        radius: 15
        color: active ? editorWindow.colAccent
               : (chipHover.hovered ? editorWindow.colHover : editorWindow.colSurface)
        border.width: active ? 0 : 1
        border.color: editorWindow.colBorder
        Behavior on color { ColorAnimation { duration: 110 } }
        HoverHandler { id: chipHover }
        TapHandler { onTapped: chip.clicked() }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: chip.text
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 12
                font.weight: chip.active ? Font.DemiBold : Font.Normal
                color: chip.active ? editorWindow.colBg
                       : (chip.accentText ? editorWindow.colAccent : editorWindow.colText)
            }
            Text {
                visible: chip.deletable
                text: "\uf00d"
                anchors.verticalCenter: parent.verticalCenter
                font.family: "Symbols Nerd Font"
                font.pixelSize: 10
                color: chip.active ? editorWindow.colBg : editorWindow.colTextDim
                TapHandler { onTapped: chip.deleteClicked() }
            }
        }
    }

    component TypeButton: Rectangle {
        id: tb
        property string typeId: ""
        property string label: ""
        property string glyph: ""
        property color accent: editorWindow.colAccent
        property bool active: false
        signal clicked()
        implicitHeight: 60
        radius: editorWindow.radiusMd
        color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
               : (tbHover.hovered ? editorWindow.colHover : editorWindow.colSurface)
        border.width: active ? 1.5 : 1
        border.color: active ? accent : editorWindow.colBorder
        Behavior on color { ColorAnimation { duration: 110 } }
        HoverHandler { id: tbHover }
        TapHandler { onTapped: tb.clicked() }
        Row {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.glyph
                font.family: "Symbols Nerd Font"
                font.pixelSize: 17
                color: tb.active ? tb.accent : editorWindow.colTextDim
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tb.label
                font.pixelSize: 12
                font.weight: tb.active ? Font.DemiBold : Font.Normal
                color: tb.active ? editorWindow.colText : editorWindow.colTextDim
            }
        }
    }

    component TextFieldBox: Rectangle {
        id: tfb
        // `text` is a pure INPUT — bind it to the data model; never write back into it.
        property string text: ""
        property string placeholder: ""
        property bool multiline: false
        signal textEdited(string t)
        signal accepted()
        implicitWidth: 200
        implicitHeight: multiline ? 84 : 40
        radius: editorWindow.radiusMd
        color: editorWindow.colSurface
        border.width: 1
        border.color: (singleField.activeFocus || multiField.activeFocus)
                      ? editorWindow.colAccent : editorWindow.colBorder
        Behavior on border.color { ColorAnimation { duration: 120 } }

        // Keep the internal fields in sync with `text` without breaking their own
        // user-edit bindings.  We use Binding with restoreMode: Binding.RestoreNone so
        // the declarative value wins whenever `text` changes from outside, but user
        // keystrokes (which only call textEdited and update the *model*, not `text`
        // directly) are not overwritten mid-typing.
        Binding {
            target: singleField
            property: "text"
            value: tfb.text
            when: !singleField.activeFocus
        }
        Binding {
            target: multiField
            property: "text"
            value: tfb.text
            when: !multiField.activeFocus
        }

        TextField {
            id: singleField
            anchors.fill: parent
            visible: !tfb.multiline
            enabled: !tfb.multiline
            text: tfb.text
            onTextEdited: tfb.textEdited(text)
            onAccepted: tfb.accepted()
            placeholderText: tfb.placeholder
            color: editorWindow.colText
            placeholderTextColor: editorWindow.colTextDim
            font.pixelSize: 13
            leftPadding: 12; rightPadding: 12
            verticalAlignment: TextInput.AlignVCenter
            background: Item {}
            selectByMouse: true
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 6
            visible: tfb.multiline
            enabled: tfb.multiline
            TextArea {
                id: multiField
                text: tfb.text
                onTextChanged: {
                    if (activeFocus) tfb.textEdited(text)
                }
                placeholderText: tfb.placeholder
                color: editorWindow.colText
                placeholderTextColor: editorWindow.colTextDim
                font.pixelSize: 13
                wrapMode: TextArea.Wrap
                background: Item {}
                selectByMouse: true
            }
        }
    }

    component ToggleSwitch: Rectangle {
        id: ts
        property bool checked: false
        signal toggled(bool v)
        implicitWidth: 50
        implicitHeight: 28
        radius: 14
        color: checked ? editorWindow.colGreen : editorWindow.colSurface2
        border.width: 1
        border.color: checked ? editorWindow.colGreen : editorWindow.colBorder
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            width: 22; height: 22; radius: 11
            y: 3
            x: ts.checked ? ts.width - width - 3 : 3
            color: ts.checked ? editorWindow.colBg : editorWindow.colTextDim
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.5 } }
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        TapHandler { onTapped: { ts.checked = !ts.checked; ts.toggled(ts.checked) } }
    }
}
