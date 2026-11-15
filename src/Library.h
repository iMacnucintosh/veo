#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QString>

/// What Veo needs around the player: the files next to the one playing (previous / next, like the episodes of a
/// series), Seeker's file picker, and the settings kept between runs (volume).
class Library : public QObject {
    Q_OBJECT
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool picking READ picking NOTIFY pickingChanged)

public:
    explicit Library(QObject *parent = nullptr);

    double volume() const { return m_volume; }
    void setVolume(double v);
    bool picking() const { return m_picking; }

    /// The video `delta` places away from path in its folder (natural order: 2 before 10), or "" at the ends
    Q_INVOKABLE QString neighbour(const QString &path, int delta) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    /// Opens Seeker to choose a file; `kind` is "video" or "subtitle". Answers with picked().
    Q_INVOKABLE void pick(const QString &kind, const QString &startDir, const QString &title, const QString &accept);
    Q_INVOKABLE bool isVideo(const QString &path) const;
    /// "nl", "dut" → "Dutch": the English name of a language code, "" if unknown (the interface translates the common ones)
    Q_INVOKABLE QString languageName(const QString &code) const;

signals:
    void volumeChanged();
    void pickingChanged();
    void picked(const QString &kind, const QString &path);

private:
    void save() const;

    double m_volume = 100;
    bool m_picking = false;
    QPointer<QProcess> m_pick;
};
