import QtQuick
import QtQuick.Layouts

// A small card of choices over the picture (audio, subtitles, speed). `entries`: [{label, detail, checked, action}].
// `footer` takes extra rows (the subtitle delay).
Rectangle {
    id: root

    property string title: ""
    property var entries: []
    property alias footer: footerSlot.data
    property bool open: false

    signal picked()

    width: 300
    height: Math.min(column.implicitHeight + 16, 460)
    radius: 20
    color: Theme.surfaceContainer
    visible: opacity > 0.01
    // Grows out of its button (bottom right) with a little overshoot, at the shell's speed
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.86
    transformOrigin: Item.BottomRight
    transform: Translate {
        y: root.open ? 0 : 10

        Behavior on y {
            SpatialAnim { fast: true }
        }
    }

    Behavior on opacity {
        EffectsAnim { fast: true }
    }
    Behavior on scale {
        SpatialAnim { fast: true }
    }

    // Clicks inside do not reach the picture
    MouseArea {
        anchors.fill: parent
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 8
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 2

            VText {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.topMargin: 6
                Layout.bottomMargin: 4
                text: root.title
                color: Theme.onSurfaceVariant
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Repeater {
                model: root.entries

                Rectangle {
                    id: row
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: entryCol.implicitHeight + 18
                    radius: modelData.checked ? 14 : 10
                    color: modelData.checked ? Theme.secondaryContainer : "transparent"

                    Behavior on color {
                        EffectsColour {}
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        ColumnLayout {
                            id: entryCol
                            Layout.fillWidth: true
                            spacing: 0

                            VText {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                color: row.modelData.checked ? Theme.onSecondaryContainer : Theme.onSurface
                                font.weight: row.modelData.checked ? Font.Medium : Font.Normal
                            }
                            VText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: row.modelData.detail || ""
                                color: Theme.onSurfaceVariant
                                font.pixelSize: 12
                            }
                        }

                        MaterialIcon {
                            visible: row.modelData.checked
                            icon: "check"
                            size: 20
                            colour: Theme.onSecondaryContainer
                        }
                    }

                    StateLayer {
                        radius: row.radius
                        color: Theme.onSurface
                        onClicked: {
                            row.modelData.action()
                            root.picked()
                        }
                    }
                }
            }

            ColumnLayout {
                id: footerSlot
                Layout.fillWidth: true
                spacing: 2
            }
        }
    }
}
