import QtQuick

// Material 3 expressive spatial motion (position, size, scale, shape) at the shell's speed: a little overshoot.
// `fast` for small things (menus, buttons), the default one for larger moves.
NumberAnimation {
    property bool fast: false

    duration: Theme.ms(fast ? 350 : 500)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: fast ? [0.42, 1.67, 0.21, 0.9, 1, 1] : [0.38, 1.21, 0.22, 1, 1, 1]
}
