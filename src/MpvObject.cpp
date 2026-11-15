#include "MpvObject.h"

#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QQuickOpenGLUtils>
#include <QQuickWindow>
#include <QStandardPaths>

#include <clocale>

namespace {

enum Observed : uint64_t {
    PauseProp = 1,
    TimeProp,
    DurationProp,
    VolumeProp,
    MuteProp,
    SpeedProp,
    SubDelayProp,
    TrackListProp,
    TitleProp,
    EofProp,
    CacheProp,
    WidthProp,
    HeightProp,
};

void *procAddress(void *, const char *name) {
    QOpenGLContext *ctx = QOpenGLContext::currentContext();
    return ctx ? reinterpret_cast<void *>(ctx->getProcAddress(QByteArray(name))) : nullptr;
}

void onRenderUpdate(void *ctx) {
    QMetaObject::invokeMethod(static_cast<MpvObject *>(ctx), "requestFrame", Qt::QueuedConnection);
}

void onWakeup(void *ctx) {
    QMetaObject::invokeMethod(static_cast<MpvObject *>(ctx), "processEvents", Qt::QueuedConnection);
}

QString nodeString(const mpv_node &n) {
    return n.format == MPV_FORMAT_STRING ? QString::fromUtf8(n.u.string) : QString();
}

QString stateDir() {
    return QDir::home().filePath(QStringLiteral(".local/state/veo"));
}

} // namespace

class MpvRenderer : public QQuickFramebufferObject::Renderer {
public:
    explicit MpvRenderer(MpvObject *obj)
        : m_obj(obj) {}

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override {
        if (!m_obj->renderContext()) {
            mpv_opengl_init_params gl{procAddress, nullptr};
            int advanced = 1;
            mpv_render_param params[] = {
                {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
                {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl},
                {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced},
                {MPV_RENDER_PARAM_INVALID, nullptr},
                {MPV_RENDER_PARAM_INVALID, nullptr},
            };
            // On Wayland mpv can share the display for hardware decoding (VA-API) without copies
            if (auto *wl = qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()) {
                params[3] = {MPV_RENDER_PARAM_WL_DISPLAY, wl->display()};
            }
            mpv_render_context *ctx = nullptr;
            if (mpv_render_context_create(&ctx, m_obj->handle(), params) < 0)
                qWarning("Veo: could not create the mpv render context");
            else
                mpv_render_context_set_update_callback(ctx, onRenderUpdate, m_obj);
            m_obj->setRenderContext(ctx);
            QMetaObject::invokeMethod(m_obj, "renderReady", Qt::QueuedConnection);
        }
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::NoAttachment);
        return new QOpenGLFramebufferObject(size, format);
    }

    void render() override {
        mpv_render_context *ctx = m_obj->renderContext();
        if (!ctx)
            return;
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo target{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flip = 0;
        mpv_render_param params[] = {
            {MPV_RENDER_PARAM_OPENGL_FBO, &target},
            {MPV_RENDER_PARAM_FLIP_Y, &flip},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(ctx, params);
        QQuickOpenGLUtils::resetOpenGLState();
    }

private:
    MpvObject *m_obj;
};

MpvObject::MpvObject(QQuickItem *parent)
    : QQuickFramebufferObject(parent) {
    // libmpv parses numbers with the C locale
    std::setlocale(LC_NUMERIC, "C");
    m_mpv = mpv_create();
    if (!m_mpv)
        qFatal("Veo: could not create mpv");

    const QString watchLater = QDir(stateDir()).filePath(QStringLiteral("watch_later"));
    QDir().mkpath(watchLater);
    // Audio and subtitles in the system's language first, then English
    const QString lang = QLocale::system().name().section(QLatin1Char('_'), 0, 0);
    // Files tag tracks with two-letter (es) or three-letter (spa) codes: both
    const QString code3 = QLocale::languageToCode(QLocale(lang).language(), QLocale::ISO639Part2);
    const QString langs = lang == QLatin1String("en") ? QStringLiteral("en,eng")
                                                       : QStringLiteral("%1,%2,en,eng").arg(lang, code3);

    const QList<QPair<const char *, QByteArray>> options = {
        {"vo", "libmpv"},
        {"hwdec", "auto-safe"},
        {"terminal", "no"},
        {"msg-level", "all=warn"},
        {"input-default-bindings", "no"},
        {"input-vo-keyboard", "no"},
        {"osc", "no"},
        {"ytdl", "no"},
        // Stay on the last frame at the end: the window offers the next file
        {"keep-open", "yes"},
        {"sub-auto", "fuzzy"},
        {"alang", langs.toUtf8()},
        {"slang", langs.toUtf8()},
        {"watch-later-dir", watchLater.toUtf8()},
        {"watch-later-options", "start,aid,sid,sub-delay"},
        {"resume-playback", "yes"},
        {"resume-playback-check-mtime", "yes"},
        {"save-position-on-quit", "no"},
        {"audio-client-name", "Veo"},
    };
    for (const auto &[name, value] : options)
        mpv_set_option_string(m_mpv, name, value.constData());

    if (mpv_initialize(m_mpv) < 0)
        qFatal("Veo: could not initialise mpv");

    mpv_observe_property(m_mpv, PauseProp, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, TimeProp, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, DurationProp, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, VolumeProp, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, MuteProp, "mute", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, SpeedProp, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, SubDelayProp, "sub-delay", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, TrackListProp, "track-list", MPV_FORMAT_NODE);
    mpv_observe_property(m_mpv, TitleProp, "media-title", MPV_FORMAT_STRING);
    mpv_observe_property(m_mpv, EofProp, "eof-reached", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, CacheProp, "paused-for-cache", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, WidthProp, "dwidth", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, HeightProp, "dheight", MPV_FORMAT_INT64);
    mpv_set_wakeup_callback(m_mpv, onWakeup, this);
}

MpvObject::~MpvObject() {
    saveResume();
    if (m_render)
        mpv_render_context_free(m_render);
    mpv_terminate_destroy(m_mpv);
}

QQuickFramebufferObject::Renderer *MpvObject::createRenderer() const {
    window()->setPersistentGraphics(true);
    window()->setPersistentSceneGraph(true);
    return new MpvRenderer(const_cast<MpvObject *>(this));
}

void MpvObject::requestFrame() {
    update();
}

void MpvObject::open(const QString &path) {
    const QString abs = QFileInfo(path).absoluteFilePath();
    if (!QFileInfo(abs).isFile()) {
        setError(abs);
        return;
    }
    saveResume();
    setError({});
    m_source = abs;
    emit sourceChanged();
    if (m_loaded) {
        m_loaded = false;
        emit loadedChanged();
    }
    if (!m_render) {
        m_pending = abs;
        return;
    }
    const QByteArray file = abs.toUtf8();
    const char *cmd[] = {"loadfile", file.constData(), nullptr};
    mpv_command_async(m_mpv, 0, cmd);
    setPaused(false);
}

void MpvObject::renderReady() {
    if (m_pending.isEmpty())
        return;
    const QString path = m_pending;
    m_pending.clear();
    open(path);
}

void MpvObject::saveResume() {
    if (!m_loaded || m_source.isEmpty())
        return;
    // Watched to (nearly) the end: next time it starts from the beginning
    const bool finished = m_ended || (m_duration > 0 && m_duration - m_position < 15);
    const char *cmd[] = {finished ? "delete-watch-later-config" : "write-watch-later-config", nullptr};
    mpv_command(m_mpv, cmd);
}

void MpvObject::togglePause() {
    if (m_ended) {
        seek(0, false);
        setPaused(false);
        return;
    }
    setPaused(!m_paused);
}

void MpvObject::setPaused(bool on) {
    int flag = on ? 1 : 0;
    mpv_set_property_async(m_mpv, 0, "pause", MPV_FORMAT_FLAG, &flag);
}

void MpvObject::setVolume(double v) {
    v = qBound(0.0, v, 100.0);
    mpv_set_property_async(m_mpv, 0, "volume", MPV_FORMAT_DOUBLE, &v);
}

void MpvObject::setMuted(bool on) {
    int flag = on ? 1 : 0;
    mpv_set_property_async(m_mpv, 0, "mute", MPV_FORMAT_FLAG, &flag);
}

void MpvObject::setSpeed(double s) {
    s = qBound(0.25, s, 4.0);
    mpv_set_property_async(m_mpv, 0, "speed", MPV_FORMAT_DOUBLE, &s);
}

void MpvObject::setSubDelay(double d) {
    mpv_set_property_async(m_mpv, 0, "sub-delay", MPV_FORMAT_DOUBLE, &d);
}

void MpvObject::seek(double seconds, bool relative) {
    const QByteArray amount = QByteArray::number(seconds, 'f', 3);
    const char *cmd[] = {"seek", amount.constData(), relative ? "relative" : "absolute+exact", nullptr};
    mpv_command_async(m_mpv, 0, cmd);
}

void MpvObject::setAudioTrack(int id) {
    const QByteArray v = QByteArray::number(id);
    mpv_set_property_string(m_mpv, "aid", v.constData());
}

void MpvObject::setSubtitleTrack(int id) {
    const QByteArray v = id > 0 ? QByteArray::number(id) : QByteArray("no");
    mpv_set_property_string(m_mpv, "sid", v.constData());
}

void MpvObject::addSubtitle(const QString &path) {
    const QByteArray file = path.toUtf8();
    const char *cmd[] = {"sub-add", file.constData(), "select", nullptr};
    mpv_command_async(m_mpv, 0, cmd);
}

void MpvObject::setMpvProperty(const QString &name, const QString &value) {
    mpv_set_property_string(m_mpv, name.toUtf8().constData(), value.toUtf8().constData());
}

void MpvObject::setError(const QString &e) {
    if (m_error == e)
        return;
    m_error = e;
    emit errorChanged();
}

void MpvObject::processEvents() {
    while (m_mpv) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        switch (event->event_id) {
        case MPV_EVENT_PROPERTY_CHANGE:
            handlePropertyChange(event->reply_userdata, static_cast<mpv_event_property *>(event->data));
            break;
        case MPV_EVENT_FILE_LOADED: {
            m_loaded = true;
            emit loadedChanged();
            double pos = 0;
            mpv_get_property(m_mpv, "time-pos", MPV_FORMAT_DOUBLE, &pos);
            emit fileLoaded(pos);
            break;
        }
        case MPV_EVENT_END_FILE: {
            auto *end = static_cast<mpv_event_end_file *>(event->data);
            if (end->reason == MPV_END_FILE_REASON_ERROR) {
                setError(m_source);
                m_loaded = false;
                emit loadedChanged();
            }
            break;
        }
        default:
            break;
        }
    }
}

void MpvObject::handlePropertyChange(uint64_t id, mpv_event_property *prop) {
    // Every change arrives through here; a property without a value (no file) reads as its neutral one
    const bool has = prop->format != MPV_FORMAT_NONE && prop->data;
    const auto flag = [&] { return has && *static_cast<int *>(prop->data) != 0; };
    const auto number = [&] { return has ? *static_cast<double *>(prop->data) : 0.0; };
    const auto integer = [&] { return has ? *static_cast<int64_t *>(prop->data) : int64_t(0); };

    switch (id) {
    case PauseProp:
        if (m_paused != flag()) {
            m_paused = flag();
            emit pausedChanged();
        }
        break;
    case TimeProp:
        m_position = number();
        emit positionChanged();
        break;
    case DurationProp:
        m_duration = number();
        emit durationChanged();
        break;
    case VolumeProp:
        if (has) {
            m_volume = number();
            emit volumeChanged();
        }
        break;
    case MuteProp:
        m_muted = flag();
        emit mutedChanged();
        break;
    case SpeedProp:
        if (has) {
            m_speed = number();
            emit speedChanged();
        }
        break;
    case SubDelayProp:
        m_subDelay = number();
        emit subDelayChanged();
        break;
    case TrackListProp:
        readTracks(has ? static_cast<mpv_node *>(prop->data) : nullptr);
        break;
    case TitleProp:
        m_title = has ? QString::fromUtf8(*static_cast<char **>(prop->data)) : QString();
        emit titleChanged();
        break;
    case EofProp:
        if (m_ended != flag()) {
            m_ended = flag();
            emit endedChanged();
        }
        break;
    case CacheProp:
        if (m_buffering != flag()) {
            m_buffering = flag();
            emit bufferingChanged();
        }
        break;
    case WidthProp:
        m_videoSize.setWidth(int(integer()));
        emit videoSizeChanged();
        break;
    case HeightProp:
        m_videoSize.setHeight(int(integer()));
        emit videoSizeChanged();
        break;
    default:
        break;
    }
}

void MpvObject::readTracks(const mpv_node *list) {
    m_audioTracks.clear();
    m_subtitleTracks.clear();
    m_audioId = 0;
    m_subtitleId = 0;
    if (list && list->format == MPV_FORMAT_NODE_ARRAY) {
        for (int i = 0; i < list->u.list->num; ++i) {
            const mpv_node &item = list->u.list->values[i];
            if (item.format != MPV_FORMAT_NODE_MAP)
                continue;
            QVariantMap track;
            QString type;
            bool selected = false;
            for (int k = 0; k < item.u.list->num; ++k) {
                const QByteArray key(item.u.list->keys[k]);
                const mpv_node &v = item.u.list->values[k];
                if (key == "type")
                    type = nodeString(v);
                else if (key == "id" && v.format == MPV_FORMAT_INT64)
                    track[QStringLiteral("id")] = int(v.u.int64);
                else if (key == "title")
                    track[QStringLiteral("title")] = nodeString(v);
                else if (key == "lang")
                    track[QStringLiteral("lang")] = nodeString(v);
                else if (key == "codec")
                    track[QStringLiteral("codec")] = nodeString(v);
                else if (key == "demux-channel-count" && v.format == MPV_FORMAT_INT64)
                    track[QStringLiteral("channels")] = int(v.u.int64);
                else if (key == "default" && v.format == MPV_FORMAT_FLAG)
                    track[QStringLiteral("isDefault")] = v.u.flag != 0;
                else if (key == "forced" && v.format == MPV_FORMAT_FLAG)
                    track[QStringLiteral("forced")] = v.u.flag != 0;
                else if (key == "external" && v.format == MPV_FORMAT_FLAG)
                    track[QStringLiteral("external")] = v.u.flag != 0;
                else if (key == "selected" && v.format == MPV_FORMAT_FLAG)
                    selected = v.u.flag != 0;
            }
            track[QStringLiteral("selected")] = selected;
            if (type == QLatin1String("audio")) {
                m_audioTracks.append(track);
                if (selected)
                    m_audioId = track.value(QStringLiteral("id")).toInt();
            } else if (type == QLatin1String("sub")) {
                m_subtitleTracks.append(track);
                if (selected)
                    m_subtitleId = track.value(QStringLiteral("id")).toInt();
            }
        }
    }
    emit tracksChanged();
}
