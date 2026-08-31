import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../singletons"

Item {
    id: autostartTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property var defaultAutostartSettings: ({
        "enabled": true,
        "entries": []
    })

    property var autostartSettings: defaultAutostartSettings
    property bool masterEnabled: true
    property var entriesList: []

    function syncSettings() {
        let s = (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings["autostart"])
            ? Config.rawSettings["autostart"]
            : ((typeof Config !== "undefined" && typeof Config.getSetting === "function")
                ? Config.getSetting("autostart", autostartTabRoot.defaultAutostartSettings)
                : autostartTabRoot.defaultAutostartSettings);
        if (!s) s = autostartTabRoot.defaultAutostartSettings;

        let newEntries = Array.isArray(s.entries) ? s.entries : [];
        if (autostartTabRoot.entriesList.length > 0 && JSON.stringify(autostartTabRoot.autostartSettings) === JSON.stringify(s) && autostartTabRoot.entriesList.length === newEntries.length) {
            return;
        }

        autostartTabRoot.autostartSettings = s;
        autostartTabRoot.masterEnabled = (s && s.enabled !== undefined) ? s.enabled : true;
        autostartTabRoot.entriesList = newEntries;
    }

    property int activePickerIndex: -1
    property var collapsedEntriesMap: ({})

    function toggleCollapsed(entryId) {
        if (!entryId) return;
        let map = Object.assign({}, autostartTabRoot.collapsedEntriesMap);
        map[entryId] = !map[entryId];
        autostartTabRoot.collapsedEntriesMap = map;
        if (typeof Sounds !== "undefined") {
            Sounds.playSfx("reusables/button/click.wav");
        }
    }

    Timer {
        id: debounceTimer
        interval: 350
        repeat: false
        onTriggered: {
            Config.setSetting("autostart", autostartTabRoot.autostartSettings);
        }
    }

    function updateEntrySilent(index, key, val) {
        if (!Array.isArray(entriesList) || index < 0 || index >= entriesList.length) return;
        entriesList[index][key] = val;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": entriesList
        };
        autostartTabRoot.autostartSettings = current;
        debounceTimer.restart();
    }

    function flushEntry(index, key, val) {
        if (!Array.isArray(entriesList) || index < 0 || index >= entriesList.length) return;
        entriesList[index][key] = val;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": entriesList
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function toggleMasterEnabled(val) {
        autostartTabRoot.masterEnabled = val;
        let current = {
            "enabled": val,
            "entries": entriesList
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function addEntry() {
        let list = Array.isArray(entriesList) ? entriesList.slice() : [];
        let newEntry = {
            "id": "auto_" + Date.now().toString(36) + Math.random().toString(36).substr(2, 4),
            "name": "",
            "exec": "",
            "enabled": true,
            "delay": 0,
            "count": 1,
            "repeatDelay": 0,
            "workspace": 0,
            "silent": false,
            "condition": "always",
            "restartOnCrash": false
        };
        list.push(newEntry);
        autostartTabRoot.entriesList = list;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": list
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function deleteEntry(index) {
        let list = Array.isArray(entriesList) ? entriesList.slice() : [];
        if (index < 0 || index >= list.length) return;
        list.splice(index, 1);
        autostartTabRoot.entriesList = list;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": list
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function testRunEntry(execCmd, delay, count, repeatDelay, workspace, silent) {
        if (!execCmd || execCmd.trim() === "") return;
        let d = (delay !== undefined && delay !== null) ? Math.max(0, parseInt(delay)) : 0;
        let c = (count !== undefined && count !== null) ? Math.max(1, parseInt(count)) : 1;
        let r = (repeatDelay !== undefined && repeatDelay !== null) ? Math.max(0, parseInt(repeatDelay)) : 0;
        let ws = (workspace !== undefined && workspace !== null && parseInt(workspace) > 0) ? parseInt(workspace) : 0;
        let isSilent = (silent === true);

        let finalExec = execCmd;
        if (ws > 0 || isSilent) {
            let rules = "[";
            if (ws > 0) rules += "workspace " + ws + " ";
            if (isSilent) rules += "silent ";
            rules = rules.trim() + "]";
            finalExec = "hyprctl dispatch 'hl.dsp.exec_cmd(\\\"" + rules + " " + execCmd + "\\\")' 2>/dev/null || hyprctl dispatch exec \\\"" + rules + " " + execCmd + "\\\"";
        }

        let script = "";
        if (d > 0) {
            script += "sleep " + d + " && ";
        }
        if (c > 1) {
            script += "for ((i=0; i<" + c + "; i++)); do if (( i > 0 && " + r + " > 0 )); then sleep " + r + "; fi; (" + finalExec + ") & done";
        } else {
            script += "(" + finalExec + ") &";
        }

        Quickshell.execDetached(["bash", "-c", script]);
        if (typeof Sounds !== "undefined") {
            Sounds.playSfx("reusables/button/click.wav");
        }
    }

    function resolveAppIcon(execStr, nameStr) {
        let clean = (execStr || "").trim().split(" ")[0];
        let name = (nameStr || "").trim();
        if (!clean && !name) {
            return { isIcon: false, icon: "", fontIcon: "󰑮", isScript: false };
        }
        let base = clean.split("/").pop();
        let baseLower = base.toLowerCase();

        if (baseLower.endsWith(".sh") || baseLower.endsWith(".bash") || baseLower.endsWith(".zsh") || baseLower.endsWith(".py")) {
            return { isIcon: false, icon: "", fontIcon: "󰆍", isScript: true };
        }

        let iconName = "";
        try {
            if (typeof DesktopEntries !== "undefined" && typeof DesktopEntries.heuristicLookup === "function") {
                let entry = DesktopEntries.heuristicLookup(clean) || (name ? DesktopEntries.heuristicLookup(name) : null);
                if (entry && entry.icon) {
                    iconName = entry.icon;
                }
            }
        } catch(e) {}

        return { isIcon: iconName !== "", icon: iconName, fontIcon: "󰑮", isScript: false };
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            autostartTabRoot.syncSettings();
        }
    }

    Component.onCompleted: {
        autostartTabRoot.syncSettings();
    }

    FilePicker {
        id: binaryPicker
        rootObj: autostartTabRoot.rootObj
        nameFilters: ["*"]
        titleText: I18n.t("guide.autostart.browse_file", "Select Executable")
        onFileSelected: function(filePath, fileName) {
            let idx = autostartTabRoot.activePickerIndex;
            if (idx >= 0 && idx < autostartTabRoot.entriesList.length) {
                let curItem = autostartTabRoot.entriesList[idx];
                curItem["exec"] = filePath;
                if (!curItem.name || curItem.name.trim() === "") {
                    curItem["name"] = fileName;
                }
                let current = {
                    "enabled": autostartTabRoot.masterEnabled,
                    "entries": autostartTabRoot.entriesList
                };
                autostartTabRoot.autostartSettings = current;
                Config.setSetting("autostart", current);
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(4)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentWidth: width
        contentHeight: settingsCol.implicitHeight + rootObj.s(20)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: rootObj.s(10)

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: masterRowLayout.implicitHeight + rootObj.s(24)
                color: "transparent"

                RowLayout {
                    id: masterRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: rootObj.s(16)

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)

                        Text {
                            text: I18n.t("guide.autostart.master_switch.title", "Enable Autostart")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            font.weight: Font.DemiBold
                            color: ThemeBackend.text
                        }

                        Text {
                            text: I18n.t("guide.autostart.master_switch.desc", "Globally execute the configured startup application list on login")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: autostartTabRoot.masterEnabled
                        accentColor: ThemeBackend.mauve
                        baseColor: ThemeBackend.surface1
                        handleColor: ThemeBackend.crust
                        handleOffColor: ThemeBackend.text
                        onToggled: function(val) {
                            autostartTabRoot.toggleMasterEnabled(val);
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.alpha(ThemeBackend.surface1, 0.4)
                Layout.topMargin: rootObj.s(4)
                Layout.bottomMargin: rootObj.s(4)
                visible: autostartTabRoot.masterEnabled
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(6)
                Layout.bottomMargin: rootObj.s(2)
                visible: autostartTabRoot.masterEnabled

                ColumnLayout {
                    spacing: rootObj.s(2)

                    Text {
                        text: I18n.t("guide.autostart.title", "Startup Applications")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                    }

                    Text {
                        text: I18n.t("guide.autostart.desc", "Manage programs, binaries, and scripts launched automatically upon session start")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                    }
                }

                Item { Layout.fillWidth: true }

                ClickButton {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    implicitHeight: rootObj.s(34)
                    horizontalPadding: rootObj.s(14)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: I18n.t("guide.autostart.add_button", "Add Application")
                    buttonIcon: "󰐕"
                    iconFontSize: rootObj.s(14)
                    textFontSize: rootObj.s(12)
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.crust
                    onClicked: {
                        autostartTabRoot.addEntry();
                    }
                }
            }

            Rectangle {
                visible: autostartTabRoot.masterEnabled && autostartTabRoot.entriesList.length === 0
                Layout.fillWidth: true
                implicitHeight: rootObj.s(180)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.3)
                border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: rootObj.s(8)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󱁐"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(36)
                        color: Qt.alpha(ThemeBackend.subtext0, 0.5)
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: I18n.t("guide.autostart.empty_title", "No autostart applications")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.DemiBold
                        color: ThemeBackend.text
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: I18n.t("guide.autostart.empty_desc", "Click 'Add Application' to specify commands, binaries, delays, and repetition counts.")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: rootObj.s(10)
                visible: autostartTabRoot.masterEnabled

                Repeater {
                    id: entriesRepeater
                    model: autostartTabRoot.entriesList

                    delegate: Rectangle {
                        id: entryCard
                        required property var modelData
                        required property int index

                        property string entryId: modelData.id || ("auto_entry_" + index)
                        property string entryName: modelData.name || ""
                        property string entryExec: modelData.exec || ""
                        property bool entryEnabled: modelData.enabled !== undefined ? modelData.enabled : true
                        property int entryDelay: modelData.delay || 0
                        property int entryCount: modelData.count || 1
                        property int entryRepeatDelay: modelData.repeatDelay || modelData.repeat_delay || modelData.interval || 0
                        property int entryWorkspace: modelData.workspace || 0
                        property bool entrySilent: modelData.silent || false
                        property string entryCondition: modelData.condition || "always"
                        property bool entryRestart: modelData.restartOnCrash || false

                        property bool isExpanded: autostartTabRoot.collapsedEntriesMap[entryId] === true
                        property bool isTestRunning: false

                        Timer {
                            id: testFeedbackTimer
                            interval: 1200
                            repeat: false
                            onTriggered: entryCard.isTestRunning = false
                        }

                        Layout.fillWidth: true
                        implicitHeight: cardInnerLayout.implicitHeight + rootObj.s(20)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface0, 0.4)

                        Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                        ColumnLayout {
                            id: cardInnerLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: rootObj.s(10)
                            spacing: rootObj.s(8)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: rootObj.s(10)

                                Item {
                                    Layout.preferredWidth: rootObj.s(34)
                                    Layout.preferredHeight: rootObj.s(34)
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: rootObj.s(6)
                                        color: Qt.alpha(ThemeBackend.surface1, 0.6)

                                        property var iconInfo: (autostartTabRoot.resolveAppIcon(entryCard.entryExec, entryCard.entryName)) || ({ isIcon: false, icon: "", fontIcon: "󰑮", isScript: false })

                                        Image {
                                            anchors.fill: parent
                                            anchors.margins: rootObj.s(5)
                                            source: (parent.iconInfo && parent.iconInfo.isIcon) ? (parent.iconInfo.icon.startsWith("/") ? ("file://" + parent.iconInfo.icon) : ("image://icon/" + parent.iconInfo.icon)) : ""
                                            visible: parent.iconInfo && parent.iconInfo.isIcon && status === Image.Ready
                                            fillMode: Image.PreserveAspectFit
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !parent.iconInfo || !parent.iconInfo.isIcon
                                            text: (parent.iconInfo && parent.iconInfo.fontIcon) ? parent.iconInfo.fontIcon : "󰑮"
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(16)
                                            color: (parent.iconInfo && parent.iconInfo.isScript) ? ThemeBackend.yellow : ThemeBackend.mauve
                                        }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: rootObj.s(34)

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: rootObj.s(2)

                                        Text {
                                            text: entryCard.entryName.trim() !== "" ? entryCard.entryName : (entryCard.entryExec.trim() !== "" ? entryCard.entryExec : ("#" + (index + 1) + " Application"))
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(13)
                                            font.weight: Font.DemiBold
                                            color: entryCard.entryEnabled ? ThemeBackend.text : ThemeBackend.subtext0
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: !entryCard.isExpanded
                                                ? ((entryCard.entryExec.trim() !== "" ? entryCard.entryExec : "No command")
                                                   + (entryCard.entryWorkspace > 0 ? (" • WS " + entryCard.entryWorkspace) : "")
                                                   + (entryCard.entrySilent ? " • Silent" : "")
                                                   + (entryCard.entryDelay > 0 ? (" • " + entryCard.entryDelay + "s") : "")
                                                   + (entryCard.entryCount > 1 ? (" • " + entryCard.entryCount + "x" + (entryCard.entryRepeatDelay > 0 ? (" (" + entryCard.entryRepeatDelay + "s)") : "")) : ""))
                                                : (entryCard.entryExec.trim() !== "" ? entryCard.entryExec : "")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(10)
                                            color: ThemeBackend.subtext0
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                            visible: text !== ""
                                        }
                                    }
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: rootObj.s(28)
                                    implicitHeight: rootObj.s(28)
                                    cornerRadius: rootObj.s(8)
                                    buttonIcon: entryCard.isTestRunning ? "󱎫" : "󰐊"
                                    iconFontSize: rootObj.s(13)
                                    iconOffsetX: entryCard.isTestRunning ? 0 : 1
                                    accentColor: entryCard.isTestRunning ? Qt.alpha(ThemeBackend.yellow, 0.2) : ThemeBackend.surface0
                                    textColor: entryCard.isTestRunning ? ThemeBackend.yellow : (entryCard.entryExec.trim() !== "" ? ThemeBackend.green : ThemeBackend.subtext0)
                                    onClicked: {
                                        if (entryCard.entryExec.trim() !== "") {
                                            entryCard.isTestRunning = true;
                                            testFeedbackTimer.restart();
                                            autostartTabRoot.testRunEntry(entryCard.entryExec, entryCard.entryDelay, entryCard.entryCount, entryCard.entryRepeatDelay, entryCard.entryWorkspace, entryCard.entrySilent);
                                        }
                                    }
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: rootObj.s(28)
                                    implicitHeight: rootObj.s(28)
                                    cornerRadius: rootObj.s(8)
                                    buttonIcon: "󰉋"
                                    iconFontSize: rootObj.s(13)
                                    accentColor: ThemeBackend.surface0
                                    textColor: ThemeBackend.mauve
                                    onClicked: {
                                        autostartTabRoot.activePickerIndex = index;
                                        binaryPicker.open();
                                    }
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: rootObj.s(28)
                                    implicitHeight: rootObj.s(28)
                                    cornerRadius: rootObj.s(8)
                                    iconOffsetX: -1
                                    buttonIcon: "󰒓"
                                    iconFontSize: rootObj.s(14)
                                    accentColor: entryCard.isExpanded ? Qt.alpha(ThemeBackend.mauve, 0.25) : ThemeBackend.surface0
                                    textColor: entryCard.isExpanded ? ThemeBackend.mauve : (isHoveredOrHighlighted ? ThemeBackend.text : ThemeBackend.overlay2)
                                    onClicked: {
                                        autostartTabRoot.toggleCollapsed(entryCard.entryId);
                                    }
                                }

                                Toggle {
                                    Layout.alignment: Qt.AlignVCenter
                                    checked: entryCard.entryEnabled
                                    accentColor: ThemeBackend.mauve
                                    baseColor: ThemeBackend.surface1
                                    handleColor: ThemeBackend.crust
                                    handleOffColor: ThemeBackend.text
                                    onToggled: function(val) {
                                        entryCard.entryEnabled = val;
                                        autostartTabRoot.flushEntry(index, "enabled", val);
                                    }
                                }

                                IconButton {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: rootObj.s(28)
                                    implicitHeight: rootObj.s(28)
                                    cornerRadius: rootObj.s(8)
                                    buttonIcon: "󰅖"
                                    iconFontSize: rootObj.s(13)
                                    accentColor: Qt.alpha(ThemeBackend.red, 0.15)
                                    textColor: ThemeBackend.red
                                    onClicked: {
                                        autostartTabRoot.deleteEntry(index);
                                    }
                                }
                            }

                            Item {
                                id: expandableWrapper
                                Layout.fillWidth: true
                                clip: true
                                visible: opacity > 0
                                opacity: entryCard.isExpanded ? 1.0 : 0.0
                                implicitHeight: entryCard.isExpanded ? expandableCol.implicitHeight : 0

                                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                ColumnLayout {
                                    id: expandableCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: rootObj.s(12)

                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                        Layout.topMargin: rootObj.s(2)
                                        Layout.bottomMargin: rootObj.s(2)
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(10)

                                        ColumnLayout {
                                            Layout.preferredWidth: rootObj.s(180)
                                            spacing: rootObj.s(4)

                                            Text {
                                                text: I18n.t("guide.autostart.name_label", "Name")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(11)
                                                color: ThemeBackend.subtext0
                                            }

                                            Input {
                                                id: cardNameInput
                                                Layout.fillWidth: true
                                                implicitHeight: rootObj.s(32)
                                                text: entryCard.entryName
                                                placeholderText: I18n.t("guide.autostart.name_placeholder", "e.g. Discord, Script")
                                                fontPixelSize: rootObj.s(11)
                                                baseColor: ThemeBackend.surface0
                                                accentColor: ThemeBackend.mauve
                                                textColor: ThemeBackend.text
                                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                                cornerRadius: rootObj.s(6)
                                                onTextEdited: function(newText) {
                                                    entryCard.entryName = newText;
                                                    autostartTabRoot.updateEntrySilent(index, "name", newText);
                                                }
                                                onAccepted: function(t) {
                                                    let val = (typeof t === "string") ? t : text;
                                                    entryCard.entryName = val;
                                                    autostartTabRoot.flushEntry(index, "name", val);
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: rootObj.s(4)

                                            Text {
                                                text: I18n.t("guide.autostart.exec_label", "Command / Executable")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(11)
                                                color: ThemeBackend.subtext0
                                            }

                                            Input {
                                                id: cardExecInput
                                                Layout.fillWidth: true
                                                implicitHeight: rootObj.s(32)
                                                text: entryCard.entryExec
                                                placeholderText: I18n.t("guide.autostart.exec_placeholder", "Binary path or command + flags")
                                                fontPixelSize: rootObj.s(11)
                                                baseColor: ThemeBackend.surface0
                                                accentColor: ThemeBackend.mauve
                                                textColor: ThemeBackend.text
                                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                                cornerRadius: rootObj.s(6)
                                                onTextEdited: function(newText) {
                                                    entryCard.entryExec = newText;
                                                    autostartTabRoot.updateEntrySilent(index, "exec", newText);
                                                }
                                                onAccepted: function(t) {
                                                    let val = (typeof t === "string") ? t : text;
                                                    entryCard.entryExec = val;
                                                    autostartTabRoot.flushEntry(index, "exec", val);
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(10)

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: rootObj.s(4)

                                            Text {
                                                text: I18n.t("guide.autostart.delay_label", "Startup Delay")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(11)
                                                color: ThemeBackend.subtext0
                                            }

                                            NumberSelector {
                                                Layout.fillWidth: true
                                                implicitHeight: rootObj.s(32)
                                                from: 0
                                                to: 3600
                                                stepSize: 1
                                                decimals: 0
                                                suffix: "s"
                                                value: entryCard.entryDelay
                                                baseColor: ThemeBackend.surface0
                                                accentColor: ThemeBackend.mauve
                                                buttonColor: ThemeBackend.surface1
                                                buttonTextColor: ThemeBackend.text
                                                textColor: ThemeBackend.text
                                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                                cornerRadius: rootObj.s(6)
                                                fontFamily: ThemeBackend.fontFamily
                                                fontPixelSize: rootObj.s(11)
                                                onTriggered: {
                                                    let rounded = Math.max(0, Math.round(value));
                                                    if (entryCard.entryDelay !== rounded) {
                                                        entryCard.entryDelay = rounded;
                                                        autostartTabRoot.flushEntry(index, "delay", rounded);
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: rootObj.s(4)

                                            Text {
                                                text: I18n.t("guide.autostart.count_label", "Launch Count")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(11)
                                                color: ThemeBackend.subtext0
                                            }

                                            NumberSelector {
                                                Layout.fillWidth: true
                                                implicitHeight: rootObj.s(32)
                                                from: 1
                                                to: 50
                                                stepSize: 1
                                                decimals: 0
                                                value: entryCard.entryCount
                                                baseColor: ThemeBackend.surface0
                                                accentColor: ThemeBackend.mauve
                                                buttonColor: ThemeBackend.surface1
                                                buttonTextColor: ThemeBackend.text
                                                textColor: ThemeBackend.text
                                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                                cornerRadius: rootObj.s(6)
                                                fontFamily: ThemeBackend.fontFamily
                                                fontPixelSize: rootObj.s(11)
                                                onTriggered: {
                                                    let rounded = Math.max(1, Math.round(value));
                                                    if (entryCard.entryCount !== rounded) {
                                                        entryCard.entryCount = rounded;
                                                        autostartTabRoot.flushEntry(index, "count", rounded);
                                                    }
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: rootObj.s(4)

                                            Text {
                                                text: I18n.t("guide.autostart.workspace_label", "Workspace")
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: rootObj.s(11)
                                                color: ThemeBackend.subtext0
                                            }

                                            NumberSelector {
                                                Layout.fillWidth: true
                                                implicitHeight: rootObj.s(32)
                                                from: 0
                                                to: 10
                                                stepSize: 1
                                                decimals: 0
                                                prefix: "WS "
                                                specialZeroText: I18n.t("guide.autostart.workspace_default", "Default")
                                                value: entryCard.entryWorkspace
                                                baseColor: ThemeBackend.surface0
                                                accentColor: ThemeBackend.mauve
                                                buttonColor: ThemeBackend.surface1
                                                buttonTextColor: ThemeBackend.text
                                                textColor: ThemeBackend.text
                                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                                cornerRadius: rootObj.s(6)
                                                fontFamily: ThemeBackend.fontFamily
                                                fontPixelSize: rootObj.s(11)
                                                onTriggered: {
                                                    let rounded = Math.max(0, Math.round(value));
                                                    if (entryCard.entryWorkspace !== rounded) {
                                                        entryCard.entryWorkspace = rounded;
                                                        autostartTabRoot.flushEntry(index, "workspace", rounded);
                                                    }
                                                }
                                            }
                                        }

                                        Item {
                                            id: repeatDelayWrapper
                                            property bool shouldShow: entryCard.entryCount > 1
                                            clip: true
                                            visible: opacity > 0
                                            opacity: shouldShow ? 1.0 : 0.0
                                            Layout.fillWidth: shouldShow
                                            implicitWidth: shouldShow ? repeatDelayCol.implicitWidth : 0
                                            implicitHeight: repeatDelayCol.implicitHeight

                                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                                            Behavior on implicitWidth { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                            ColumnLayout {
                                                id: repeatDelayCol
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                spacing: rootObj.s(4)

                                                Text {
                                                    text: I18n.t("guide.autostart.repeat_delay_label", "Repeat Interval")
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(11)
                                                    color: ThemeBackend.subtext0
                                                }

                                                NumberSelector {
                                                    Layout.fillWidth: true
                                                    implicitHeight: rootObj.s(32)
                                                    from: 0
                                                    to: 3600
                                                    stepSize: 1
                                                    decimals: 0
                                                    suffix: "s"
                                                    value: entryCard.entryRepeatDelay
                                                    baseColor: ThemeBackend.surface0
                                                    accentColor: ThemeBackend.mauve
                                                    buttonColor: ThemeBackend.surface1
                                                    buttonTextColor: ThemeBackend.text
                                                    textColor: ThemeBackend.text
                                                    borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                                    cornerRadius: rootObj.s(6)
                                                    fontFamily: ThemeBackend.fontFamily
                                                    fontPixelSize: rootObj.s(11)
                                                    onTriggered: {
                                                        let rounded = Math.max(0, Math.round(value));
                                                        if (entryCard.entryRepeatDelay !== rounded) {
                                                            entryCard.entryRepeatDelay = rounded;
                                                            autostartTabRoot.flushEntry(index, "repeatDelay", rounded);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(10)

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: rootObj.s(46)
                                            radius: rootObj.s(6)
                                            color: Qt.alpha(ThemeBackend.surface0, 0.4)
                                            border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: rootObj.s(10)
                                                anchors.rightMargin: rootObj.s(10)
                                                spacing: rootObj.s(8)

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0

                                                    Text {
                                                        text: I18n.t("guide.autostart.silent_label", "Silent Launch")
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: rootObj.s(11)
                                                        font.weight: Font.DemiBold
                                                        color: ThemeBackend.text
                                                    }

                                                    Text {
                                                        text: I18n.t("guide.autostart.silent_desc", "Do not steal focus")
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: rootObj.s(9)
                                                        color: ThemeBackend.subtext0
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                Toggle {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    checked: entryCard.entrySilent
                                                    accentColor: ThemeBackend.mauve
                                                    baseColor: ThemeBackend.surface1
                                                    handleColor: ThemeBackend.crust
                                                    handleOffColor: ThemeBackend.text
                                                    onToggled: function(val) {
                                                        entryCard.entrySilent = val;
                                                        autostartTabRoot.flushEntry(index, "silent", val);
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: rootObj.s(46)
                                            radius: rootObj.s(6)
                                            color: Qt.alpha(ThemeBackend.surface0, 0.4)
                                            border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: rootObj.s(10)
                                                anchors.rightMargin: rootObj.s(10)
                                                spacing: rootObj.s(8)

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0

                                                    Text {
                                                        text: I18n.t("guide.autostart.restart_crash_label", "Keep-Alive")
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: rootObj.s(11)
                                                        font.weight: Font.DemiBold
                                                        color: ThemeBackend.text
                                                    }

                                                    Text {
                                                        text: I18n.t("guide.autostart.restart_crash_desc", "Restart if crashes")
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: rootObj.s(9)
                                                        color: ThemeBackend.subtext0
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                Toggle {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    checked: entryCard.entryRestart
                                                    accentColor: ThemeBackend.mauve
                                                    baseColor: ThemeBackend.surface1
                                                    handleColor: ThemeBackend.crust
                                                    handleOffColor: ThemeBackend.text
                                                    onToggled: function(val) {
                                                        entryCard.entryRestart = val;
                                                        autostartTabRoot.flushEntry(index, "restartOnCrash", val);
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.condition_label", "Launch Condition")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        Switch {
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            options: [
                                                I18n.t("guide.autostart.condition_always", "Always"),
                                                I18n.t("guide.autostart.condition_ac_only", "AC Only"),
                                                I18n.t("guide.autostart.condition_battery_only", "Battery"),
                                                I18n.t("guide.autostart.condition_multi_monitor", "Multi-Mon")
                                            ]
                                            currentIndex: entryCard.entryCondition === "ac_only" ? 1
                                                        : (entryCard.entryCondition === "battery_only" ? 2
                                                        : (entryCard.entryCondition === "multi_monitor" ? 3 : 0))
                                            accentColor: ThemeBackend.mauve
                                            baseColor: ThemeBackend.surface0
                                            textColor: ThemeBackend.subtext0
                                            activeTextColor: ThemeBackend.crust
                                            cornerRadius: rootObj.s(6)
                                            fontPixelSize: rootObj.s(10)
                                            onToggled: function(idx) {
                                                let cond = "always";
                                                if (idx === 1) cond = "ac_only";
                                                else if (idx === 2) cond = "battery_only";
                                                else if (idx === 3) cond = "multi_monitor";
                                                if (entryCard.entryCondition !== cond) {
                                                    entryCard.entryCondition = cond;
                                                    autostartTabRoot.flushEntry(index, "condition", cond);
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
    }
}
