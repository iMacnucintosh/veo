import QtQuick

// Text in Lunele's UI font; white by default, since most of Veo sits over the picture
Text {
    color: "#ffffff"
    font.family: Theme.uiFamily
    font.pixelSize: 14
    renderType: Text.NativeRendering
    elide: Text.ElideRight
}
