import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: "Kumi " + Qt.application.version
    width: 600
    height: 700

    property int previousWindowWidth: 600
    property int currentSectionIndex: -1
    property bool isEditorView: false
    property bool isAnalyticsView: false
    property bool isSettingsView: false
    property var activeIconTarget: null
    property var masterEditableConfig: []
    property int selectedEditorSectionIndex: 0
    property var pendingActionItem: null
    property var parentItemContext: null

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: !processRunner.running
        onActivated: root.close()
    }

    function navigateToPage(component, properties) {
        if (pageStack.depth > 0) {
            pageStack.replace(component, properties || {})
        } else {
            pageStack.push(component, properties || {})
        }
    }

    function findPathInItems(items, targetItem, currentPath) {
        if (!items) return null
        for (var i = 0; i < items.length; i++) {
            var entry = items[i]
            if (entry.type === "submenu") {
                var subResult = findPathInItems(entry.items, targetItem, currentPath.concat([entry.name]))
                if (subResult !== null) {
                    return subResult
                }
            } else {
                if (entry === targetItem ||
                    (entry.name === targetItem.name &&
                     entry.command === targetItem.command &&
                     (entry.arguments || "") === (targetItem.arguments || ""))) {
                    return currentPath
                }
            }
        }
        return null
    }

    function buildItemPrefix(targetItem) {
        if (!targetItem || !backend.sections) return ""
        if (root.currentSectionIndex >= 0 && root.currentSectionIndex < backend.sections.length) {
            var activeSec = backend.sections[root.currentSectionIndex]
            var activePath = findPathInItems(activeSec.items, targetItem, [activeSec.title])
            if (activePath !== null) {
                return activePath.join(" / ")
            }
        }
        for (var s = 0; s < backend.sections.length; s++) {
            var sec = backend.sections[s]
            var foundPath = findPathInItems(sec.items, targetItem, [sec.title])
            if (foundPath !== null) {
                return foundPath.join(" / ")
            }
        }
        return targetItem.breadcrumb || ""
    }

    function recordExecutionWithPrefix(item, args) {
        var copy = JSON.parse(JSON.stringify(item))
        var prefix = buildItemPrefix(item)
        if (prefix.length > 0 && copy.name.indexOf(prefix + " / ") !== 0) {
            copy.breadcrumb = prefix
            copy.name = prefix + " / " + copy.name
        }
        backend.record_history(copy, args)
    }

    function executeActionItem(item) {
        if (!item || !item.command) {
            return
        }
        var shouldPrompt = backend.promptArguments || Boolean(item.prompt_arguments)
        if (shouldPrompt) {
            pendingActionItem = item
            argsComboBox.editText = item.arguments || ""
            paramsDialog.open()
        } else {
            var defaultArgs = item.arguments || ""
            var isDetached = Boolean(item.detached)
            recordExecutionWithPrefix(item, defaultArgs)

            if (isDetached) {
                processRunner.start_command_with_args(item.name, item.command, defaultArgs, true, false)
            } else {
                terminalOutput.text = ""
                runningCommandTitle.text = "Executing: " + item.name
                parentItemContext = item

                if (Boolean(item.show_output)) {
                    terminalDialog.open()
                }

                processRunner.start_command_with_args(item.name, item.command, defaultArgs, false, item.notify === undefined ? true : Boolean(item.notify))
            }
        }
    }

    Connections {
        target: backend
        function onStatusNotification(message, isSuccess) {
            root.showPassiveNotification(message, isSuccess ? "short" : "long")
        }
    }

    Repeater {
        model: backend.get_shortcut_assignments()
        delegate: Shortcut {
            sequence: backend.shortcutModifier + "+" + modelData.shortcutId
            enabled: modelData.item !== null && modelData.item !== undefined && modelData.item.command !== undefined
            onActivated: {
                var item = modelData.item
                if (item && item.command) {
                    var defaultArgs = item.arguments || ""
                    var isDetached = Boolean(item.detached)
                    root.recordExecutionWithPrefix(item, defaultArgs)
                    if (isDetached) {
                        processRunner.start_command_with_args(item.name, item.command, defaultArgs, true, false)
                    } else {
                        terminalOutput.text = ""
                        runningCommandTitle.text = "Executing: " + item.name
                        parentItemContext = item

                        if (Boolean(item.show_output)) {
                            terminalDialog.open()
                        }

                        processRunner.start_command_with_args(item.name, item.command, defaultArgs, false, item.notify === undefined ? true : Boolean(item.notify))
                    }
                }
            }
        }
    }

    Dialog {
        id: iconPickerDialog
        title: "Select System Icon"
        modal: true
        standardButtons: Dialog.Close
        width: 600
        height: 500
        x: (root.width - width) / 2
        y: (root.height - height) / 2

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            Kirigami.SearchField {
                id: iconSearchField
                Layout.fillWidth: true
                placeholderText: "Search icon..."
                onTextChanged: {
                    iconGridView.model = backend.get_system_icons(text)
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                GridView {
                    id: iconGridView
                    cellWidth: 80
                    cellHeight: 80
                    model: backend.get_system_icons("")

                    delegate: Item {
                        width: 80
                        height: 80

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            Kirigami.Icon {
                                source: modelData
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                            }

                            Label {
                                text: modelData
                                font.pointSize: 8
                                elide: Text.ElideMiddle
                                Layout.preferredWidth: 70
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.activeIconTarget) {
                                    root.activeIconTarget.text = modelData
                                }
                                iconPickerDialog.close()
                            }
                        }
                    }
                }
            }
        }
    }

    FileDialog {
        id: exportConfigDialog
        title: "Export Backup Configuration"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["JSON Files (*.json)"]
        onAccepted: backend.export_configuration(selectedFile)
    }

    FileDialog {
        id: importConfigDialog
        title: "Import Backup Configuration"
        fileMode: FileDialog.OpenFile
        nameFilters: ["JSON Files (*.json)"]
        onAccepted: {
            if (backend.import_configuration(selectedFile)) {
                root.masterEditableConfig = JSON.parse(JSON.stringify(backend.sections))
                root.selectedEditorSectionIndex = 0
                if (root.isEditorView) {
                    root.navigateToPage(visualEditorUnifiedComponent)
                }
            }
        }
    }

    Dialog {
        id: paramsDialog
        title: "Execution Parameters"
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        width: 500
        height: 320
        x: (root.width - width) / 2
        y: (root.height - height) / 2

        onOpened: {
            if (pendingActionItem) {
                var history = backend.get_arguments_history(pendingActionItem.command)
                argsComboBox.model = history
                argsComboBox.editText = pendingActionItem.arguments || (history.length > 0 ? history[0] : "")
            }
        }

        onAccepted: {
            if (pendingActionItem) {
                var selectedArgs = argsComboBox.editText
                var isDetached = Boolean(pendingActionItem.detached)
                root.recordExecutionWithPrefix(pendingActionItem, selectedArgs)

                if (isDetached) {
                    processRunner.start_command_with_args(pendingActionItem.name, pendingActionItem.command, selectedArgs, true, false)
                } else {
                    terminalOutput.text = ""
                    runningCommandTitle.text = "Executing: " + pendingActionItem.name
                    parentItemContext = pendingActionItem

                    if (Boolean(pendingActionItem.show_output)) {
                        terminalDialog.open()
                    }

                    processRunner.start_command_with_args(pendingActionItem.name, pendingActionItem.command, selectedArgs, false, pendingActionItem.notify === undefined ? true : Boolean(pendingActionItem.notify))
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.mediumSpacing

            Label {
                text: pendingActionItem ? "Configure arguments for: " + pendingActionItem.name : ""
                font.bold: true
                Layout.fillWidth: true
            }

            Label {
                visible: backend.showCommand
                text: "Base command: " + (pendingActionItem ? pendingActionItem.command : "")
                opacity: 0.7
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                Layout.fillWidth: true
                elide: Text.ElideMiddle
            }

            Label {
                text: "Custom arguments:"
                Layout.fillWidth: true
            }

            ComboBox {
                id: argsComboBox
                Layout.fillWidth: true
                editable: true
                model: []
            }
        }
    }

    Connections {
        target: processRunner
        function onNotificationError(message) {
            console.error(message)
            root.showPassiveNotification(message, "long")
        }
        function onOutputReceived(data) {
            terminalOutput.text += data
            terminalOutput.cursorPosition = terminalOutput.length
        }
        function onProcessFinished(exitCode, message) {
            terminalOutput.text += message
            terminalOutput.cursorPosition = terminalOutput.length
            var explicitShow = parentItemContext && Boolean(parentItemContext.show_output)

            if (exitCode !== 0) {
                runningCommandTitle.text = runningCommandTitle.text + " (Failed with exit code " + exitCode + ")"
                if (!terminalDialog.opened) {
                    terminalDialog.open()
                }
            } else {
                runningCommandTitle.text = runningCommandTitle.text + " (Completed successfully)"
                root.showPassiveNotification("Command completed successfully", "short")
                if (!explicitShow && terminalDialog.opened) {
                    terminalDialog.close()
                }
            }
        }
    }

    FileDialog {
        id: saveFileDialog
        title: "Save Console Output"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Text Files (*.txt)"]
        onAccepted: processRunner.save_text_to_file(selectedFile, terminalOutput.text)
    }

    Dialog {
        id: terminalDialog
        objectName: "terminalDialog"
        title: "Live Process Output (STDOUT & STDERR)"
        modal: true
        closePolicy: processRunner.running ? Popup.CloseOnPressOutside
                                           : Popup.CloseOnPressOutside | Popup.CloseOnEscape
        width: Math.min(root.width * 0.8, 700)
        height: Math.min(root.height * 0.8, 500)
        x: (root.width - width) / 2
        y: (root.height - height) / 2

        onClosed: processRunner.terminate_process()

        footer: DialogButtonBox {
            Button {
                objectName: "processActionButton"
                text: processRunner.running ? "Abort" : "Close"
                focusPolicy: Qt.NoFocus
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                onClicked: {
                    if (processRunner.running) {
                        processRunner.terminate_process()
                    } else {
                        terminalDialog.close()
                    }
                }
            }
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                BusyIndicator {
                    running: processRunner.running
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                }

                Label {
                    id: runningCommandTitle
                    text: "Executing command..."
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                }

                Button {
                    text: "Save Log"
                    icon.name: "document-save"
                    focusPolicy: Qt.NoFocus
                    onClicked: saveFileDialog.open()
                }

            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true

                TextArea {
                    id: terminalOutput
                    readOnly: true
                    font.family: "Monospace"
                    font.pointSize: 10
                    wrapMode: TextArea.Wrap
                    selectByMouse: true
                    background: Rectangle {
                        color: Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.separatorColor
                    }
                }
            }
        }
    }

    globalDrawer: Kirigami.GlobalDrawer {
        id: drawer
        title: "Options"
        titleIcon: "applications-other"
        isMenu: false
        modal: false

        contentItem: ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.NavigationTabButton {
                Layout.fillWidth: true
                text: "Recent"
                icon.name: "bookmarks"
                enabled: !root.isEditorView
                checked: root.currentSectionIndex === -1 && !root.isEditorView && !root.isAnalyticsView && !root.isSettingsView
                onClicked: {
                    root.currentSectionIndex = -1
                    root.isEditorView = false
                    root.isAnalyticsView = false
                    root.isSettingsView = false
                    root.navigateToPage(mainPageComponent, {
                        pageTitle: "Recent",
                        menuItems: backend.favorites,
                        isFavoritesView: true
                    })
                }
            }

            MenuSeparator { Layout.fillWidth: true }

            ScrollView {
                id: sectionsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: sectionsScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: backend.sections
                        delegate: Kirigami.NavigationTabButton {
                            Layout.fillWidth: true
                            text: modelData.title
                            icon.name: modelData.icon || "folder"
                            enabled: !root.isEditorView
                            checked: root.currentSectionIndex === index && !root.isEditorView && !root.isAnalyticsView && !root.isSettingsView
                            onClicked: {
                                root.currentSectionIndex = index
                                root.isEditorView = false
                                root.isAnalyticsView = false
                                root.isSettingsView = false
                                root.navigateToPage(mainPageComponent, {
                                    pageTitle: backend.sections[index].title,
                                    menuItems: backend.sections[index].items,
                                    isFavoritesView: false
                                })
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            MenuSeparator { Layout.fillWidth: true }

            Kirigami.NavigationTabButton {
                Layout.fillWidth: true
                text: "Settings"
                icon.name: "preferences-system"
                enabled: !root.isEditorView
                checked: root.isSettingsView || root.isEditorView || root.isAnalyticsView
                onClicked: {
                    root.isEditorView = false
                    root.isAnalyticsView = false
                    root.isSettingsView = true
                    root.navigateToPage(settingsComponent)
                }
            }
        }
    }

    Component.onCompleted: {
        if (backend.favorites.length > 0) {
            root.navigateToPage(mainPageComponent, {
                pageTitle: "Recent",
                menuItems: backend.favorites,
                isFavoritesView: true
            })
        } else if (backend.sections.length > 0) {
            root.currentSectionIndex = 0
            root.navigateToPage(mainPageComponent, {
                pageTitle: backend.sections[0].title,
                menuItems: backend.sections[0].items,
                isFavoritesView: false
            })
        }
    }

    Component {
        id: settingsComponent
        Kirigami.ScrollablePage {
            title: "Settings & Configuration"

            ColumnLayout {
                spacing: Kirigami.Units.largeSpacing
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing

                Kirigami.AbstractCard {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.mediumSpacing
                        Layout.margins: Kirigami.Units.mediumSpacing

                        Label {
                            text: "Menu Management & Insights"
                            font.bold: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.mediumSpacing
                            Layout.fillWidth: true

                            Button {
                                text: "Open Menu Editor"
                                icon.name: "configure"
                                focusPolicy: Qt.NoFocus
                                Layout.fillWidth: true
                                onClicked: {
                                    root.previousWindowWidth = root.width
                                    root.width = 1200
                                    root.isEditorView = true
                                    root.isAnalyticsView = false
                                    root.isSettingsView = false
                                    root.masterEditableConfig = JSON.parse(JSON.stringify(backend.sections))
                                    root.selectedEditorSectionIndex = 0
                                    root.navigateToPage(visualEditorUnifiedComponent)
                                }
                            }

                            Button {
                                text: "View Analytics"
                                icon.name: "office-chart-bar"
                                focusPolicy: Qt.NoFocus
                                Layout.fillWidth: true
                                onClicked: {
                                    root.isEditorView = false
                                    root.isAnalyticsView = true
                                    root.isSettingsView = false
                                    root.navigateToPage(analyticsComponent)
                                }
                            }
                        }
                    }
                }

                Kirigami.AbstractCard {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.mediumSpacing
                        Layout.margins: Kirigami.Units.mediumSpacing

                        Label {
                            text: "Execution & Display Options"
                            font.bold: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.mediumSpacing

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: "Always prompt for arguments before running"
                                }

                                Label {
                                    text: "Force the argument input dialog on every command (when off, only items with 'Ask Args' enabled in the editor will prompt)."
                                    opacity: 0.7
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    wrapMode: Label.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            Switch {
                                id: promptArgsSwitch
                                checked: backend.promptArguments
                                onToggled: {
                                    backend.promptArguments = checked
                                }
                            }
                        }

                        MenuSeparator { Layout.fillWidth: true }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.mediumSpacing

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: "Show shell command under item title"
                                }

                                Label {
                                    text: "Display the raw executable command string inside launcher cards (disabled by default)."
                                    opacity: 0.7
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    wrapMode: Label.WordWrap
                                    Layout.fillWidth: true
                                }
                            }

                            Switch {
                                id: showCommandSwitch
                                checked: backend.showCommand
                                onToggled: {
                                    backend.showCommand = checked
                                }
                            }
                        }
                    }
                }

                Kirigami.AbstractCard {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.mediumSpacing
                        Layout.margins: Kirigami.Units.mediumSpacing

                        Label {
                            text: "Configuration Backup & Restore"
                            font.bold: true
                        }

                        Label {
                            text: "Export your current menu layout and shortcut settings to a JSON file, or restore from a previous backup:"
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            wrapMode: Label.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: Kirigami.Units.mediumSpacing
                            Layout.fillWidth: true

                            Button {
                                text: "Export JSON Backup"
                                icon.name: "document-export"
                                focusPolicy: Qt.NoFocus
                                Layout.fillWidth: true
                                onClicked: exportConfigDialog.open()
                            }

                            Button {
                                text: "Import JSON Backup"
                                icon.name: "document-import"
                                focusPolicy: Qt.NoFocus
                                Layout.fillWidth: true
                                onClicked: importConfigDialog.open()
                            }
                        }
                    }
                }

                Kirigami.AbstractCard {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Kirigami.Units.mediumSpacing
                        Layout.margins: Kirigami.Units.mediumSpacing

                        Label {
                            text: "Global Shortcut Modifier (1 to 9):"
                            font.bold: true
                        }

                        Label {
                            text: "Select modifier keys to avoid desktop environment key collisions:"
                            opacity: 0.7
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            wrapMode: Label.WordWrap
                            Layout.fillWidth: true
                        }

                        ComboBox {
                            id: modifierCombo
                            model: ["Ctrl+Shift", "Ctrl+Alt", "Meta", "Alt"]
                            Layout.preferredWidth: 220

                            Component.onCompleted: {
                                var current = backend.shortcutModifier
                                for (var i = 0; i < model.length; i++) {
                                    if (model[i] === current) {
                                        currentIndex = i
                                        break
                                    }
                                }
                            }

                            onActivated: {
                                backend.shortcutModifier = currentText
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: analyticsComponent
        Kirigami.ScrollablePage {
            title: "Execution Statistics & Frequency"

            function getAvailableFilterPaths() {
                var paths = ["All"]
                function collect(items, prefix) {
                    if (!items) return
                    for (var i = 0; i < items.length; i++) {
                        var it = items[i]
                        if (it.type === "submenu") {
                            var currentPath = prefix + " / " + it.name
                            paths.push(currentPath)
                            collect(it.items, currentPath)
                        }
                    }
                }
                var sections = backend.sections || []
                for (var s = 0; s < sections.length; s++) {
                    var sec = sections[s]
                    paths.push(sec.title)
                    collect(sec.items, sec.title)
                }
                return paths
            }

            header: RowLayout {
                Layout.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                Button {
                    text: "Back to Settings"
                    icon.name: "go-previous"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        root.isAnalyticsView = false
                        root.isSettingsView = true
                        root.navigateToPage(settingsComponent)
                    }
                }

                Label {
                    text: "Filter by path:"
                    font.bold: true
                }

                ComboBox {
                    id: sectionFilterCombo
                    model: analyticPage.getAvailableFilterPaths()
                    Layout.preferredWidth: 220
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Reset Statistics"
                    icon.name: "edit-clear-history"
                    focusPolicy: Qt.NoFocus
                    onClicked: {
                        backend.reset_execution_stats()
                    }
                }
            }

            id: analyticPage
            ColumnLayout {
                spacing: Kirigami.Units.mediumSpacing
                Layout.fillWidth: true

                Repeater {
                    model: {
                        var filterVal = sectionFilterCombo.currentText
                        var query = filterVal === "All" ? "" : filterVal
                        return backend.get_execution_stats(query)
                    }

                    delegate: Kirigami.AbstractCard {
                        Layout.fillWidth: true

                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Layout.margins: Kirigami.Units.mediumSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.largeSpacing

                                Kirigami.Icon {
                                    source: modelData.icon || "application-x-executable"
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Label {
                                            text: modelData.name
                                            font.bold: true
                                        }
                                        Label {
                                            text: "[" + modelData.section + "]"
                                            opacity: 0.6
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                        }
                                    }

                                    Label {
                                        visible: modelData.breadcrumb !== undefined && modelData.breadcrumb !== ""
                                        text: "Path: " + modelData.breadcrumb
                                        opacity: 0.6
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        visible: backend.showCommand
                                        text: modelData.command
                                        opacity: 0.7
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Label {
                                        text: "Last executed: " + (modelData.last_executed || "N/A")
                                        opacity: 0.5
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                    }
                                }

                                ColumnLayout {
                                    spacing: 2
                                    Layout.alignment: Qt.AlignRight

                                    Label {
                                        text: modelData.count + " executions"
                                        font.bold: true
                                        color: Kirigami.Theme.accentColor
                                        Layout.alignment: Qt.AlignRight
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 12

                                Rectangle {
                                    anchors.fill: parent
                                    color: Kirigami.Theme.backgroundColor
                                    border.color: Kirigami.Theme.separatorColor
                                    radius: 4
                                }

                                Rectangle {
                                    width: parent.width * (modelData.ratio !== undefined ? modelData.ratio : 0)
                                    height: parent.height
                                    color: Kirigami.Theme.accentColor
                                    radius: 4

                                    Behavior on width {
                                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: visualEditorUnifiedComponent
        Kirigami.Page {
            id: editorPage
            title: "Visual Menu Editor"
            padding: 0

            property var editorNavIndices: []
            property int selectedItemIndex: 0
            property bool isRightPanelFocused: false
            property bool focusNewSection: false
            property bool focusNewItem: false

            Component.onCompleted: {
                root.isEditorView = true
            }

            Component.onDestruction: {
                root.isEditorView = false
                root.width = root.previousWindowWidth
            }

            function resolveNode(configTree) {
                if (!configTree || configTree.length === 0) return null
                var secIdx = root.selectedEditorSectionIndex
                if (secIdx < 0 || secIdx >= configTree.length) return null
                var node = configTree[secIdx]
                for (var i = 0; i < editorNavIndices.length; i++) {
                    var idx = editorNavIndices[i]
                    if (!node.items || idx < 0 || idx >= node.items.length) return null
                    node = node.items[idx]
                }
                return node
            }

            function mutateCurrentItems(mutatorFn) {
                var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                var node = resolveNode(list)
                if (!node) return
                if (!node.items) node.items = []
                mutatorFn(node.items, node)
                root.masterEditableConfig = list
            }

            readonly property var activeNode: resolveNode(root.masterEditableConfig)
            readonly property string activeTitle: {
                if (!activeNode) return "No Section Selected"
                return editorNavIndices.length === 0 ? activeNode.title : activeNode.name
            }

            // Editor keyboard shortcuts.
            Shortcut {
                sequence: "Ctrl+Return"
                enabled: root.isEditorView && editorPage.isRightPanelFocused
                onActivated: {
                    var node = editorPage.activeNode
                    if (node && node.items && editorPage.selectedItemIndex >= 0 && editorPage.selectedItemIndex < node.items.length) {
                        var targetItem = node.items[editorPage.selectedItemIndex]
                        if (targetItem && targetItem.type === "submenu") {
                            var next = editorPage.editorNavIndices.slice()
                            next.push(editorPage.selectedItemIndex)
                            editorPage.editorNavIndices = next
                            editorPage.selectedItemIndex = 0
                        }
                    }
                }
            }

            Shortcut {
                sequence: "Ctrl+Up"
                enabled: root.isEditorView
                onActivated: {
                    if (!editorPage.isRightPanelFocused) {
                        if (root.selectedEditorSectionIndex > 0) {
                            var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                            var temp = list[root.selectedEditorSectionIndex]
                            list[root.selectedEditorSectionIndex] = list[root.selectedEditorSectionIndex - 1]
                            list[root.selectedEditorSectionIndex - 1] = temp
                            root.masterEditableConfig = list
                            root.selectedEditorSectionIndex--
                        }
                    } else {
                        if (editorPage.selectedItemIndex > 0) {
                            editorPage.mutateCurrentItems(function(items) {
                                var temp = items[editorPage.selectedItemIndex]
                                items[editorPage.selectedItemIndex] = items[editorPage.selectedItemIndex - 1]
                                items[editorPage.selectedItemIndex - 1] = temp
                            })
                            editorPage.selectedItemIndex--
                        }
                    }
                }
            }

            Shortcut {
                sequence: "Ctrl+Down"
                enabled: root.isEditorView
                onActivated: {
                    if (!editorPage.isRightPanelFocused) {
                        if (root.selectedEditorSectionIndex < root.masterEditableConfig.length - 1) {
                            var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                            var temp = list[root.selectedEditorSectionIndex]
                            list[root.selectedEditorSectionIndex] = list[root.selectedEditorSectionIndex + 1]
                            list[root.selectedEditorSectionIndex + 1] = temp
                            root.masterEditableConfig = list
                            root.selectedEditorSectionIndex++
                        }
                    } else {
                        var node = editorPage.activeNode
                        if (node && node.items && editorPage.selectedItemIndex < node.items.length - 1) {
                            editorPage.mutateCurrentItems(function(items) {
                                var temp = items[editorPage.selectedItemIndex]
                                items[editorPage.selectedItemIndex] = items[editorPage.selectedItemIndex + 1]
                                items[editorPage.selectedItemIndex + 1] = temp
                            })
                            editorPage.selectedItemIndex++
                        }
                    }
                }
            }

            Shortcut {
                sequences: ["Ctrl++", "Ctrl+="]
                enabled: root.isEditorView
                onActivated: {
                    if (!editorPage.isRightPanelFocused && editorPage.editorNavIndices.length === 0) {
                        var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                        list.push({ "title": "New Section", "icon": "folder", "items": [] })
                        editorPage.focusNewSection = true
                        root.masterEditableConfig = list
                        root.selectedEditorSectionIndex = list.length - 1
                    } else if (editorPage.activeNode !== null) {
                        editorPage.focusNewItem = true
                        editorPage.mutateCurrentItems(function(items) {
                            items.push({
                                "name": "New Command",
                                "description": "Description",
                                "icon": "application-x-executable",
                                "type": "action",
                                "command": "echo hello",
                                "arguments": "",
                                "notify": false,
                                "prompt_arguments": false,
                                "detached": false,
                                "show_output": false,
                                "shortcut": 0
                            })
                        })
                        editorPage.selectedItemIndex = editorPage.activeNode.items.length - 1
                        editorPage.isRightPanelFocused = true
                    }
                }
            }

            Shortcut {
                sequences: ["Ctrl+Shift++", "Ctrl+Shift+="]
                enabled: root.isEditorView && editorPage.activeNode !== null
                onActivated: {
                    editorPage.focusNewItem = true
                    editorPage.mutateCurrentItems(function(items) {
                        items.push({
                            "name": "New Submenu",
                            "icon": "folder",
                            "type": "submenu",
                            "items": []
                        })
                    })
                    editorPage.selectedItemIndex = editorPage.activeNode.items.length - 1
                    editorPage.isRightPanelFocused = true
                }
            }

            Shortcut {
                sequence: "Ctrl+Del"
                enabled: root.isEditorView
                onActivated: {
                    if (!editorPage.isRightPanelFocused) {
                        if (root.masterEditableConfig.length > 0) {
                            var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                            list.splice(root.selectedEditorSectionIndex, 1)
                            root.masterEditableConfig = list
                            root.selectedEditorSectionIndex = Math.max(0, list.length - 1)
                        }
                    } else {
                        var node = editorPage.activeNode
                        if (node && node.items && editorPage.selectedItemIndex >= 0 && editorPage.selectedItemIndex < node.items.length) {
                            editorPage.mutateCurrentItems(function(items) {
                                items.splice(editorPage.selectedItemIndex, 1)
                            })
                            editorPage.selectedItemIndex = Math.max(0, editorPage.selectedItemIndex - 1)
                        }
                    }
                }
            }

            Shortcut {
                sequence: "Ctrl+S"
                enabled: root.isEditorView
                onActivated: {
                    var payload = { "sections": root.masterEditableConfig }
                    if (backend.save_configuration_json(JSON.stringify(payload, null, 4))) {
                        root.showPassiveNotification("Configuration saved successfully", "short")
                    }
                }
            }

            header: ToolBar {
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.mediumSpacing

                    Button {
                        text: "Back to Settings"
                        icon.name: "go-previous"
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            root.isEditorView = false
                            root.isSettingsView = true
                            root.width = root.previousWindowWidth
                            root.navigateToPage(settingsComponent)
                        }
                    }

                    Label {
                        text: editorPage.editorNavIndices.length === 0
                              ? "Main Sections (Root)"
                              : "Submenu: " + editorPage.activeTitle
                        opacity: 0.7
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                    }

                    Button {
                        text: "Save All Changes"
                        icon.name: "document-save"
                        highlighted: true
                        focusPolicy: Qt.NoFocus
                        onClicked: {
                            var payload = { "sections": root.masterEditableConfig }
                            if (backend.save_configuration_json(JSON.stringify(payload, null, 4))) {
                                root.showPassiveNotification("Configuration saved successfully", "short")
                            }
                        }
                    }
                }
            }

            SplitView {
                id: mainEditorSplitView
                anchors.fill: parent
                orientation: Qt.Horizontal

                handle: Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    color: SplitHandle.pressed ? Kirigami.Theme.highlightColor
                         : (SplitHandle.hovered ? Kirigami.Theme.hoverColor : Kirigami.Theme.separatorColor)

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2
                        height: 36
                        radius: 1
                        color: Kirigami.Theme.textColor
                        opacity: 0.4
                    }
                }

                // Main sections.
                Item {
                    SplitView.preferredWidth: 280
                    SplitView.minimumWidth: 200
                    SplitView.fillHeight: true

                    MouseArea {
                        anchors.fill: parent
                        onPressed: editorPage.isRightPanelFocused = false
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.mediumSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            Button {
                                visible: editorPage.editorNavIndices.length > 0
                                text: "Back"
                                icon.name: "go-previous"
                                focusPolicy: Qt.NoFocus
                                onClicked: {
                                    var next = editorPage.editorNavIndices.slice()
                                    next.pop()
                                    editorPage.editorNavIndices = next
                                }
                            }
                            Label {
                                text: editorPage.editorNavIndices.length === 0
                                      ? "Main Sections"
                                      : "Current: " + editorPage.activeTitle
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }
                            Button {
                                visible: editorPage.editorNavIndices.length === 0
                                text: "Add Section"
                                icon.name: "list-add"
                                focusPolicy: Qt.NoFocus
                                onClicked: {
                                    editorPage.focusNewSection = true
                                    var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                                    list.push({ "title": "New Section", "icon": "folder", "items": [] })
                                    root.masterEditableConfig = list
                                    root.selectedEditorSectionIndex = list.length - 1
                                }
                            }
                        }

                        ListView {
                            id: leftListView
                            visible: editorPage.editorNavIndices.length === 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Kirigami.Units.smallSpacing
                            model: root.masterEditableConfig

                            delegate: Kirigami.AbstractCard {
                                width: leftListView.width
                                highlighted: root.selectedEditorSectionIndex === index
                                onClicked: {
                                    root.selectedEditorSectionIndex = index
                                    editorPage.isRightPanelFocused = false
                                }

                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Layout.margins: Kirigami.Units.smallSpacing

                                    Kirigami.Icon {
                                        source: modelData.icon || "folder"
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                    }

                                    TextField {
                                        id: sectionTitleField
                                        text: modelData.title || ""
                                        Layout.fillWidth: true
                                        Component.onCompleted: {
                                            if (editorPage.focusNewSection && index === root.masterEditableConfig.length - 1) {
                                                editorPage.focusNewSection = false
                                                focusTimer.field = sectionTitleField
                                                focusTimer.restart()
                                            }
                                        }
                                        onActiveFocusChanged: {
                                            if (activeFocus) {
                                                root.selectedEditorSectionIndex = index
                                                editorPage.isRightPanelFocused = false
                                            }
                                        }
                                        onEditingFinished: {
                                            if (text !== (modelData.title || "")) {
                                                if (root.masterEditableConfig[index]) {
                                                    root.masterEditableConfig[index].title = text
                                                }
                                            }
                                        }
                                        Keys.onPressed: function(event) {
                                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                event.accepted = true
                                                focus = false
                                            } else if (event.key === Qt.Key_Tab) {
                                                event.accepted = true
                                                nextItemInFocusChain().forceActiveFocus()
                                            }
                                        }
                                    }

                                    Button {
                                        icon.name: "go-up"
                                        enabled: index > 0
                                        focusPolicy: Qt.NoFocus
                                        onClicked: {
                                            var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                                            var temp = list[index]
                                            list[index] = list[index - 1]
                                            list[index - 1] = temp
                                            root.masterEditableConfig = list
                                            if (root.selectedEditorSectionIndex === index) {
                                                root.selectedEditorSectionIndex = index - 1
                                            } else if (root.selectedEditorSectionIndex === index - 1) {
                                                root.selectedEditorSectionIndex = index
                                            }
                                        }
                                    }

                                    Button {
                                        icon.name: "go-down"
                                        enabled: index < root.masterEditableConfig.length - 1
                                        focusPolicy: Qt.NoFocus
                                        onClicked: {
                                            var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                                            var temp = list[index]
                                            list[index] = list[index + 1]
                                            list[index + 1] = temp
                                            root.masterEditableConfig = list
                                            if (root.selectedEditorSectionIndex === index) {
                                                root.selectedEditorSectionIndex = index + 1
                                            } else if (root.selectedEditorSectionIndex === index + 1) {
                                                root.selectedEditorSectionIndex = index
                                            }
                                        }
                                    }

                                    Button {
                                        icon.name: "edit-delete"
                                        focusPolicy: Qt.NoFocus
                                        onClicked: {
                                            var list = JSON.parse(JSON.stringify(root.masterEditableConfig))
                                            list.splice(index, 1)
                                            root.masterEditableConfig = list
                                            if (root.selectedEditorSectionIndex >= list.length) {
                                                root.selectedEditorSectionIndex = Math.max(0, list.length - 1)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            visible: editorPage.editorNavIndices.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.largeSpacing * 2
                                spacing: Kirigami.Units.mediumSpacing

                                Kirigami.Icon {
                                    source: "folder-open"
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 48
                                    Layout.alignment: Qt.AlignHCenter
                                    opacity: 0.5
                                }
                                Label {
                                    text: "Editing submenu contents.\nUse 'Back' to return to the parent level."
                                    horizontalAlignment: Text.AlignHCenter
                                    opacity: 0.6
                                    wrapMode: Label.WordWrap
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                // Items and submenus.
                Item {
                    SplitView.fillWidth: true
                    SplitView.minimumWidth: 380
                    SplitView.fillHeight: true

                    MouseArea {
                        anchors.fill: parent
                        onPressed: editorPage.isRightPanelFocused = true
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.mediumSpacing
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: {
                                    if (!editorPage.activeNode) return "No Section Selected"
                                    return editorPage.editorNavIndices.length === 0
                                           ? "Items in: " + editorPage.activeTitle
                                           : "Items in Submenu: " + editorPage.activeTitle
                                }
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                            }

                            Button {
                                text: "Add Submenu"
                                icon.name: "folder-new"
                                enabled: editorPage.activeNode !== null
                                focusPolicy: Qt.NoFocus
                                onClicked: {
                                    editorPage.focusNewItem = true
                                    editorPage.mutateCurrentItems(function(items) {
                                        items.push({
                                            "name": "New Submenu",
                                            "icon": "folder",
                                            "type": "submenu",
                                            "items": []
                                        })
                                    })
                                    editorPage.selectedItemIndex = editorPage.activeNode.items.length - 1
                                    editorPage.isRightPanelFocused = true
                                }
                            }

                            Button {
                                text: "Add Item"
                                icon.name: "list-add"
                                enabled: editorPage.activeNode !== null
                                focusPolicy: Qt.NoFocus
                                onClicked: {
                                    editorPage.focusNewItem = true
                                    editorPage.mutateCurrentItems(function(items) {
                                        items.push({
                                            "name": "New Command",
                                            "description": "Description",
                                            "icon": "application-x-executable",
                                            "type": "action",
                                            "command": "echo hello",
                                            "arguments": "",
                                            "notify": false,
                                            "prompt_arguments": false,
                                            "detached": false,
                                            "show_output": false,
                                            "shortcut": 0
                                        })
                                    })
                                    editorPage.selectedItemIndex = editorPage.activeNode.items.length - 1
                                    editorPage.isRightPanelFocused = true
                                }
                            }
                        }

                        ListView {
                            id: itemsListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Kirigami.Units.smallSpacing
                            model: editorPage.activeNode ? (editorPage.activeNode.items || []) : []

                            delegate: Kirigami.AbstractCard {
                                width: itemsListView.width
                                onClicked: {
                                    editorPage.selectedItemIndex = index
                                    editorPage.isRightPanelFocused = true
                                }

                                contentItem: ColumnLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Layout.margins: Kirigami.Units.smallSpacing

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        TextField {
                                            id: itemNameField
                                            text: modelData.name || ""
                                            placeholderText: "Label"
                                            Layout.fillWidth: true
                                            Layout.horizontalStretchFactor: 2
                                            Component.onCompleted: {
                                                if (editorPage.focusNewItem && editorPage.activeNode && index === editorPage.activeNode.items.length - 1) {
                                                    editorPage.focusNewItem = false
                                                    focusTimer.field = itemNameField
                                                    focusTimer.restart()
                                                }
                                            }
                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    editorPage.selectedItemIndex = index
                                                    editorPage.isRightPanelFocused = true
                                                }
                                            }
                                            onEditingFinished: {
                                                if (text !== (modelData.name || "")) {
                                                    if (editorPage.activeNode && editorPage.activeNode.items && editorPage.activeNode.items[index]) {
                                                        editorPage.activeNode.items[index].name = text
                                                    }
                                                }
                                            }
                                            Keys.onPressed: function(event) {
                                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                                    event.accepted = true
                                                    if (modelData.type !== "submenu") {
                                                        itemCommandField.forceActiveFocus()
                                                        itemCommandField.selectAll()
                                                    } else {
                                                        if (editorPage.activeNode && editorPage.activeNode.items && index < editorPage.activeNode.items.length - 1) {
                                                            editorPage.selectedItemIndex = index + 1
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        TextField {
                                            id: itemCommandField
                                            text: modelData.command || ""
                                            placeholderText: "Shell Command"
                                            Layout.fillWidth: true
                                            Layout.horizontalStretchFactor: 1
                                            visible: modelData.type !== "submenu"
                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    editorPage.selectedItemIndex = index
                                                    editorPage.isRightPanelFocused = true
                                                }
                                            }
                                            onEditingFinished: {
                                                if (text !== (modelData.command || "")) {
                                                    if (editorPage.activeNode && editorPage.activeNode.items && editorPage.activeNode.items[index]) {
                                                        editorPage.activeNode.items[index].command = text
                                                    }
                                                }
                                            }
                                            Keys.onPressed: function(event) {
                                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                                    event.accepted = true
                                                    itemArgsField.forceActiveFocus()
                                                    itemArgsField.selectAll()
                                                }
                                            }
                                        }

                                        TextField {
                                            id: itemArgsField
                                            text: modelData.arguments || ""
                                            placeholderText: "Default Arguments"
                                            Layout.fillWidth: true
                                            Layout.horizontalStretchFactor: 2
                                            visible: modelData.type !== "submenu"
                                            onActiveFocusChanged: {
                                                if (activeFocus) {
                                                    editorPage.selectedItemIndex = index
                                                    editorPage.isRightPanelFocused = true
                                                }
                                            }
                                            onEditingFinished: {
                                                if (text !== (modelData.arguments || "")) {
                                                    if (editorPage.activeNode && editorPage.activeNode.items && editorPage.activeNode.items[index]) {
                                                        editorPage.activeNode.items[index].arguments = text
                                                    }
                                                }
                                            }
                                            Keys.onPressed: function(event) {
                                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
                                                    event.accepted = true
                                                    if (editorPage.activeNode && editorPage.activeNode.items && index < editorPage.activeNode.items.length - 1) {
                                                        editorPage.selectedItemIndex = index + 1
                                                    }
                                                }
                                            }
                                        }

                                        Button {
                                            visible: modelData.type === "submenu"
                                            text: "Enter"
                                            icon.name: "go-next"
                                            focusPolicy: Qt.NoFocus
                                            onClicked: {
                                                var next = editorPage.editorNavIndices.slice()
                                                next.push(index)
                                                editorPage.editorNavIndices = next
                                                editorPage.selectedItemIndex = 0
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        Switch {
                                            text: "Notify"
                                            objectName: "notifySwitch"
                                            visible: modelData.type !== "submenu"
                                            focusPolicy: Qt.NoFocus
                                            checked: !Boolean(modelData.detached) && (modelData.notify === undefined ? true : Boolean(modelData.notify))
                                            onClicked: {
                                                var value = checked
                                                editorPage.mutateCurrentItems(function(items) {
                                                    items[index].notify = value
                                                    if (value) items[index].detached = false
                                                })
                                            }
                                        }

                                        Switch {
                                            text: "Ask Args"
                                            visible: modelData.type !== "submenu"
                                            focusPolicy: Qt.NoFocus
                                            checked: modelData.prompt_arguments !== undefined ? Boolean(modelData.prompt_arguments) : false
                                            onToggled: {
                                                if (editorPage.activeNode && editorPage.activeNode.items && editorPage.activeNode.items[index]) {
                                                    editorPage.activeNode.items[index].prompt_arguments = checked
                                                }
                                            }
                                        }

                                        Switch {
                                            text: "Show Output"
                                            visible: modelData.type !== "submenu"
                                            focusPolicy: Qt.NoFocus
                                            checked: modelData.show_output !== undefined ? Boolean(modelData.show_output) : false
                                            onToggled: {
                                                if (editorPage.activeNode && editorPage.activeNode.items && editorPage.activeNode.items[index]) {
                                                    editorPage.activeNode.items[index].show_output = checked
                                                }
                                            }
                                        }

                                        Switch {
                                            text: "Run Detached"
                                            objectName: "detachedSwitch"
                                            visible: modelData.type !== "submenu"
                                            focusPolicy: Qt.NoFocus
                                            checked: modelData.detached !== undefined ? Boolean(modelData.detached) : false
                                            onClicked: {
                                                var value = checked
                                                editorPage.mutateCurrentItems(function(items) {
                                                    items[index].detached = value
                                                    if (value) items[index].notify = false
                                                })
                                            }
                                        }

                                        ComboBox {
                                            visible: modelData.type !== "submenu"
                                            focusPolicy: Qt.NoFocus
                                            model: ["No shortcut", "Shortcut 1", "Shortcut 2", "Shortcut 3", "Shortcut 4", "Shortcut 5", "Shortcut 6", "Shortcut 7", "Shortcut 8", "Shortcut 9"]
                                            currentIndex: modelData.shortcut !== undefined && modelData.shortcut >= 1 && modelData.shortcut <= 9 ? modelData.shortcut : 0
                                            Layout.preferredWidth: 130
                                            onActivated: {
                                                if (editorPage.activeNode && editorPage.activeNode.items && editorPage.activeNode.items[index]) {
                                                    editorPage.activeNode.items[index].shortcut = currentIndex
                                                }
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Button {
                                            icon.name: "go-up"
                                            enabled: index > 0
                                            focusPolicy: Qt.NoFocus
                                            onClicked: {
                                                editorPage.mutateCurrentItems(function(items) {
                                                    var temp = items[index]
                                                    items[index] = items[index - 1]
                                                    items[index - 1] = temp
                                                })
                                                editorPage.selectedItemIndex = index - 1
                                            }
                                        }

                                        Button {
                                            icon.name: "go-down"
                                            enabled: editorPage.activeNode && editorPage.activeNode.items && index < editorPage.activeNode.items.length - 1
                                            focusPolicy: Qt.NoFocus
                                            onClicked: {
                                                editorPage.mutateCurrentItems(function(items) {
                                                    var temp = items[index]
                                                    items[index] = items[index + 1]
                                                    items[index + 1] = temp
                                                })
                                                editorPage.selectedItemIndex = index + 1
                                            }
                                        }

                                        Button {
                                            icon.name: "edit-delete"
                                            focusPolicy: Qt.NoFocus
                                            onClicked: {
                                                editorPage.mutateCurrentItems(function(items) {
                                                    items.splice(index, 1)
                                                })
                                                editorPage.selectedItemIndex = Math.max(0, index - 1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 15
        property var field: null
        onTriggered: {
            if (field) {
                field.forceActiveFocus()
                field.selectAll()
            }
        }
    }

    Component {
        id: mainPageComponent
        Kirigami.ScrollablePage {
            id: subPage
            property string pageTitle: ""
            property var menuItems: []
            property bool isFavoritesView: false
            property bool isSubmenuLevel: false
            property var submenuNavStack: []
            title: pageTitle

            header: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.margins: Kirigami.Units.largeSpacing
                Kirigami.SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search..."
                    onTextChanged: {
                        if (text.length > 0) {
                            searchResultsView.model = backend.search_items(text)
                            searchResultsView.visible = true
                            normalContent.visible = false
                        } else {
                            searchResultsView.visible = false
                            normalContent.visible = true
                        }
                    }
                }
            }

            Kirigami.CardsListView {
                id: normalContent
                visible: true
                model: {
                    var items = []
                    if (subPage.isFavoritesView) {
                        var uniqueFavs = []
                        var seen = {}
                        for (var i = 0; i < backend.favorites.length; i++) {
                            var fav = backend.favorites[i]
                            var key = (fav.name || "") + "|||" + fav.command + "|||" + (fav.arguments || "")
                            if (!seen[key]) {
                                seen[key] = true
                                uniqueFavs.push(fav)
                            }
                        }
                        items = uniqueFavs
                    } else {
                        items = subPage.menuItems
                    }

                    if (subPage.isSubmenuLevel) {
                        var backItem = {
                            "name": "Go Back",
                            "type": "back_virtual",
                            "icon": "go-previous"
                        }
                        return [backItem].concat(items)
                    }
                    return items
                }

                delegate: Kirigami.AbstractCard {
                    showClickFeedback: true
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon {
                            source: modelData.type === "back_virtual" ? "go-previous" : (modelData.icon || (modelData.type === "submenu" ? "folder" : "application-x-executable"))
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Label { text: modelData.type === "back_virtual" ? ".." : modelData.name; font.bold: true; Layout.fillWidth: true }
                            Label {
                                visible: modelData.type !== "back_virtual" && (modelData.type === "submenu" || backend.showCommand)
                                text: modelData.type === "submenu"
                                      ? "Submenu"
                                      : (modelData.arguments ? modelData.command + " " + modelData.arguments : modelData.command)
                                opacity: 0.7
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Button {
                            text: modelData.type === "back_virtual" ? "Back" : (modelData.type === "submenu" ? "Open" : "Run")
                            icon.name: modelData.type === "back_virtual" ? "go-previous" : (modelData.type === "submenu" ? "go-next" : "system-run")
                            focusPolicy: Qt.NoFocus
                            onClicked: handleItemActivation()
                        }
                        Button {
                            objectName: "removeRecentButton"
                            visible: subPage.isFavoritesView && modelData.type !== "back_virtual"
                            icon.name: "edit-delete"
                            Accessible.name: "Remove from Recent"
                            ToolTip.visible: hovered
                            ToolTip.text: "Remove from Recent"
                            onClicked: backend.remove_recent(
                                modelData.name || "", modelData.command || "", modelData.arguments || ""
                            )
                        }
                    }
                    onClicked: handleItemActivation()

                    function handleItemActivation() {
                        if (modelData.type === "back_virtual") {
                            var stack = subPage.submenuNavStack.slice()
                            var previousLevel = stack.pop()
                            if (previousLevel) {
                                root.navigateToPage(mainPageComponent, {
                                    pageTitle: previousLevel.pageTitle,
                                    menuItems: previousLevel.menuItems,
                                    isFavoritesView: false,
                                    isSubmenuLevel: stack.length > 0,
                                    submenuNavStack: stack
                                })
                            }
                        } else if (modelData.type === "submenu") {
                            var nextStack = subPage.submenuNavStack.slice()
                            nextStack.push({
                                pageTitle: subPage.pageTitle,
                                menuItems: subPage.menuItems
                            })
                            root.navigateToPage(mainPageComponent, {
                                pageTitle: modelData.name,
                                menuItems: modelData.items || [],
                                isFavoritesView: false,
                                isSubmenuLevel: true,
                                submenuNavStack: nextStack
                            })
                        } else {
                            root.executeActionItem(modelData)
                        }
                    }
                }
            }

            Kirigami.CardsListView {
                id: searchResultsView
                visible: false
                model: []
                delegate: Kirigami.AbstractCard {
                    showClickFeedback: true
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        Kirigami.Icon { source: modelData.icon || "application-x-executable"; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.bold: true }
                            Label { text: "Path: " + (modelData.breadcrumb || ""); opacity: 0.6 }
                            Label {
                                visible: backend.showCommand
                                text: modelData.arguments ? modelData.command + " " + modelData.arguments : (modelData.command || "")
                                opacity: 0.5
                                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        Button {
                            text: "Run"
                            icon.name: "system-run"
                            focusPolicy: Qt.NoFocus
                            onClicked: root.executeActionItem(modelData)
                        }
                    }
                    onClicked: root.executeActionItem(modelData)
                }
            }
        }
    }
}
