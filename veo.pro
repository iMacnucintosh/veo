QT += quick qml quickcontrols2 svg opengl
CONFIG += c++20 link_pkgconfig
PKGCONFIG += mpv
TARGET = veo
TEMPLATE = app

DEFINES += QT_DISABLE_DEPRECATED_BEFORE=0x060000

SOURCES += \
    src/main.cpp \
    src/JsonTranslator.cpp \
    src/Library.cpp \
    src/MpvObject.cpp \
    src/Theme.cpp

HEADERS += \
    src/JsonTranslator.h \
    src/Library.h \
    src/MpvObject.h \
    src/Theme.h

RESOURCES += qml.qrc

# Default install prefix: user-local (a package passes PREFIX=/usr)
isEmpty(PREFIX) {
    PREFIX = $$(HOME)/.local
}

target.path = $$PREFIX/bin
desktop.path = $$PREFIX/share/applications
desktop.files = data/veo.desktop
icons.path = $$PREFIX/share/icons/hicolor/scalable/apps
icons.files = data/veo.svg

INSTALLS += target desktop icons
