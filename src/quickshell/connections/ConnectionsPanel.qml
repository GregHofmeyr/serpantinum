// serpantinum :: Connections — Cloudflare WARP + KDE Connect phone hub.
// Ported from Greg's HyDE ConnectionsHub (VPN + phone parts; serp already covers
// wifi/BT natively). WARP via warp-cli; phone via scripts/kdeconnect.sh. Rebuilt in
// serp's idiom (ThemeBackend tokens, Scaler.s() scaling, serp reusables, ambient blobs).
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
    readonly property real cardRadius: Math.min(ThemeBackend.borderRadius, root.s(16))

    // ── WARP / VPN state ──
    property bool warpConnected: false
    property string warpStatus: "…"
    Process {
        id: warpStat
        command: ["warp-cli", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text;
                root.warpConnected = /Connected\b/.test(t);
                root.warpStatus = root.warpConnected ? "Connected"
                    : (/Connecting/.test(t) ? "Connecting…" : "Disconnected");
            }
        }
    }
    Process { id: warpToggle; onExited: warpStat.running = true }
    function toggleWarp() {
        root.warpStatus = root.warpConnected ? "Disconnecting…" : "Connecting…";
        warpToggle.command = ["warp-cli", root.warpConnected ? "disconnect" : "connect"];
        warpToggle.running = true;
    }
    Timer {
        interval: 2500; repeat: true; running: root.visible; triggeredOnStart: true
        onTriggered: warpStat.running = true
    }

    // live WARP tunnel stats
    property string warpLatency: "—"
    property string warpLoss: "—"
    property string warpSent: "—"
    property string warpRecv: "—"
    property string warpEndpoint: "—"
    property string warpProto: "—"
    property string warpHandshake: "—"
    Process {
        id: warpStatsProc
        command: ["warp-cli", "tunnel", "stats"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text;
                function m(re, d) { var r = re.exec(t); return r ? r[1] : d; }
                root.warpLatency = m(/Estimated latency:\s*(\S+)/, "—");
                root.warpLoss = m(/Estimated loss:\s*(\S+)/, "—");
                var sr = /Sent:\s*([\d.]+\s*\w?B);\s*Received:\s*([\d.]+\s*\w?B)/.exec(t);
                root.warpSent = sr ? sr[1] : "—";
                root.warpRecv = sr ? sr[2] : "—";
                root.warpEndpoint = m(/Endpoints:\s*([^,\n]+)/, "—");
                root.warpProto = m(/Tunnel Protocol:\s*(\S+)/, "—");
                root.warpHandshake = m(/last handshake:\s*(\S+)/, "—");
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: root.visible && root.warpConnected
        onTriggered: warpStatsProc.running = true
    }

    // ── Phone (KDE Connect) state ──
    readonly property string kdeScript: Caching.serpantinumDir + "/scripts/kdeconnect.sh"
    property bool   phoneReachable: false
    property string phoneName: "Phone"
    property int    phoneBattery: -1
    property bool   phoneCharging: false
    property string phoneSigType: ""
    property int    phoneSigStrength: -1
    readonly property color battColor: phoneCharging ? ThemeBackend.green
        : phoneBattery < 0  ? ThemeBackend.overlay0
        : phoneBattery <= 15 ? ThemeBackend.red
        : phoneBattery <= 35 ? ThemeBackend.yellow
        : ThemeBackend.text
    readonly property string battGlyph: {
        var b = phoneBattery;
        if (b < 0)   return "󰂑";
        if (b >= 90) return "󰁹";
        if (b >= 70) return "󰂀";
        if (b >= 50) return "󰁾";
        if (b >= 30) return "󰁼";
        if (b >= 10) return "󰁺";
        return "󰂎";
    }
    Process {
        id: phoneProc
        command: ["bash", root.kdeScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    root.phoneReachable = d.reachable === true;
                    if (d.reachable) {
                        root.phoneName = d.name || "Phone";
                        root.phoneBattery = (d.battery !== undefined) ? d.battery : -1;
                        root.phoneCharging = d.charging === true;
                        root.phoneSigType = d.sigType || "";
                        root.phoneSigStrength = (d.sigStrength !== undefined) ? d.sigStrength : -1;
                    }
                } catch (e) { root.phoneReachable = false; }
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; running: root.visible; triggeredOnStart: true
        onTriggered: phoneProc.running = true
    }
    Process { id: phoneActionProc }
    function phoneAction(cmd) { phoneActionProc.command = ["bash", root.kdeScript, cmd]; phoneActionProc.running = true; }

    // ── panel surface (serp look) ──
    Rectangle {
        id: panel
        anchors.fill: parent
        color: Qt.rgba(ThemeBackend.base.r, ThemeBackend.base.g, ThemeBackend.base.b, 0.97)
        radius: Math.min(ThemeBackend.borderRadius, root.s(28))
        clip: true

        // ── ambient gradient blobs ──
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blurMax: 64; blur: 1.0 }
            Rectangle {
                x: parent.width - width * 0.6; y: -height * 0.4
                width: root.s(360); height: root.s(300); radius: width
                color: Qt.rgba(ThemeBackend.sapphire.r, ThemeBackend.sapphire.g, ThemeBackend.sapphire.b, 0.10)
            }
            Rectangle {
                x: -width * 0.38; y: parent.height - height * 0.6
                width: root.s(340); height: root.s(300); radius: width
                color: Qt.rgba(ThemeBackend.mauve.r, ThemeBackend.mauve.g, ThemeBackend.mauve.b, 0.09)
            }
        }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(18)
            spacing: root.s(14)

            // ── header ──
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: root.s(4)
                text: "Connections"
                color: ThemeBackend.text
                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(16); font.bold: true
            }

            // ── WARP card ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: warpCol.implicitHeight + root.s(28)
                radius: root.cardRadius
                color: Qt.darker(ThemeBackend.surface0, 1.04)
                border.color: ThemeBackend.surface1; border.width: 1

                ColumnLayout {
                    id: warpCol
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.s(14)
                    spacing: root.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(12)
                        Text {
                            text: "󰖂"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(24)
                            color: root.warpConnected ? ThemeBackend.green : ThemeBackend.subtext0
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: "Cloudflare WARP"; color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(13); font.bold: true
                            }
                            Text {
                                text: root.warpStatus
                                color: root.warpConnected ? ThemeBackend.green
                                       : /…/.test(root.warpStatus) ? ThemeBackend.yellow : ThemeBackend.subtext0
                                font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Toggle {
                            checked: root.warpConnected
                            accentColor: ThemeBackend.green
                            onToggled: root.toggleWarp()
                        }
                    }

                    // tunnel stats grid (when connected)
                    GridLayout {
                        visible: root.warpConnected
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: root.s(18); rowSpacing: root.s(6)

                        component Stat : RowLayout {
                            property string k: ""
                            property string v: ""
                            Layout.fillWidth: true
                            spacing: root.s(8)
                            Text { text: parent.k; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10) }
                            Item { Layout.fillWidth: true }
                            Text { text: parent.v; color: ThemeBackend.subtext1; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(10); elide: Text.ElideRight }
                        }
                        Stat { k: "Latency";  v: root.warpLatency }
                        Stat { k: "Loss";     v: root.warpLoss }
                        Stat { k: "Sent";     v: root.warpSent }
                        Stat { k: "Recv";     v: root.warpRecv }
                        Stat { k: "Protocol"; v: root.warpProto }
                        Stat { k: "Handshake";v: root.warpHandshake }
                        Stat { k: "Endpoint"; v: root.warpEndpoint }
                    }
                }
            }

            // ── Phone (KDE Connect) card ──
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.cardRadius
                color: Qt.darker(ThemeBackend.surface0, 1.04)
                border.color: ThemeBackend.surface1; border.width: 1

                // unreachable state
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !root.phoneReachable
                    spacing: root.s(8)
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰄜"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(40); color: ThemeBackend.overlay0 }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "No phone connected"; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(13) }
                }

                // reachable — device header + actions
                ColumnLayout {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.s(14)
                    visible: root.phoneReachable
                    spacing: root.s(14)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(12)
                        Text { text: "󰄜"; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(26); color: ThemeBackend.text }
                        ColumnLayout {
                            spacing: 0
                            Text { text: root.phoneName; color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(14); font.bold: true }
                            Text {
                                text: root.phoneSigType !== "" ? (root.phoneSigType + (root.phoneSigStrength >= 0 ? "  ·  " + root.phoneSigStrength + "/4" : "")) : "connected"
                                color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(11)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        RowLayout {
                            spacing: root.s(6)
                            Text { text: root.battGlyph; font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(20); color: root.battColor }
                            Text { text: root.phoneBattery >= 0 ? root.phoneBattery + "%" : "—"; color: root.battColor; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(13); font.bold: true }
                        }
                    }

                    // action buttons
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: root.s(8); rowSpacing: root.s(8)

                        component Act : ClickButton {
                            property string cmd: ""
                            Layout.fillWidth: true
                            implicitHeight: root.s(52)
                            cornerRadius: root.s(10)
                            accentColor: Qt.darker(ThemeBackend.surface1, 1.02)
                            textColor: ThemeBackend.text
                            iconFontSize: root.s(18); textFontSize: root.s(10)
                            contentAlignment: Qt.AlignHCenter
                            onClicked: root.phoneAction(cmd)
                        }
                        Act { buttonIcon: "󰂚"; buttonText: "Ring";     cmd: "ring" }
                        Act { buttonIcon: "󰅍"; buttonText: "Clip";     cmd: "clip" }
                        Act { buttonIcon: "󰈤"; buttonText: "Share";    cmd: "share" }
                        Act { buttonIcon: "󰉏"; buttonText: "Photos";   cmd: "photos" }
                        Act { buttonIcon: "󰉋"; buttonText: "Files";    cmd: "files" }
                        Act { buttonIcon: "󰍡"; buttonText: "Messages"; cmd: "messages" }
                        Act { buttonIcon: "󰍹"; buttonText: "Mirror";   cmd: "mirror" }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
