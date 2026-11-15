#pragma once

#include <QQuickFramebufferObject>
#include <QVariantList>

#include <mpv/client.h>
#include <mpv/render_gl.h>

class MpvRenderer;

/// The video, drawn by libmpv inside the QML scene (OpenGL render API), and the player's state as properties.
/// Resuming where a file was left (position, audio and subtitle track, subtitle delay) is mpv's watch-later,
/// kept in ~/.local/state/veo/watch_later.
class MpvObject : public QQuickFramebufferObject {
    Q_OBJECT
    Q_PROPERTY(QString source READ source NOTIFY sourceChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(bool ended READ ended NOTIFY endedChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    Q_PROPERTY(double subDelay READ subDelay WRITE setSubDelay NOTIFY subDelayChanged)
    /// Tracks: {id, title, lang, codec, channels, isDefault, external, selected}
    Q_PROPERTY(QVariantList audioTracks READ audioTracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY tracksChanged)
    Q_PROPERTY(int audioId READ audioId NOTIFY tracksChanged)
    /// 0 = subtitles off
    Q_PROPERTY(int subtitleId READ subtitleId NOTIFY tracksChanged)
    Q_PROPERTY(QSize videoSize READ videoSize NOTIFY videoSizeChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit MpvObject(QQuickItem *parent = nullptr);
    ~MpvObject() override;

    Renderer *createRenderer() const override;

    QString source() const { return m_source; }
    QString title() const { return m_title; }
    bool loaded() const { return m_loaded; }
    bool paused() const { return m_paused; }
    bool buffering() const { return m_buffering; }
    bool ended() const { return m_ended; }
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    double speed() const { return m_speed; }
    double subDelay() const { return m_subDelay; }
    QVariantList audioTracks() const { return m_audioTracks; }
    QVariantList subtitleTracks() const { return m_subtitleTracks; }
    int audioId() const { return m_audioId; }
    int subtitleId() const { return m_subtitleId; }
    QSize videoSize() const { return m_videoSize; }
    QString error() const { return m_error; }

    void setPaused(bool on);
    void setVolume(double v);
    void setMuted(bool on);
    void setSpeed(double s);
    void setSubDelay(double d);

    Q_INVOKABLE void open(const QString &path);
    Q_INVOKABLE void togglePause();
    /// seconds; relative to the current position or absolute
    Q_INVOKABLE void seek(double seconds, bool relative = true);
    Q_INVOKABLE void setAudioTrack(int id);
    /// 0 turns subtitles off
    Q_INVOKABLE void setSubtitleTrack(int id);
    Q_INVOKABLE void addSubtitle(const QString &path);
    /// Any other mpv property, as text (sub-margin-y to lift the subtitles over the controls)
    Q_INVOKABLE void setMpvProperty(const QString &name, const QString &value);
    /// Remember where the current file was left (or forget it, when it was watched to the end)
    Q_INVOKABLE void saveResume();

    // Used by the renderer
    mpv_handle *handle() const { return m_mpv; }
    mpv_render_context *renderContext() const { return m_render; }
    void setRenderContext(mpv_render_context *ctx) { m_render = ctx; }

signals:
    void sourceChanged();
    void titleChanged();
    void loadedChanged();
    void pausedChanged();
    void bufferingChanged();
    void endedChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void mutedChanged();
    void speedChanged();
    void subDelayChanged();
    void tracksChanged();
    void videoSizeChanged();
    void errorChanged();
    /// A file finished loading (the moment to show what was resumed, for instance)
    void fileLoaded(double resumedAt);

private slots:
    void processEvents();
    void requestFrame();
    /// The render context exists (first frame of the item): a file asked for before it can load now
    void renderReady();

private:
    void handlePropertyChange(uint64_t id, mpv_event_property *prop);
    void readTracks(const mpv_node *list);
    void setError(const QString &e);

    mpv_handle *m_mpv = nullptr;
    mpv_render_context *m_render = nullptr;

    // Asked for before the render context existed: mpv cannot start its video output without one
    QString m_pending;
    QString m_source;
    QString m_title;
    bool m_loaded = false;
    bool m_paused = false;
    bool m_buffering = false;
    bool m_ended = false;
    double m_position = 0;
    double m_duration = 0;
    double m_volume = 100;
    bool m_muted = false;
    double m_speed = 1;
    double m_subDelay = 0;
    QVariantList m_audioTracks;
    QVariantList m_subtitleTracks;
    int m_audioId = 0;
    int m_subtitleId = 0;
    QSize m_videoSize;
    QString m_error;
};
