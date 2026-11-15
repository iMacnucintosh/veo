#include "Library.h"

#include <QCollator>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QMimeDatabase>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

namespace {

QString settingsPath() {
    return QDir::home().filePath(QStringLiteral(".local/state/veo/settings.json"));
}

const QStringList kSubtitleExts = {QStringLiteral("srt"), QStringLiteral("ass"), QStringLiteral("ssa"),
                                   QStringLiteral("vtt"), QStringLiteral("sub")};

} // namespace

Library::Library(QObject *parent)
    : QObject(parent) {
    QFile f(settingsPath());
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        m_volume = qBound(0.0, o.value(QStringLiteral("volume")).toDouble(100), 100.0);
    }
}

void Library::setVolume(double v) {
    v = qBound(0.0, v, 100.0);
    if (qFuzzyCompare(v + 1, m_volume + 1))
        return;
    m_volume = v;
    emit volumeChanged();
    save();
}

void Library::save() const {
    QDir().mkpath(QFileInfo(settingsPath()).absolutePath());
    QFile f(settingsPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        f.write(QJsonDocument(QJsonObject{{QStringLiteral("volume"), m_volume}}).toJson());
}

bool Library::isVideo(const QString &path) const {
    static QMimeDatabase db;
    const QString mime = db.mimeTypeForFile(path, QMimeDatabase::MatchExtension).name();
    return mime.startsWith(QLatin1String("video/"));
}

QString Library::fileName(const QString &path) const {
    return QFileInfo(path).completeBaseName();
}

QString Library::neighbour(const QString &path, int delta) const {
    const QFileInfo fi(path);
    QStringList files;
    const auto entries = fi.dir().entryInfoList(QDir::Files | QDir::Readable);
    for (const QFileInfo &e : entries) {
        if (isVideo(e.absoluteFilePath()))
            files << e.absoluteFilePath();
    }
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(files.begin(), files.end(), [&](const QString &a, const QString &b) { return collator.compare(a, b) < 0; });
    const int at = files.indexOf(fi.absoluteFilePath());
    const int to = at + delta;
    if (at < 0 || to < 0 || to >= files.size())
        return {};
    return files.at(to);
}

void Library::pick(const QString &kind, const QString &startDir, const QString &title, const QString &accept) {
    if (m_pick)
        return;
    const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR", QDir::tempPath());
    const QString result = QDir(runtime).filePath(QStringLiteral("veo-pick-%1.json").arg(QDateTime::currentMSecsSinceEpoch()));
    QStringList args{QStringLiteral("--pick"), QStringLiteral("--pick-mode=file"), QStringLiteral("--pick-result=") + result,
                     QStringLiteral("--pick-title=") + title, QStringLiteral("--pick-accept=") + accept};
    if (QFileInfo(startDir).isDir())
        args << QStringLiteral("--pick-current=") + startDir;
    if (kind == QLatin1String("subtitle"))
        args << QStringLiteral("--pick-extensions=") + kSubtitleExts.join(QLatin1Char(','));

    // Seeker built from source lives in ~/.local/bin, which a launcher's PATH may lack
    QString seeker = QDir::home().filePath(QStringLiteral(".local/bin/seeker"));
    if (!QFileInfo(seeker).isExecutable())
        seeker = QStandardPaths::findExecutable(QStringLiteral("seeker"));
    if (seeker.isEmpty()) {
        emit picked(kind, {});
        return;
    }

    auto *proc = new QProcess(this);
    m_pick = proc;
    m_picking = true;
    emit pickingChanged();
    proc->setStandardInputFile(QProcess::nullDevice());
    connect(proc, &QProcess::finished, this, [this, proc, kind, result] {
        proc->deleteLater();
        m_picking = false;
        emit pickingChanged();
        QString path;
        QFile f(result);
        if (f.open(QIODevice::ReadOnly)) {
            const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
            const auto uris = o.value(QStringLiteral("uris")).toArray();
            if (o.value(QStringLiteral("response")).toInt(1) == 0 && !uris.isEmpty()) {
                const QString uri = uris.first().toString();
                path = uri.startsWith(QLatin1String("file://")) ? QUrl(uri).toLocalFile() : uri;
            }
            f.close();
            f.remove();
        }
        emit picked(kind, path);
    });
    proc->start(seeker, args);
}

QString Library::languageName(const QString &code) const {
    if (code.isEmpty() || code == QLatin1String("und"))
        return {};
    const QLocale::Language language = QLocale::codeToLanguage(code, QLocale::AnyLanguageCode);
    if (language == QLocale::AnyLanguage || language == QLocale::C)
        return {};
    return QLocale::languageToString(language);
}
