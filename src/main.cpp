#include "JsonTranslator.h"
#include "Library.h"
#include "MpvObject.h"
#include "Theme.h"

#include <QCommandLineParser>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QLocale>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QTimer>
#include <QUrl>

namespace {

/// The code is in English; a language with a catalogue in i18n/<lang>.json (VEO_LANG overrides the system one)
/// is shown translated.
void installTranslation(QCoreApplication &app) {
    const QString lang = qEnvironmentVariable("VEO_LANG", QLocale::system().name()).section(QLatin1Char('_'), 0, 0);
    auto *t = new JsonTranslator(&app);
    if (t->loadFile(QStringLiteral(":/i18n/%1.json").arg(lang)))
        app.installTranslator(t);
    else
        delete t;
}

void loadSylphrenaUiFont() {
    const QStringList candidates = {
        QDir::home().filePath(QStringLiteral(
            ".config/quickshell/sylphrena/assets/google-sans-flex/"
            "GoogleSansFlex-VariableFont_GRAD,ROND,opsz,slnt,wdth,wght.ttf")),
        QDir::home().filePath(QStringLiteral(".local/share/seeker/fonts/GoogleSansFlex.ttf")),
    };
    for (const QString &path : candidates) {
        if (QFile::exists(path) && QFontDatabase::addApplicationFont(path) >= 0)
            return;
    }
}

} // namespace

int main(int argc, char *argv[]) {
    // libmpv draws through OpenGL into the scene
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");

    QGuiApplication app(argc, argv);
    installTranslation(app);
    app.setOrganizationName(QStringLiteral("Sylphrena"));
    app.setApplicationName(QStringLiteral("Veo"));
    app.setApplicationDisplayName(QStringLiteral("Veo"));
    app.setDesktopFileName(QStringLiteral("veo"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("veo"), QIcon(QStringLiteral(":/data/veo.svg"))));
    loadSylphrenaUiFont();

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Veo — video player"));
    parser.addHelpOption();
    parser.addPositionalArgument(QStringLiteral("file"), QStringLiteral("Video to play"));
    parser.addOption({QStringLiteral("shot"), QStringLiteral("(dev) save the window to this file and quit"), QStringLiteral("png")});
    parser.addOption({QStringLiteral("shot-delay"), QStringLiteral("(dev) ms before --shot"), QStringLiteral("ms"), QStringLiteral("3000")});
    parser.addOption({QStringLiteral("shot-ui"), QStringLiteral("(dev) state to show before --shot: controls, audio, subtitles, speed, next"), QStringLiteral("state")});
    parser.process(app);

    // A file manager may hand over a file:// URL
    QString start = parser.positionalArguments().value(0);
    if (start.startsWith(QLatin1String("file://")))
        start = QUrl(start).toLocalFile();
    if (!start.isEmpty())
        start = QFileInfo(start).absoluteFilePath();

    qmlRegisterType<MpvObject>("Veo", 1, 0, "Mpv");

    Theme theme;
    Library library;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("Theme"), &theme);
    engine.rootContext()->setContextProperty(QStringLiteral("Library"), &library);
    engine.rootContext()->setContextProperty(QStringLiteral("StartFile"), start);
    engine.rootContext()->setContextProperty(QStringLiteral("DevShotUi"), parser.value(QStringLiteral("shot-ui")));
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 1;

    // Development: --shot saves the window after --shot-delay ms and quits, to check the UI without looking
    if (const QString shot = parser.value(QStringLiteral("shot")); !shot.isEmpty()) {
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QTimer::singleShot(parser.value(QStringLiteral("shot-delay")).toInt(), &app, [window, shot] {
            if (window)
                window->grabWindow().save(shot);
            QGuiApplication::quit();
        });
    }
    return app.exec();
}
