// serpantinum :: Docker — live container dashboard + lifecycle control.
// Ported from Greg's HyDE "DockerHub" widget into serp's idiom (ThemeBackend tokens,
// Scaler.s() scaling, serp reusables). Data from scripts/docker-stats.py (no sudo;
// user is in the `docker` group). Overview strip + compose-project-grouped container
// list with live CPU/MEM bars. Start = single click (ClickButton); Stop/Restart =
// hold-to-confirm (serp FillButton's liquid fill), so a stray tap never kills a
// container. Actions give live feedback: a "Verbing…" pill + pulsing dot in flight,
// a red pill + inline error + notification on failure.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: root

    function s(val) { return Scaler.s(val); }

    readonly property real boxRadius:  Math.min(ThemeBackend.borderRadius, root.s(20))
    readonly property real cardRadius: Math.min(ThemeBackend.borderRadius, root.s(14))

    // accent / heat colours — serp palette (matugen-driven)
    readonly property color lime:   ThemeBackend.green
    readonly property color danger: ThemeBackend.red
    readonly property color amber:  ThemeBackend.yellow

    // status-dot semantics — fixed meaning via the palette's semantic slots
    readonly property color stOk:   ThemeBackend.green      // running / healthy
    readonly property color stBad:  ThemeBackend.red        // unhealthy / dead
    readonly property color stWarn: ThemeBackend.yellow     // starting / restarting
    readonly property color stOff:  ThemeBackend.overlay0   // created / exited / paused

    // ── data ──
    property bool ok: true
    property bool loaded: false
    property string errKind: ""
    property var overview: ({ running: 0, total: 0, healthy: 0, unhealthy: 0, images: 0, disk: "—" })
    property var groups: []

    function heat(v, warn, hot) { return v < warn ? lime : (v < hot ? amber : danger); }

    function dotColor(c) {
        if (c.state === "running") {
            if (c.health === "unhealthy") return stBad;
            if (c.health === "starting")  return stWarn;
            return stOk;
        }
        if (c.state === "restarting") return stWarn;
        if (c.state === "dead")       return stBad;
        return stOff;
    }

    Process {
        id: statsProc
        command: ["python3", Caching.serpantinumDir + "/scripts/docker-stats.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    root.loaded = true;
                    root.ok = d.ok !== false;
                    root.errKind = d.error ?? "";
                    if (root.ok) {
                        root.overview = d.overview ?? root.overview;
                        root.groups = d.groups ?? [];
                        root.reconcileActing();
                    }
                } catch (e) { /* ignore a bad sample */ }
            }
        }
    }
    // poll every 2s, but only while the widget is actually shown
    Timer {
        interval: 2000; repeat: true; running: root.visible; triggeredOnStart: true
        onTriggered: statsProc.running = true
    }

    // ── lifecycle actions — state keyed by container id, survives the 2s scrape ──
    property var acting: ({})
    function setActing(id, v) { var m = Object.assign({}, acting); m[id] = v; acting = m; }
    function clearActing(id)  { var m = Object.assign({}, acting); delete m[id]; acting = m; }
    function gerund(v)    { return v === "start" ? "Starting…" : v === "stop" ? "Stopping…" : "Restarting…"; }
    function verbColor(v) { return v === "start" ? stOk : v === "stop" ? danger : amber; }

    Timer { id: refreshTimer; interval: 600; onTriggered: statsProc.running = true }

    function doAction(id, verb) {
        if (!id || !verb) return;
        if (acting[id] && acting[id].phase === "run") return;
        setActing(id, { verb: verb, phase: "run", err: "" });
        var p = actionProcComp.createObject(root, { cid: id, verb: verb });
        p.command = ["docker", verb, id];
        p.running = true;
    }
    function onActionExit(id, verb, code, errText) {
        if (code === 0) {
            setActing(id, { verb: verb, phase: "done", err: "" });
            statsProc.running = true;
            refreshTimer.restart();
        } else {
            var msg = (errText || "").replace(/\s+/g, " ").trim()
                                     .replace(/^Error response from daemon:\s*/i, "");
            if (!msg) msg = "exit " + code;
            setActing(id, { verb: verb, phase: "fail", err: msg });
            notifyProc.command = ["notify-send", "-u", "critical", "Docker: " + verb + " failed", msg];
            notifyProc.running = true;
        }
    }
    function reconcileActing() {
        var ids = {};
        for (var gi = 0; gi < groups.length; gi++)
            for (var ci = 0; ci < groups[gi].containers.length; ci++)
                ids[groups[gi].containers[ci].id] = true;
        var m = Object.assign({}, acting), changed = false;
        for (var id in m)
            if (m[id].phase === "done" || !ids[id]) { delete m[id]; changed = true; }
        if (changed) acting = m;
    }

    Component {
        id: actionProcComp
        Process {
            id: aproc
            property string cid: ""
            property string verb: ""
            stderr: StdioCollector { id: aerr }
            onExited: function(exitCode, exitStatus) {
                root.onActionExit(aproc.cid, aproc.verb, exitCode, aerr.text);
                aproc.destroy();
            }
        }
    }
    Process { id: notifyProc }

    // ── panel surface (serp look) ──
    Rectangle {
        id: panel
        anchors.fill: parent
        color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.97)
        radius: Math.min(ThemeBackend.borderRadius, root.s(28))
        clip: true

        // ── ambient gradient blobs (ilyamiro-style: faint, blurred accent ovals) ──
        Item {
            id: ambient
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 64; blur: 1.0 }
            Rectangle {   // top-right, cool accent
                x: parent.width - width * 0.6; y: -height * 0.4
                width: root.s(380); height: root.s(300); radius: width
                color: Qt.rgba(ThemeBackend.blue.r, ThemeBackend.blue.g, ThemeBackend.blue.b, 0.10)
            }
            Rectangle {   // bottom-left, warm accent
                x: -width * 0.38; y: parent.height - height * 0.62
                width: root.s(360); height: root.s(300); radius: width
                color: Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.09)
            }
            Rectangle {   // mid-right whisper, teal
                x: parent.width - width * 0.35; y: parent.height * 0.42
                width: root.s(240); height: root.s(200); radius: width
                color: Qt.rgba(ThemeBackend.sapphire.r, ThemeBackend.sapphire.g, ThemeBackend.sapphire.b, 0.07)
            }
        }

        MouseArea { anchors.fill: parent }   // swallow clicks on empty area

        readonly property int headerH: root.s(120)

        // ── title + daemon dot ──
        Row {
            id: titleRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top; anchors.topMargin: root.s(20)
            spacing: root.s(10)
            Rectangle {
                width: root.s(9); height: root.s(9); radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.ok ? root.lime : root.danger
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            Text {
                text: "Docker"; color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(16); font.bold: true
            }
        }

        // ── overview strip ──
        Row {
            id: overviewRow
            visible: root.ok
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top; anchors.topMargin: root.s(50)
            spacing: root.s(30)

            component Stat : Column {
                property string value: ""
                property string label: ""
                property color valueColor: ThemeBackend.text
                property bool show: true
                visible: show
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.value; color: parent.valueColor
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(18); font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.label; color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10)
                }
            }

            Stat { value: root.overview.running + "/" + root.overview.total; label: "running" }
            Stat { value: "" + root.overview.healthy;   label: "healthy";   valueColor: root.lime }
            Stat { value: "" + root.overview.unhealthy; label: "unhealthy"; valueColor: root.danger; show: root.overview.unhealthy > 0 }
            Stat { value: "" + root.overview.images;    label: "images" }
            Stat { value: root.overview.disk;           label: "disk" }
        }

        // ── container list (grouped by compose project), scrollable ──
        Flickable {
            id: listFlick
            visible: root.ok
            anchors.left: parent.left; anchors.right: parent.right
            anchors.leftMargin: root.s(18); anchors.rightMargin: root.s(18)
            anchors.top: parent.top; anchors.topMargin: panel.headerH
            anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(16)
            contentWidth: width
            contentHeight: listCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listCol
                width: listFlick.width
                spacing: root.s(12)

                Text {
                    visible: root.overview.total === 0
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    topPadding: root.s(40)
                    text: root.loaded ? "No containers" : "Loading…"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(14)
                }

                Repeater {
                    model: root.groups
                    delegate: Column {
                        id: grp
                        required property var modelData
                        width: listCol.width
                        spacing: root.s(8)

                        Text {
                            text: grp.modelData.project
                            color: ThemeBackend.subtext0
                            font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(12); font.bold: true
                            leftPadding: root.s(4)
                        }

                        Repeater {
                            model: grp.modelData.containers
                            delegate: Rectangle {
                                id: crow
                                required property var modelData
                                width: grp.width; height: root.s(78); radius: root.cardRadius
                                color: Qt.darker(ThemeBackend.surface0, 1.04)
                                border.color: ThemeBackend.surface1; border.width: 1

                                readonly property bool isRunning: crow.modelData.state === "running"
                                readonly property var act: root.acting[crow.modelData.id] || null

                                // status dot — recolours to the verb + pulses while acting
                                Rectangle {
                                    id: dot
                                    anchors.left: parent.left; anchors.leftMargin: root.s(14)
                                    anchors.top: parent.top; anchors.topMargin: root.s(16)
                                    width: root.s(10); height: root.s(10); radius: width / 2
                                    color: (crow.act && crow.act.phase === "run")
                                           ? root.verbColor(crow.act.verb) : root.dotColor(crow.modelData)
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    SequentialAnimation on opacity {
                                        running: crow.act && crow.act.phase === "run"
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.3; duration: 450; easing.type: Easing.InOutQuad }
                                        NumberAnimation { to: 1;   duration: 450; easing.type: Easing.InOutQuad }
                                        onRunningChanged: if (!running) dot.opacity = 1
                                    }
                                }

                                // name + meta
                                Column {
                                    anchors.left: dot.right; anchors.leftMargin: root.s(12)
                                    anchors.right: bars.left; anchors.rightMargin: root.s(12)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: root.s(4)
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: crow.modelData.name
                                        color: ThemeBackend.text
                                        font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(14); font.bold: true
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: crow.modelData.image
                                              + (crow.modelData.ports.length ? "  ·  " + crow.modelData.ports.join(" ") : "")
                                        color: ThemeBackend.subtext1
                                        font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: (crow.act && crow.act.phase === "fail")
                                              ? ("⚠ " + crow.act.err) : crow.modelData.status
                                        color: (crow.act && crow.act.phase === "fail") ? root.danger : ThemeBackend.subtext0
                                        font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10)
                                    }
                                }

                                // CPU / MEM mini-bars
                                Column {
                                    id: bars
                                    anchors.right: actionZone.left; anchors.rightMargin: root.s(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(120); spacing: root.s(8)

                                    component Meter : Column {
                                        property string label: ""
                                        property real value: 0
                                        property bool live: false
                                        property real warn: 60
                                        property real hot: 85
                                        width: parent.width; spacing: root.s(2)
                                        Row {
                                            width: parent.width
                                            Text { text: parent.parent.label; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(9) }
                                            Item { width: parent.width - vTxt.width - root.s(24); height: 1 }
                                            Text { id: vTxt; text: parent.parent.live ? parent.parent.value + "%" : "—"; color: ThemeBackend.subtext1; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(9) }
                                        }
                                        Rectangle {
                                            width: parent.width; height: root.s(4); radius: height / 2; color: ThemeBackend.surface1
                                            Rectangle {
                                                height: parent.height; radius: height / 2
                                                width: parent.width * Math.min(1, (parent.parent.live ? parent.parent.value : 0) / 100)
                                                color: root.heat(parent.parent.value, parent.parent.warn, parent.parent.hot)
                                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    Meter { label: "CPU"; value: crow.modelData.cpu;     live: crow.isRunning; warn: 60; hot: 85 }
                                    Meter { label: "MEM"; value: crow.modelData.memPerc; live: crow.isRunning; warn: 70; hot: 90 }
                                }

                                // actions — fixed-width zone anchored right
                                Item {
                                    id: actionZone
                                    anchors.right: parent.right; anchors.rightMargin: root.s(14)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(172); height: parent.height

                                    // NORMAL — buttons (hidden while acting)
                                    Row {
                                        visible: !crow.act
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: root.s(8)

                                        // START — single click (safe)
                                        ClickButton {
                                            visible: !crow.isRunning
                                            width: root.s(64); height: root.s(32)
                                            cornerRadius: root.s(9)
                                            buttonText: "Start"; textFontSize: root.s(12)
                                            accentColor: ThemeBackend.surface0
                                            textColor: root.stOk
                                            onClicked: root.doAction(crow.modelData.id, "start")
                                        }
                                        // STOP — hold to confirm (serp liquid fill)
                                        FillButton {
                                            visible: crow.isRunning
                                            width: root.s(72); height: root.s(32)
                                            maxWidth: root.s(72); cornerRadius: root.s(9)
                                            horizontalPadding: root.s(10); textFontSize: root.s(12)
                                            buttonText: "Stop"; fillDuration: 650; autoResetTimeout: 900
                                            baseColor: ThemeBackend.surface0
                                            hoverColor: ThemeBackend.surface1
                                            accentColor: root.danger
                                            textColor: root.danger
                                            filledTextColor: ThemeBackend.crust
                                            onTriggered: root.doAction(crow.modelData.id, "stop")
                                        }
                                        // RESTART — hold to confirm
                                        FillButton {
                                            visible: crow.isRunning
                                            width: root.s(84); height: root.s(32)
                                            maxWidth: root.s(84); cornerRadius: root.s(9)
                                            horizontalPadding: root.s(10); textFontSize: root.s(12)
                                            buttonText: "Restart"; fillDuration: 650; autoResetTimeout: 900
                                            baseColor: ThemeBackend.surface0
                                            hoverColor: ThemeBackend.surface1
                                            accentColor: root.amber
                                            textColor: ThemeBackend.text
                                            filledTextColor: ThemeBackend.crust
                                            onTriggered: root.doAction(crow.modelData.id, "restart")
                                        }
                                    }

                                    // IN-FLIGHT / just-succeeded — progress pill
                                    Rectangle {
                                        visible: crow.act && crow.act.phase !== "fail"
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(160); height: root.s(32); radius: root.s(9)
                                        color: ThemeBackend.surface0
                                        border.width: 1
                                        border.color: crow.act ? root.verbColor(crow.act.verb) : "transparent"
                                        Row {
                                            anchors.centerIn: parent; spacing: root.s(8)
                                            Rectangle {
                                                id: pillDot
                                                width: root.s(8); height: root.s(8); radius: width / 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: crow.act ? root.verbColor(crow.act.verb) : "transparent"
                                                SequentialAnimation on opacity {
                                                    running: crow.act && crow.act.phase === "run"
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.25; duration: 450; easing.type: Easing.InOutQuad }
                                                    NumberAnimation { to: 1;    duration: 450; easing.type: Easing.InOutQuad }
                                                    onRunningChanged: if (!running) pillDot.opacity = 1
                                                }
                                            }
                                            Text {
                                                text: crow.act ? root.gerund(crow.act.verb) : ""
                                                color: ThemeBackend.text
                                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(12); font.bold: true
                                            }
                                        }
                                    }

                                    // FAILED — red pill, click to dismiss
                                    Rectangle {
                                        visible: crow.act && crow.act.phase === "fail"
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: root.s(160); height: root.s(32); radius: root.s(9)
                                        color: Qt.rgba(root.danger.r, root.danger.g, root.danger.b, 0.14)
                                        border.color: root.danger; border.width: 1
                                        Text { anchors.centerIn: parent; text: "⚠ Failed · dismiss"; color: root.danger; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11); font.bold: true }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.clearActing(crow.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── daemon-down / error card ──
        Item {
            anchors.fill: parent
            visible: !root.ok
            Column {
                anchors.centerIn: parent; spacing: root.s(10)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.s(44); height: root.s(44); radius: width / 2
                    color: "transparent"; border.color: root.danger; border.width: 2
                    Text { anchors.centerIn: parent; text: "!"; color: root.danger; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(24); font.bold: true }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.errKind === "daemon" ? "Docker daemon not running"
                          : root.errKind === "timeout" ? "Docker timed out" : "Docker unavailable"
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(15); font.bold: true
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.errKind === "daemon" ? "start it with:  systemctl start docker" : "retrying…"
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                }
            }
        }
    }
}
