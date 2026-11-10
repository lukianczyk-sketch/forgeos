// ForgeOS Show Me How (Job 22): ring, arrow and sentence drawn by KWin on top of everything; clicks go
// straight through (outputOnly). This file never changes (KWin caches it): what it shows comes from
// forgeos-showme over D-Bus every 250 ms (own() = our label + step panel, never pointed at).
// It keeps the step panel on top, away from the arrow.
import QtQuick
import QtQuick.Window
import org.kde.kwin

Item {
    id: root
    property var st: ({ "show": false })
    property real big: st.size ? st.size : 1
    property rect area: Workspace.virtualScreenGeometry
    property var panelWin: null

    function own() {
        var r = [];
        if (area.width <= 0 || area.height <= 0)
            return "[]";
        if (over.visible)
            r.push([label.x / area.width, label.y / area.height, label.width / area.width, label.height / area.height]);
        if (panelWin) {
            var g = panelWin.frameGeometry;
            r.push([(g.x - area.x) / area.width, (g.y - area.y) / area.height, g.width / area.width, g.height / area.height]);
        }
        return JSON.stringify(r);
    }

    function place() {
        if (!panelWin)
            return;
        panelWin.keepAbove = true;
        var c = st.corner ? st.corner : "rb";
        var g = panelWin.frameGeometry;
        var x = c.charAt(0) === "r" ? area.x + area.width - g.width - 24 : area.x + 24;
        var y = c.charAt(1) === "b" ? area.y + area.height - g.height - 80 : area.y + 24;
        if (Math.abs(g.x - x) > 2 || Math.abs(g.y - y) > 2)
            panelWin.frameGeometry = Qt.rect(x, y, g.width, g.height);
    }

    function isPanel(w) {
        return w && w.caption === "Show Me How" && String(w.resourceClass).indexOf("kdialog") >= 0;
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            if (root.isPanel(w)) {
                root.panelWin = w;
                root.place();
            }
        }
        function onWindowRemoved(w) {
            if (w === root.panelWin)
                root.panelWin = null;
        }
    }

    DBusCall {
        id: poll
        service: "org.forgeos.ShowMe"
        path: "/ShowMe"
        dbusInterface: "org.forgeos.ShowMe"
        method: "State"
        onFinished: (returnValue) => {
            try {
                root.st = JSON.parse(returnValue[0]);
            } catch (e) {
                root.st = { "show": false };
            }
            root.place();
        }
        onFailed: root.st = { "show": false }
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            poll.arguments = [root.own()];
            poll.call();
        }
    }

    Window {
        id: over
        property bool outputOnly: true
        property int kwin_windowType: 16
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
        color: "transparent"
        x: root.area.x
        y: root.area.y
        width: root.area.width
        height: root.area.height
        visible: root.st.show === true
        transientParent: null

        property real pad: 14 * root.big
        property real tx: (root.st.x || 0) * width - pad
        property real ty: (root.st.y || 0) * height - pad
        property real tw: (root.st.w || 0) * width + 2 * pad
        property real th: (root.st.h || 0) * height + 2 * pad
        property bool below: ty < 260 * root.big

        Rectangle {
            id: ring
            x: over.tx
            y: over.ty
            width: over.tw
            height: over.th
            radius: 12 * root.big
            color: "#26FFD400"
            border.color: "#FFD400"
            border.width: 6 * root.big
            SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation { to: 1.12; duration: 600; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            }
        }

        Canvas {
            id: arrow
            width: 60 * root.big
            height: 90 * root.big
            x: over.tx + over.tw / 2 - width / 2
            y: over.below ? over.ty + over.th + 8 : over.ty - height - 8
            rotation: over.below ? 180 : 0
            onPaint: {
                var c = getContext("2d");
                var w = width;
                var h = height;
                c.reset();
                c.beginPath();
                c.moveTo(w * 0.32, 0);
                c.lineTo(w * 0.68, 0);
                c.lineTo(w * 0.68, h * 0.55);
                c.lineTo(w, h * 0.55);
                c.lineTo(w / 2, h);
                c.lineTo(0, h * 0.55);
                c.lineTo(w * 0.32, h * 0.55);
                c.closePath();
                c.fillStyle = "#FFD400";
                c.strokeStyle = "#202020";
                c.lineWidth = 3;
                c.fill();
                c.stroke();
            }
            onWidthChanged: requestPaint()
        }

        Rectangle {
            id: label
            width: Math.min(words.implicitWidth, 520 * root.big) + 40 * root.big
            height: words.contentHeight + 28 * root.big
            x: Math.max(8, Math.min(over.width - width - 8, over.tx + over.tw / 2 - width / 2))
            y: over.below ? arrow.y + arrow.height + 8 : arrow.y - height - 8
            radius: 10 * root.big
            color: "#1E1E1E"
            border.color: "#FFD400"
            border.width: 3 * root.big
            Text {
                id: words
                anchors.centerIn: parent
                width: label.width - 40 * root.big
                text: root.st.say ? root.st.say : ""
                color: "white"
                font.pixelSize: 24 * root.big
                font.bold: true
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
