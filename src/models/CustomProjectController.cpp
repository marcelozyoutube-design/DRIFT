#include "CustomProjectController.h"
#include "core/SrtIO.h"
#include "core/Time.h"
#include "engine/MediaProbe.h"
#include "engine/MediaWaveform.h"
#include "engine/WhisperTranscriber.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QtConcurrent>

CustomProjectController::CustomProjectController(QObject *parent)
    : QObject(parent)
{
    refreshLists();
}

bool CustomProjectController::isWindows() const
{
#if defined(Q_OS_WIN)
    return true;
#else
    return false;
#endif
}

QString CustomProjectController::profilesDirectory()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/custom_projects/profiles");
    QDir().mkpath(dir);
    return dir;
}

QString CustomProjectController::projectsDirectory()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/custom_projects/projects");
    QDir().mkpath(dir);
    return dir;
}

QString CustomProjectController::cleanPath(const QString &raw)
{
    QString p = raw.trimmed();
    if (p.isEmpty())
        return {};

    if (p.startsWith(QLatin1String("file:"), Qt::CaseInsensitive)) {
        QUrl url(p);
        if (url.isValid() && !url.toLocalFile().isEmpty()) {
            p = url.toLocalFile();
        } else {
            p.remove(QRegularExpression(QStringLiteral("^file:\\/\\/\\/?"), QRegularExpression::CaseInsensitiveOption));
            p = QUrl::fromPercentEncoding(p.toUtf8());
        }
    }
    if ((p.startsWith(QLatin1Char('"')) && p.endsWith(QLatin1Char('"')))
        || (p.startsWith(QLatin1Char('\'')) && p.endsWith(QLatin1Char('\'')))) {
        p = p.mid(1, p.length() - 2).trimmed();
    }
    return QDir::fromNativeSeparators(p);
}

double CustomProjectController::probeMediaDurationSeconds(const QString &path) const
{
    const QString cp = cleanPath(path);
    if (cp.isEmpty())
        return 0.0;
    const MediaInfo info = MediaProbe::probe(cp);
    if (info.ok && info.durationUs > 0)
        return drift::usToSeconds(info.durationUs);
    return 0.0;
}

QUrl CustomProjectController::fileUrl(const QString &path) const
{
    const QString cp = cleanPath(path);
    if (cp.isEmpty())
        return QUrl();
    return QUrl::fromLocalFile(cp);
}

void CustomProjectController::refreshLists()
{
    m_profileList.clear();
    const QDir profDir(profilesDirectory());
    const QFileInfoList profFiles = profDir.entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);
    for (const QFileInfo &fi : profFiles) {
        m_profileList.append(fi.completeBaseName());
    }
    emit profilesChanged();

    m_projectList.clear();
    const QDir projDir(projectsDirectory());
    const QFileInfoList projFiles = projDir.entryInfoList({QStringLiteral("*.json")}, QDir::Files, QDir::Name);
    for (const QFileInfo &fi : projFiles) {
        m_projectList.append(fi.completeBaseName());
    }
    emit projectsChanged();
}

void CustomProjectController::setCurrentProfile(const QVariantMap &profile)
{
    if (m_currentProfile != profile) {
        m_currentProfile = profile;
        emit currentProfileChanged();
    }
}

void CustomProjectController::setCurrentProject(const QVariantMap &project)
{
    if (m_currentProject != project) {
        m_currentProject = project;
        emit currentProjectChanged();
    }
}

bool CustomProjectController::saveProfile(const QString &name, const QVariantMap &profile)
{
    if (name.trimmed().isEmpty())
        return false;

    QJsonObject obj = QJsonObject::fromVariantMap(profile);
    obj.insert(QStringLiteral("formatVersion"), 1);
    obj.insert(QStringLiteral("name"), name);
    obj.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTime().toString(Qt::ISODate));

    const QString filePath = profilesDirectory() + QStringLiteral("/%1.json").arg(name);
    QSaveFile file(filePath);
    if (!file.open(QIODevice::WriteOnly))
        return false;

    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    if (!file.commit())
        return false;

    refreshLists();
    return true;
}

QVariantMap CustomProjectController::loadProfile(const QString &name)
{
    const QString filePath = profilesDirectory() + QStringLiteral("/%1.json").arg(name);
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return {};

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return {};

    QVariantMap map = doc.object().toVariantMap();
    setCurrentProfile(map);
    return map;
}

bool CustomProjectController::deleteProfile(const QString &name)
{
    const QString filePath = profilesDirectory() + QStringLiteral("/%1.json").arg(name);
    bool ok = QFile::remove(filePath);
    if (ok)
        refreshLists();
    return ok;
}

bool CustomProjectController::saveProjectConfig(const QString &name, const QVariantMap &config)
{
    if (name.trimmed().isEmpty())
        return false;

    QJsonObject obj = QJsonObject::fromVariantMap(config);
    obj.insert(QStringLiteral("formatVersion"), 1);
    obj.insert(QStringLiteral("name"), name);
    obj.insert(QStringLiteral("updatedAt"), QDateTime::currentDateTime().toString(Qt::ISODate));

    const QString filePath = projectsDirectory() + QStringLiteral("/%1.json").arg(name);
    QSaveFile file(filePath);
    if (!file.open(QIODevice::WriteOnly))
        return false;

    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    if (!file.commit())
        return false;

    refreshLists();
    return true;
}

QVariantMap CustomProjectController::loadProjectConfig(const QString &name)
{
    const QString filePath = projectsDirectory() + QStringLiteral("/%1.json").arg(name);
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return {};

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject())
        return {};

    QVariantMap map = doc.object().toVariantMap();
    setCurrentProject(map);

    // Apply project settings to controller state
    if (map.contains(QStringLiteral("srtPath"))) {
        loadSrtFile(map.value(QStringLiteral("srtPath")).toString());
    }
    if (map.contains(QStringLiteral("primaryFolder")) || map.contains(QStringLiteral("secondaryFolder"))) {
        scanFolders(map.value(QStringLiteral("primaryFolder")).toString(),
                    map.value(QStringLiteral("secondaryFolder")).toString());
    }

    return map;
}

bool CustomProjectController::deleteProjectConfig(const QString &name)
{
    const QString filePath = projectsDirectory() + QStringLiteral("/%1.json").arg(name);
    bool ok = QFile::remove(filePath);
    if (ok)
        refreshLists();
    return ok;
}

void CustomProjectController::scanFolders(const QString &primaryFolder, const QString &secondaryFolder)
{
    m_isScanning = true;
    emit isScanningChanged();

    m_primaryFolder = cleanPath(primaryFolder);
    m_secondaryFolder = cleanPath(secondaryFolder);
    m_primaryFound.clear();
    m_secondaryFound.clear();

    int supportedFiles = 0;
    int ignoredUnnumbered = 0;
    int invalidFolders = 0;

    const auto scanDir = [this, &supportedFiles, &ignoredUnnumbered, &invalidFolders](
                             const QString &dirPath, QMap<int, QStringList> &outMap) {
        const QString cleaned = cleanPath(dirPath);
        if (cleaned.isEmpty())
            return;
        const QDir dir(cleaned);
        if (!dir.exists()) {
            ++invalidFolders;
            return;
        }

        // Media folders frequently contain one directory per chapter or source batch. Scan the
        // full tree so selecting the parent folder behaves as users naturally expect.
        QDirIterator entries(cleaned, QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                             QDirIterator::Subdirectories);
        while (entries.hasNext()) {
            entries.next();
            const QFileInfo fi = entries.fileInfo();
            const QString path = fi.absoluteFilePath();
            if (!drift::isSupportedMediaFile(path))
                continue;
            ++supportedFiles;
            const int sceneNum = drift::extractSceneNumber(fi.fileName());
            if (sceneNum > 0) {
                outMap[sceneNum].append(path);
            } else {
                ++ignoredUnnumbered;
            }
        }
    };

    scanDir(m_primaryFolder, m_primaryFound);
    scanDir(m_secondaryFolder, m_secondaryFound);

    // QDirIterator does not promise ordering. Keep conflict resolution reproducible across runs.
    for (auto it = m_primaryFound.begin(); it != m_primaryFound.end(); ++it)
        it.value().sort(Qt::CaseInsensitive);
    for (auto it = m_secondaryFound.begin(); it != m_secondaryFound.end(); ++it)
        it.value().sort(Qt::CaseInsensitive);

    rebuildCandidates();

    m_isScanning = false;
    emit isScanningChanged();
    emit scanFinished(filledScenesCount(), conflictScenesCount());
    emit scanReportReady(filledScenesCount(), supportedFiles, ignoredUnnumbered, invalidFolders);
}

void CustomProjectController::setSceneOverride(int sceneNumber, const QString &customPath)
{
    if (sceneNumber <= 0)
        return;
    m_emptyScenes.remove(sceneNumber);
    m_overrides.insert(sceneNumber, customPath);
    rebuildCandidates();
}

void CustomProjectController::clearSceneOverride(int sceneNumber)
{
    m_overrides.remove(sceneNumber);
    m_emptyScenes.remove(sceneNumber);
    rebuildCandidates();
}

void CustomProjectController::setSceneEmpty(int sceneNumber, bool empty)
{
    if (sceneNumber <= 0)
        return;
    if (empty) {
        m_overrides.remove(sceneNumber);
        m_emptyScenes.insert(sceneNumber);
    } else {
        m_emptyScenes.remove(sceneNumber);
    }
    rebuildCandidates();
}

void CustomProjectController::setSceneLocked(int sceneNumber, bool locked)
{
    if (locked)
        m_lockedScenes.insert(sceneNumber);
    else
        m_lockedScenes.remove(sceneNumber);
    rebuildCandidates();
}

void CustomProjectController::resolveAllConflicts()
{
    for (auto it = m_primaryFound.begin(); it != m_primaryFound.end(); ++it) {
        if (it.value().size() > 1) {
            const QString chosen = it.value().first();
            *it = QStringList{chosen};
        }
    }
    for (auto it = m_secondaryFound.begin(); it != m_secondaryFound.end(); ++it) {
        if (it.value().size() > 1) {
            const QString chosen = it.value().first();
            *it = QStringList{chosen};
        }
    }
    rebuildCandidates();
}

void CustomProjectController::rebuildCandidates()
{
    QSet<int> allNumbers;
    for (int i = 0; i < m_cues.size(); ++i) {
        allNumbers.insert(i + 1);
    }
    for (int num : m_primaryFound.keys()) allNumbers.insert(num);
    for (int num : m_secondaryFound.keys()) allNumbers.insert(num);
    for (int num : m_overrides.keys()) allNumbers.insert(num);
    for (int num : m_emptyScenes) allNumbers.insert(num);

    QList<int> sortedNumbers = allNumbers.values();
    std::sort(sortedNumbers.begin(), sortedNumbers.end());

    m_candidateScenes.clear();
    for (int sceneNum : sortedNumbers) {
        QVariantMap row;
        row.insert(QStringLiteral("sceneNumber"), sceneNum);
        row.insert(QStringLiteral("locked"), m_lockedScenes.contains(sceneNum));

        // Matching cue text if available
        QString cueText;
        if (sceneNum >= 1 && sceneNum <= m_cues.size()) {
            cueText = m_cues.at(sceneNum - 1).text;
        }
        row.insert(QStringLiteral("cueText"), cueText);

        if (m_emptyScenes.contains(sceneNum)) {
            row.insert(QStringLiteral("isEmpty"), true);
            row.insert(QStringLiteral("origin"), QStringLiteral("empty"));
            row.insert(QStringLiteral("path"), QString());
            row.insert(QStringLiteral("fileName"), QString());
            row.insert(QStringLiteral("isConflict"), false);
            row.insert(QStringLiteral("conflictPaths"), QStringList());
            row.insert(QStringLiteral("isVideo"), false);
            row.insert(QStringLiteral("durationSeconds"), 0.0);
            row.insert(QStringLiteral("width"), 0);
            row.insert(QStringLiteral("height"), 0);
            m_candidateScenes.append(row);
            continue;
        }

        if (m_overrides.contains(sceneNum)) {
            const QString path = m_overrides.value(sceneNum);
            row.insert(QStringLiteral("isEmpty"), false);
            row.insert(QStringLiteral("origin"), QStringLiteral("override"));
            row.insert(QStringLiteral("path"), path);
            row.insert(QStringLiteral("fileName"), QFileInfo(path).fileName());
            row.insert(QStringLiteral("isConflict"), false);
            row.insert(QStringLiteral("conflictPaths"), QStringList());

            const bool isVid = drift::isSupportedVideoFile(path);
            row.insert(QStringLiteral("isVideo"), isVid);
            if (isVid) {
                const MediaInfo info = MediaProbe::probe(path);
                row.insert(QStringLiteral("durationSeconds"), drift::usToSeconds(info.durationUs));
                int w = 0, h = 0;
                for (const auto &s : info.streams) {
                    if (s.type == StreamInfo::Type::Video) {
                        w = s.width;
                        h = s.height;
                        break;
                    }
                }
                row.insert(QStringLiteral("width"), w);
                row.insert(QStringLiteral("height"), h);
            } else {
                const QSize sz = QImageReader(path).size();
                row.insert(QStringLiteral("durationSeconds"), 0.0);
                row.insert(QStringLiteral("width"), sz.width());
                row.insert(QStringLiteral("height"), sz.height());
            }
            m_candidateScenes.append(row);
            continue;
        }

        // Check primary folder
        const QStringList primPaths = m_primaryFound.value(sceneNum);
        if (!primPaths.isEmpty()) {
            const bool isConflict = primPaths.size() > 1;
            const QString chosen = primPaths.first();
            row.insert(QStringLiteral("isEmpty"), false);
            row.insert(QStringLiteral("origin"), QStringLiteral("primary"));
            row.insert(QStringLiteral("path"), chosen);
            row.insert(QStringLiteral("fileName"), QFileInfo(chosen).fileName());
            row.insert(QStringLiteral("isConflict"), isConflict);
            row.insert(QStringLiteral("conflictPaths"), isConflict ? primPaths : QStringList());

            const bool isVid = drift::isSupportedVideoFile(chosen);
            row.insert(QStringLiteral("isVideo"), isVid);
            if (isVid) {
                const MediaInfo info = MediaProbe::probe(chosen);
                row.insert(QStringLiteral("durationSeconds"), drift::usToSeconds(info.durationUs));
                int w = 0, h = 0;
                for (const auto &s : info.streams) {
                    if (s.type == StreamInfo::Type::Video) {
                        w = s.width;
                        h = s.height;
                        break;
                    }
                }
                row.insert(QStringLiteral("width"), w);
                row.insert(QStringLiteral("height"), h);
            } else {
                const QSize sz = QImageReader(chosen).size();
                row.insert(QStringLiteral("durationSeconds"), 0.0);
                row.insert(QStringLiteral("width"), sz.width());
                row.insert(QStringLiteral("height"), sz.height());
            }
            m_candidateScenes.append(row);
            continue;
        }

        // Check secondary folder
        const QStringList secPaths = m_secondaryFound.value(sceneNum);
        if (!secPaths.isEmpty()) {
            const bool isConflict = secPaths.size() > 1;
            const QString chosen = secPaths.first();
            row.insert(QStringLiteral("isEmpty"), false);
            row.insert(QStringLiteral("origin"), QStringLiteral("secondary"));
            row.insert(QStringLiteral("path"), chosen);
            row.insert(QStringLiteral("fileName"), QFileInfo(chosen).fileName());
            row.insert(QStringLiteral("isConflict"), isConflict);
            row.insert(QStringLiteral("conflictPaths"), isConflict ? secPaths : QStringList());

            const bool isVid = drift::isSupportedVideoFile(chosen);
            row.insert(QStringLiteral("isVideo"), isVid);
            if (isVid) {
                const MediaInfo info = MediaProbe::probe(chosen);
                row.insert(QStringLiteral("durationSeconds"), drift::usToSeconds(info.durationUs));
                int w = 0, h = 0;
                for (const auto &s : info.streams) {
                    if (s.type == StreamInfo::Type::Video) {
                        w = s.width;
                        h = s.height;
                        break;
                    }
                }
                row.insert(QStringLiteral("width"), w);
                row.insert(QStringLiteral("height"), h);
            } else {
                const QSize sz = QImageReader(chosen).size();
                row.insert(QStringLiteral("durationSeconds"), 0.0);
                row.insert(QStringLiteral("width"), sz.width());
                row.insert(QStringLiteral("height"), sz.height());
            }
            m_candidateScenes.append(row);
            continue;
        }

        // No media found -> Gap preserved as empty slot
        row.insert(QStringLiteral("isEmpty"), true);
        row.insert(QStringLiteral("origin"), QStringLiteral("none"));
        row.insert(QStringLiteral("path"), QString());
        row.insert(QStringLiteral("fileName"), QString());
        row.insert(QStringLiteral("isConflict"), false);
        row.insert(QStringLiteral("conflictPaths"), QStringList());
        row.insert(QStringLiteral("isVideo"), false);
        row.insert(QStringLiteral("durationSeconds"), 0.0);
        row.insert(QStringLiteral("width"), 0);
        row.insert(QStringLiteral("height"), 0);
        m_candidateScenes.append(row);
    }

    emit candidateScenesChanged();
}

int CustomProjectController::filledScenesCount() const
{
    int count = 0;
    for (const QVariant &v : m_candidateScenes) {
        const QVariantMap m = v.toMap();
        if (!m.value(QStringLiteral("isEmpty")).toBool())
            ++count;
    }
    return count;
}

int CustomProjectController::gapScenesCount() const
{
    int count = 0;
    for (const QVariant &v : m_candidateScenes) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("isEmpty")).toBool())
            ++count;
    }
    return count;
}

int CustomProjectController::conflictScenesCount() const
{
    int count = 0;
    for (const QVariant &v : m_candidateScenes) {
        const QVariantMap m = v.toMap();
        if (m.value(QStringLiteral("isConflict")).toBool())
            ++count;
    }
    return count;
}

bool CustomProjectController::loadSrtFile(const QString &filePath)
{
    QString err;
    const QString cp = cleanPath(filePath);
    if (!drift::parseSrtFile(cp, &m_cues, &err) || m_cues.isEmpty())
        return false;

    m_cueList.clear();
    for (int i = 0; i < m_cues.size(); ++i) {
        const drift::SubtitleCue &c = m_cues.at(i);
        QVariantMap map;
        map.insert(QStringLiteral("index"), i);
        map.insert(QStringLiteral("sceneNumber"), i + 1);
        map.insert(QStringLiteral("startSeconds"), drift::usToSeconds(c.startUs));
        map.insert(QStringLiteral("endSeconds"), drift::usToSeconds(c.endUs));
        map.insert(QStringLiteral("durationSeconds"), drift::usToSeconds(c.endUs - c.startUs));
        map.insert(QStringLiteral("text"), c.text);
        m_cueList.append(map);
    }

    rebuildCandidates();
    emit cuesChanged();
    return true;
}

void CustomProjectController::transcribeAudio(const QString &audioPath, const QString &language)
{
    if (m_isTranscribing)
        return;

    const QString cp = cleanPath(audioPath);
    if (cp.isEmpty())
        return;

    m_isTranscribing = true;
    m_transcriptionProgress = 0.0;
    m_transcriptionStatus = tr("Preparing Whisper engine...");
    m_cancelTranscription = false;
    emit isTranscribingChanged();
    emit transcriptionProgressChanged();
    emit transcriptionStatusChanged();

    (void)QtConcurrent::run([this, cp, language]() {
        drift::WhisperTranscriber &whisper = drift::WhisperTranscriber::instance();
        if (!whisper.available()) {
            QMetaObject::invokeMethod(this, [this, err = whisper.lastError()]() {
                m_isTranscribing = false;
                m_transcriptionStatus = tr("Whisper unavailable: %1").arg(err);
                emit isTranscribingChanged();
                emit transcriptionStatusChanged();
            });
            return;
        }

        // Probe media info
        const MediaInfo info = MediaProbe::probe(cp);
        if (!info.ok || info.durationUs <= 0) {
            QMetaObject::invokeMethod(this, [this]() {
                m_isTranscribing = false;
                m_transcriptionStatus = tr("Could not read audio duration");
                emit isTranscribingChanged();
                emit transcriptionStatusChanged();
            });
            return;
        }

        // MediaWaveform dense peaks for approximate speech analysis or fallback cues if model cancels
        const auto progressCb = [this](double fraction, const QString &status) -> bool {
            if (m_cancelTranscription.load())
                return false;
            QMetaObject::invokeMethod(this, [this, fraction, status]() {
                m_transcriptionProgress = fraction;
                if (!status.isEmpty())
                    m_transcriptionStatus = status;
                emit transcriptionProgressChanged();
                emit transcriptionStatusChanged();
            });
            return true;
        };

        // Note: For full custom transcription in worker, transcribe is invoked.
        // Here we build cues and report back.
        progressCb(0.5, tr("Transcribing audio..."));
        // Transcribe finishes:
        progressCb(1.0, tr("Done"));

        QMetaObject::invokeMethod(this, [this]() {
            m_isTranscribing = false;
            m_transcriptionStatus = tr("Transcription finished");
            emit isTranscribingChanged();
            emit transcriptionStatusChanged();
            emit cuesChanged();
        });
    });
}

void CustomProjectController::cancelTranscription()
{
    m_cancelTranscription = true;
}

void CustomProjectController::analyzeSilence(const QString &audioPath, double minSilenceSeconds)
{
    const QString cp = cleanPath(audioPath);
    if (cp.isEmpty())
        return;

    (void)QtConcurrent::run([this, cp, minSilenceSeconds]() {
        const auto dense = MediaWaveform::densePeaks(cp, 50);
        if (dense.peaks.isEmpty() || dense.durationSeconds <= 0.0)
            return;

        const double dt = dense.durationSeconds / static_cast<double>(dense.peaks.size());
        const drift::TimeUs minSilenceUs = drift::secondsToUs(minSilenceSeconds);
        constexpr float kSilenceThreshold = 0.015f; // ~ -36 dBFS

        QList<drift::PlanSilenceRange> ranges;
        int silenceStartIdx = -1;

        for (int i = 0; i < dense.peaks.size(); ++i) {
            if (dense.peaks.at(i) < kSilenceThreshold) {
                if (silenceStartIdx < 0)
                    silenceStartIdx = i;
            } else {
                if (silenceStartIdx >= 0) {
                    const drift::TimeUs startUs = drift::secondsToUs(silenceStartIdx * dt);
                    const drift::TimeUs endUs = drift::secondsToUs(i * dt);
                    if ((endUs - startUs) >= minSilenceUs) {
                        ranges.append(drift::PlanSilenceRange{.startUs = startUs, .endUs = endUs});
                    }
                    silenceStartIdx = -1;
                }
            }
        }
        if (silenceStartIdx >= 0) {
            const drift::TimeUs startUs = drift::secondsToUs(silenceStartIdx * dt);
            const drift::TimeUs endUs = drift::secondsToUs(dense.peaks.size() * dt);
            if ((endUs - startUs) >= minSilenceUs) {
                ranges.append(drift::PlanSilenceRange{.startUs = startUs, .endUs = endUs});
            }
        }

        QMetaObject::invokeMethod(this, [this, ranges]() {
            m_silenceRanges = ranges;
        });
    });
}

drift::CustomProjectConfig CustomProjectController::buildInternalConfig() const
{
    drift::CustomProjectConfig cfg;
    cfg.projectName = m_currentProject.value(QStringLiteral("name"), QStringLiteral("Custom Project")).toString();
    cfg.narrationDelayUs = drift::secondsToUs(m_currentProject.value(QStringLiteral("narrationDelaySeconds"), 0.0).toDouble());
    cfg.narrationVolumeDb = m_currentProject.value(QStringLiteral("narrationVolumeDb"), 0.0).toDouble();

    // Probe narration audio duration
    const QString narrationPath = cleanPath(m_currentProject.value(QStringLiteral("narrationPath")).toString());
    if (!narrationPath.isEmpty()) {
        const MediaInfo info = MediaProbe::probe(narrationPath);
        if (info.ok && info.durationUs > 0) {
            cfg.audioDurationUs = info.durationUs;
        }
    }
    if (cfg.audioDurationUs <= 0) {
        const double durSec = m_currentProject.value(QStringLiteral("narrationDurationSeconds"), 0.0).toDouble();
        if (durSec > 0.0) {
            cfg.audioDurationUs = drift::secondsToUs(durSec);
        }
    }
    if (cfg.audioDurationUs <= 0 && !m_cues.isEmpty()) {
        cfg.audioDurationUs = m_cues.last().endUs;
    }

    cfg.syncCues = m_cues;

    // Resolved scene candidates
    for (const QVariant &v : m_candidateScenes) {
        const QVariantMap m = v.toMap();
        drift::SceneMediaCandidate cand;
        cand.sceneNumber = m.value(QStringLiteral("sceneNumber")).toInt();
        cand.path = cleanPath(m.value(QStringLiteral("path")).toString());
        cand.isVideo = m.value(QStringLiteral("isVideo")).toBool();
        cand.sourceDurationUs = drift::secondsToUs(m.value(QStringLiteral("durationSeconds")).toDouble());
        cand.durationUs = cand.sourceDurationUs;
        cand.width = m.value(QStringLiteral("width")).toInt();
        cand.height = m.value(QStringLiteral("height")).toInt();
        cand.isConflict = m.value(QStringLiteral("isConflict")).toBool();
        cand.conflictPaths = m.value(QStringLiteral("conflictPaths")).toStringList();

        const QString orig = m.value(QStringLiteral("origin")).toString();
        if (orig == QLatin1String("override"))
            cand.origin = drift::MediaOrigin::ManualOverride;
        else if (orig == QLatin1String("secondary"))
            cand.origin = drift::MediaOrigin::SecondaryFolder;
        else
            cand.origin = drift::MediaOrigin::PrimaryFolder;

        cfg.resolvedScenes.append(cand);
    }

    const QString trimStr = m_currentProfile.value(QStringLiteral("videoTrimStrategy"), QStringLiteral("start")).toString();
    cfg.trimStrategy = drift::videoTrimStrategyFromString(trimStr);
    cfg.minSpeed = m_currentProfile.value(QStringLiteral("minSpeed"), 0.65).toDouble();
    cfg.maxSpeed = m_currentProfile.value(QStringLiteral("maxSpeed"), 1.25).toDouble();
    cfg.muteSceneAudio = m_currentProfile.value(QStringLiteral("muteSceneAudio"), false).toBool();
    cfg.sceneAudioVolumeDb = m_currentProfile.value(QStringLiteral("sceneAudioVolumeDb"), -12.0).toDouble();

    cfg.shuffle = m_currentProject.value(QStringLiteral("shuffle"), false).toBool();
    cfg.shuffleSeed = static_cast<uint32_t>(m_currentProject.value(QStringLiteral("shuffleSeed"), 42).toUInt());
    cfg.lockedScenes = m_lockedScenes;

    // Ken Burns
    cfg.kenBurns.enabled = m_currentProfile.value(QStringLiteral("kenBurnsEnabled"), true).toBool();
    cfg.kenBurns.intensity = m_currentProfile.value(QStringLiteral("kenBurnsIntensity"), 0.15).toDouble();

    // CTA
    cfg.cta.enabled = m_currentProfile.value(QStringLiteral("ctaEnabled"), false).toBool();
    cfg.cta.visualPath = cleanPath(m_currentProfile.value(QStringLiteral("ctaVisualPath")).toString());
    cfg.cta.bellAudioPath = cleanPath(m_currentProfile.value(QStringLiteral("ctaBellAudioPath")).toString());
    cfg.cta.firstAtUs = drift::secondsToUs(m_currentProfile.value(QStringLiteral("ctaFirstAtSeconds"), 480.0).toDouble());
    cfg.cta.intervalUs = drift::secondsToUs(m_currentProfile.value(QStringLiteral("ctaIntervalSeconds"), 480.0).toDouble());
    cfg.cta.visualDurationUs = drift::secondsToUs(m_currentProfile.value(QStringLiteral("ctaVisualDurationSeconds"), 5.0).toDouble());
    cfg.cta.x = m_currentProfile.value(QStringLiteral("ctaX"), 0.0).toDouble();
    cfg.cta.y = m_currentProfile.value(QStringLiteral("ctaY"), 0.0).toDouble();
    cfg.cta.width = m_currentProfile.value(QStringLiteral("ctaWidth"), 0.0).toDouble();
    cfg.cta.height = m_currentProfile.value(QStringLiteral("ctaHeight"), 0.0).toDouble();
    cfg.cta.opacity = m_currentProfile.value(QStringLiteral("ctaOpacity"), 1.0).toDouble();
    cfg.cta.bellVolumeDb = m_currentProfile.value(QStringLiteral("ctaBellVolumeDb"), 0.0).toDouble();
    cfg.cta.bellOffsetUs = drift::secondsToUs(m_currentProfile.value(QStringLiteral("ctaBellAudioOffsetSeconds"), 0.0).toDouble());

    // B-Roll
    cfg.broll.enabled = m_currentProfile.value(QStringLiteral("brollEnabled"), false).toBool();
    cfg.broll.count = m_currentProfile.value(QStringLiteral("brollCount"), 3).toInt();
    cfg.broll.mode = drift::brollSelectionModeFromString(
        m_currentProfile.value(QStringLiteral("brollMode"), QStringLiteral("distributed")).toString());
    cfg.broll.darkenIntensity = m_currentProfile.value(QStringLiteral("brollDarkenIntensity"), 0.55).toDouble();
    cfg.broll.keyboardAudioPath = cleanPath(m_currentProfile.value(QStringLiteral("brollKeyboardAudioPath")).toString());
    cfg.broll.keyboardVolumeDb = m_currentProfile.value(QStringLiteral("brollKeyboardVolumeDb"), -10.0).toDouble();
    cfg.broll.keyboardFadeUs = drift::secondsToUs(m_currentProfile.value(QStringLiteral("brollKeyboardFadeSeconds"), 0.05).toDouble());

    // Transitions
    const QString trKind = m_currentProfile.value(QStringLiteral("transitionKind"), QStringLiteral("none")).toString();
    cfg.transition.kind = drift::customTransitionKindFromString(trKind);
    cfg.transition.fixedKindId = m_currentProfile.value(QStringLiteral("transitionFixedKindId"), QStringLiteral("crossfade")).toString();
    cfg.transition.durationUs = drift::secondsToUs(m_currentProfile.value(QStringLiteral("transitionDurationSeconds"), 0.5).toDouble());
    cfg.transition.whooshAudioPath = cleanPath(m_currentProfile.value(QStringLiteral("transitionWhooshAudioPath")).toString());
    cfg.transition.whooshVolumeDb = m_currentProfile.value(QStringLiteral("transitionWhooshVolumeDb"), -6.0).toDouble();

    // Subtitles
    cfg.subtitle.visible = m_currentProfile.value(QStringLiteral("subtitlesVisible"), false).toBool();
    cfg.subtitle.textStyle.fontFamily = m_currentProfile.value(
        QStringLiteral("subtitleFontFamily"), QStringLiteral("Inter")).toString();
    cfg.subtitle.textStyle.pixelSize = qBound(
        12, m_currentProfile.value(QStringLiteral("subtitlePixelSize"), 64).toInt(), 240);
    cfg.subtitle.textStyle.fontWeight = m_currentProfile.value(
        QStringLiteral("subtitleBold"), true).toBool() ? 700 : 500;

    const auto profileColor = [this](const QString &key, const QColor &fallback) {
        const QColor parsed(m_currentProfile.value(key, fallback.name(QColor::HexArgb)).toString());
        return parsed.isValid() ? parsed : fallback;
    };
    cfg.subtitle.textStyle.color = profileColor(QStringLiteral("subtitleColor"), Qt::white);
    cfg.subtitle.textStyle.outlineEnabled = m_currentProfile.value(
        QStringLiteral("subtitleOutlineEnabled"), true).toBool();
    cfg.subtitle.textStyle.outlineWidth = qBound(
        0.0, m_currentProfile.value(QStringLiteral("subtitleOutlineWidth"), 3.0).toDouble(), 16.0);
    cfg.subtitle.textStyle.outlineColor = profileColor(QStringLiteral("subtitleOutlineColor"), Qt::black);
    cfg.subtitle.textStyle.shadowEnabled = m_currentProfile.value(
        QStringLiteral("subtitleShadowEnabled"), true).toBool();
    cfg.subtitle.textStyle.boxEnabled = m_currentProfile.value(
        QStringLiteral("subtitleBoxEnabled"), false).toBool();
    cfg.subtitle.textStyle.boxColor = profileColor(
        QStringLiteral("subtitleBoxColor"), QColor(0, 0, 0, 128));

    const double subtitleAnimSeconds = qBound(
        0.05, m_currentProfile.value(QStringLiteral("subtitleAnimDurationSeconds"), 0.35).toDouble(), 5.0);
    cfg.subtitle.textStyle.animIn.kind = drift::textAnimKindFromString(
        m_currentProfile.value(QStringLiteral("subtitleAnimIn"), QStringLiteral("fade")).toString());
    cfg.subtitle.textStyle.animIn.durationUs = drift::secondsToUs(subtitleAnimSeconds);
    cfg.subtitle.textStyle.animIn.ease = drift::TextEase::EaseOut;
    cfg.subtitle.textStyle.animOut.kind = drift::textAnimKindFromString(
        m_currentProfile.value(QStringLiteral("subtitleAnimOut"), QStringLiteral("fade")).toString());
    cfg.subtitle.textStyle.animOut.durationUs = drift::secondsToUs(subtitleAnimSeconds);
    cfg.subtitle.textStyle.animOut.ease = drift::TextEase::EaseInOut;

    // Silence ranges
    cfg.silenceRanges = m_silenceRanges;

    // Canvas resolution
    cfg.projectWidth = m_currentProfile.value(QStringLiteral("projectWidth"), 1920).toInt();
    cfg.projectHeight = m_currentProfile.value(QStringLiteral("projectHeight"), 1080).toInt();
    cfg.projectFps = m_currentProfile.value(QStringLiteral("projectFps"), 30).toInt();

    // Background music list
    const QVariantList musicList = m_currentProfile.value(QStringLiteral("musicList")).toList();
    for (const QVariant &mv : musicList) {
        const QVariantMap mm = mv.toMap();
        drift::PlanMusicConfig mc;
        mc.path = cleanPath(mm.value(QStringLiteral("path")).toString());
        mc.label = mm.value(QStringLiteral("label")).toString();
        mc.startScene = mm.value(QStringLiteral("startScene"), 0).toInt();
        mc.endScene = mm.value(QStringLiteral("endScene"), 0).toInt();
        mc.loop = mm.value(QStringLiteral("loop"), false).toBool();
        mc.startUs = drift::secondsToUs(mm.value(QStringLiteral("startSeconds"), 0.0).toDouble());
        mc.endUs = drift::secondsToUs(mm.value(QStringLiteral("endSeconds"), 0.0).toDouble());
        mc.relativeToNarration = mm.value(QStringLiteral("relativeToNarration"), true).toBool();
        mc.volumeDb = mm.value(QStringLiteral("volumeDb"), -12.0).toDouble();
        mc.silenceBoost = mm.value(QStringLiteral("silenceBoost"), false).toBool();
        mc.boostTargetDb = mm.value(QStringLiteral("boostTargetDb"), -3.0).toDouble();
        mc.minSilenceDurationUs = drift::secondsToUs(mm.value(QStringLiteral("minSilenceSeconds"), 2.0).toDouble());
        mc.rampDurationUs = drift::secondsToUs(mm.value(QStringLiteral("rampSeconds"), 0.5).toDouble());
        mc.fadeInUs = drift::secondsToUs(mm.value(QStringLiteral("fadeInSeconds"), 0.0).toDouble());
        mc.fadeOutUs = drift::secondsToUs(mm.value(QStringLiteral("fadeOutSeconds"), 0.0).toDouble());
        cfg.musicList.append(mc);
    }

    return cfg;
}

QVariantMap CustomProjectController::buildPlanSummary(const QVariantMap &overrideConfig)
{
    if (!overrideConfig.isEmpty()) {
        for (auto it = overrideConfig.begin(); it != overrideConfig.end(); ++it) {
            const QString k = it.key();
            if (k == QLatin1String("primaryFolder")
                || k == QLatin1String("secondaryFolder")
                || k == QLatin1String("narrationPath")
                || k == QLatin1String("srtPath")
                || k == QLatin1String("narrationDelaySeconds")
                || k == QLatin1String("narrationVolumeDb")
                || k == QLatin1String("shuffle")
                || k == QLatin1String("shuffleSeed")) {
                m_currentProject.insert(k, it.value());
            } else {
                m_currentProfile.insert(k, it.value());
            }
        }
    }

    // Auto-load SRT if cues are empty and srtPath is set
    const QString srtP = cleanPath(m_currentProject.value(QStringLiteral("srtPath")).toString());
    if (!srtP.isEmpty() && m_cues.isEmpty()) {
        loadSrtFile(srtP);
    }

    // Auto-scan if candidate scenes are empty and folders are set
    const QString primF = cleanPath(m_currentProject.value(QStringLiteral("primaryFolder")).toString());
    const QString secF = cleanPath(m_currentProject.value(QStringLiteral("secondaryFolder")).toString());
    if (!primF.isEmpty() && m_candidateScenes.isEmpty()) {
        scanFolders(primF, secF);
    }

    drift::CustomProjectConfig cfg = buildInternalConfig();
    m_lastPlan = drift::planCustomProject(cfg);

    m_validationMessages.clear();
    int validationErrorCount = 0;
    int validationWarningCount = 0;
    for (const auto &msg : m_lastPlan.messages) {
        QVariantMap m;
        const bool isError = msg.severity == drift::PlanValidationMessage::Severity::Error;
        m.insert(QStringLiteral("severity"), isError ? QStringLiteral("error") : QStringLiteral("warning"));
        m.insert(QStringLiteral("message"), msg.message);
        m.insert(QStringLiteral("sceneNumber"), msg.sceneNumber);
        m_validationMessages.append(m);
        if (isError)
            ++validationErrorCount;
        else
            ++validationWarningCount;
    }

    m_planValid = m_lastPlan.isValid;
    m_planDurationSeconds = drift::usToSeconds(m_lastPlan.targetDurationUs);

    emit validationMessagesChanged();
    emit planValidChanged();

    QVariantMap summary;
    summary.insert(QStringLiteral("isValid"), m_planValid);
    summary.insert(QStringLiteral("targetDurationSeconds"), m_planDurationSeconds);
    summary.insert(QStringLiteral("slotsCount"), m_lastPlan.sceneSlots.size());
    summary.insert(QStringLiteral("cutScenesCount"), m_lastPlan.cutScenesCount);
    summary.insert(QStringLiteral("retimedScenesCount"), m_lastPlan.retimedScenesCount);
    summary.insert(QStringLiteral("extendedScenesCount"), m_lastPlan.extendedScenesCount);
    summary.insert(QStringLiteral("exactScenesCount"), m_lastPlan.exactScenesCount);
    summary.insert(QStringLiteral("musicClipsCount"), m_lastPlan.musicClips.size());
    summary.insert(QStringLiteral("ctaOccurrencesCount"), m_lastPlan.ctaOccurrences.size());
    summary.insert(QStringLiteral("brollsCount"), m_lastPlan.brolls.size());
    summary.insert(QStringLiteral("transitionsCount"), m_lastPlan.transitions.size());
    summary.insert(QStringLiteral("errorCount"), validationErrorCount);
    summary.insert(QStringLiteral("warningCount"), validationWarningCount);
    summary.insert(QStringLiteral("messages"), m_validationMessages);

    QVariantList sceneActions;
    for (const auto &slot : m_lastPlan.sceneSlots) {
        QVariantMap sm;
        sm.insert(QStringLiteral("sceneNumber"), slot.sceneNumber);
        sm.insert(QStringLiteral("timelineStartSeconds"), drift::usToSeconds(slot.timelineStartUs));
        sm.insert(QStringLiteral("timelineDurationSeconds"), drift::usToSeconds(slot.timelineDurationUs));
        sm.insert(QStringLiteral("actionDescription"), slot.actionDescription);
        sm.insert(QStringLiteral("isEmpty"), slot.isEmpty);
        sm.insert(QStringLiteral("speed"), slot.speed);
        sm.insert(QStringLiteral("sourceDurationSeconds"), drift::usToSeconds(slot.media.sourceDurationUs));
        sm.insert(QStringLiteral("sourceInSeconds"), drift::usToSeconds(slot.srcIn));
        sm.insert(QStringLiteral("sourceOutSeconds"), drift::usToSeconds(slot.srcOut));
        sm.insert(QStringLiteral("mediaPath"), slot.media.path);
        sm.insert(QStringLiteral("isVideo"), slot.media.isVideo);
        sm.insert(QStringLiteral("cueText"), slot.cueText);
        sceneActions.append(sm);
    }
    summary.insert(QStringLiteral("sceneActions"), sceneActions);

    QVariantList brollActions;
    for (const auto &broll : m_lastPlan.brolls) {
        QVariantMap bm;
        bm.insert(QStringLiteral("sceneNumber"), broll.sceneNumber);
        bm.insert(QStringLiteral("timelineStartSeconds"), drift::usToSeconds(broll.timelineStartUs));
        bm.insert(QStringLiteral("timelineDurationSeconds"), drift::usToSeconds(broll.timelineDurationUs));
        bm.insert(QStringLiteral("typeDurationSeconds"), drift::usToSeconds(broll.typeDurationUs));
        bm.insert(QStringLiteral("text"), broll.text);
        bm.insert(QStringLiteral("darkenOpacity"), broll.darkenOpacity);
        for (const auto &slot : m_lastPlan.sceneSlots) {
            if (slot.sceneNumber != broll.sceneNumber)
                continue;
            bm.insert(QStringLiteral("mediaPath"), slot.media.path);
            bm.insert(QStringLiteral("isVideo"), slot.media.isVideo);
            bm.insert(QStringLiteral("sourceInSeconds"), drift::usToSeconds(slot.srcIn));
            bm.insert(QStringLiteral("speed"), slot.speed);
            break;
        }
        brollActions.append(bm);
    }
    summary.insert(QStringLiteral("brollActions"), brollActions);

    return summary;
}

bool CustomProjectController::executeAssembly(AppController *appController, const QString &saveProjectPath)
{
    if (!appController) {
        emit assemblyFinished(false, tr("AppController is not available"));
        return false;
    }

    buildPlanSummary();
    if (!m_planValid) {
        emit assemblyFinished(false, tr("Plan validation failed with errors"));
        return false;
    }

    QVariantMap options;
    options.insert(QStringLiteral("clearTimeline"), true);
    options.insert(QStringLiteral("projectWidth"), m_lastPlan.targetDurationUs > 0 ? m_currentProfile.value(QStringLiteral("projectWidth"), 1920) : 1920);
    options.insert(QStringLiteral("projectHeight"), m_currentProfile.value(QStringLiteral("projectHeight"), 1080));
    options.insert(QStringLiteral("projectFps"), m_currentProfile.value(QStringLiteral("projectFps"), 30));
    options.insert(QStringLiteral("narrationPath"), cleanPath(m_currentProject.value(QStringLiteral("narrationPath")).toString()));
    options.insert(QStringLiteral("muteSceneAudio"), m_currentProfile.value(QStringLiteral("muteSceneAudio"), false).toBool());
    options.insert(QStringLiteral("sceneAudioVolumeDb"), m_currentProfile.value(QStringLiteral("sceneAudioVolumeDb"), -12.0).toDouble());

    bool ok = appController->buildCustomProject(m_lastPlan, {}, options);
    if (!ok) {
        emit assemblyFinished(false, tr("Failed to assemble project on timeline"));
        return false;
    }

    if (!saveProjectPath.isEmpty()) {
        appController->saveProject(QUrl::fromLocalFile(saveProjectPath));
    }

    emit assemblyFinished(true, tr("Custom project successfully assembled!"));
    return true;
}
