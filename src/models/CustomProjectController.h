#pragma once

#include "AppController.h"
#include "core/CustomProjectPlan.h"
#include "core/SubtitleCue.h"

#include <QFutureWatcher>
#include <QObject>
#include <QSet>
#include <QString>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

#include <atomic>
#include <memory>

class CustomProjectController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool isWindows READ isWindows CONSTANT)
    Q_PROPERTY(QStringList profileList READ profileList NOTIFY profilesChanged)
    Q_PROPERTY(QStringList projectList READ projectList NOTIFY projectsChanged)

    Q_PROPERTY(QVariantMap currentProfile READ currentProfile WRITE setCurrentProfile NOTIFY currentProfileChanged)
    Q_PROPERTY(QVariantMap currentProject READ currentProject WRITE setCurrentProject NOTIFY currentProjectChanged)
    Q_PROPERTY(QVariantList candidateScenes READ candidateScenes NOTIFY candidateScenesChanged)
    Q_PROPERTY(QVariantList cues READ cues NOTIFY cuesChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY isScanningChanged)
    Q_PROPERTY(bool isTranscribing READ isTranscribing NOTIFY isTranscribingChanged)
    Q_PROPERTY(double transcriptionProgress READ transcriptionProgress NOTIFY transcriptionProgressChanged)
    Q_PROPERTY(QString transcriptionStatus READ transcriptionStatus NOTIFY transcriptionStatusChanged)
    Q_PROPERTY(QVariantList validationMessages READ validationMessages NOTIFY validationMessagesChanged)
    Q_PROPERTY(bool planValid READ planValid NOTIFY planValidChanged)
    Q_PROPERTY(double planDurationSeconds READ planDurationSeconds NOTIFY planValidChanged)
    Q_PROPERTY(int totalScenesCount READ totalScenesCount NOTIFY cuesChanged)
    Q_PROPERTY(int filledScenesCount READ filledScenesCount NOTIFY candidateScenesChanged)
    Q_PROPERTY(int gapScenesCount READ gapScenesCount NOTIFY candidateScenesChanged)
    Q_PROPERTY(int conflictScenesCount READ conflictScenesCount NOTIFY candidateScenesChanged)

public:
    explicit CustomProjectController(QObject *parent = nullptr);
    ~CustomProjectController() override = default;

    bool isWindows() const;

    QStringList profileList() const { return m_profileList; }
    QStringList projectList() const { return m_projectList; }

    QVariantMap currentProfile() const { return m_currentProfile; }
    void setCurrentProfile(const QVariantMap &profile);

    QVariantMap currentProject() const { return m_currentProject; }
    void setCurrentProject(const QVariantMap &project);

    QVariantList candidateScenes() const { return m_candidateScenes; }
    QVariantList cues() const { return m_cueList; }

    bool isScanning() const { return m_isScanning; }
    bool isTranscribing() const { return m_isTranscribing; }
    double transcriptionProgress() const { return m_transcriptionProgress; }
    QString transcriptionStatus() const { return m_transcriptionStatus; }

    QVariantList validationMessages() const { return m_validationMessages; }
    bool planValid() const { return m_planValid; }
    double planDurationSeconds() const { return m_planDurationSeconds; }

    int totalScenesCount() const { return m_cues.size(); }
    int filledScenesCount() const;
    int gapScenesCount() const;
    int conflictScenesCount() const;

    // --- Profile & Project CRUD ---
    Q_INVOKABLE void refreshLists();
    Q_INVOKABLE bool saveProfile(const QString &name, const QVariantMap &profile);
    Q_INVOKABLE QVariantMap loadProfile(const QString &name);
    Q_INVOKABLE bool deleteProfile(const QString &name);

    Q_INVOKABLE bool saveProjectConfig(const QString &name, const QVariantMap &config);
    Q_INVOKABLE QVariantMap loadProjectConfig(const QString &name);
    Q_INVOKABLE bool deleteProjectConfig(const QString &name);

    // --- Folder Scanning & Scene Management ---
    Q_INVOKABLE void scanFolders(const QString &primaryFolder, const QString &secondaryFolder = QString());
    Q_INVOKABLE void setSceneOverride(int sceneNumber, const QString &customPath);
    Q_INVOKABLE void clearSceneOverride(int sceneNumber);
    Q_INVOKABLE void setSceneEmpty(int sceneNumber, bool empty);
    Q_INVOKABLE void setSceneLocked(int sceneNumber, bool locked);
    Q_INVOKABLE void resolveAllConflicts();

    // --- SRT & Whisper Transcription ---
    Q_INVOKABLE bool loadSrtFile(const QString &filePath);
    Q_INVOKABLE void transcribeAudio(const QString &audioPath, const QString &language = QString());
    Q_INVOKABLE void cancelTranscription();

    // --- Speech Silence Detection ---
    Q_INVOKABLE void analyzeSilence(const QString &audioPath, double minSilenceSeconds = 2.0);

    // --- Media & Duration Probing ---
    Q_INVOKABLE double probeMediaDurationSeconds(const QString &path) const;
    Q_INVOKABLE QUrl fileUrl(const QString &path) const;
    static QString cleanPath(const QString &raw);

    // --- Planning & Assembly ---
    Q_INVOKABLE QVariantMap buildPlanSummary(const QVariantMap &overrideConfig = {});
    Q_INVOKABLE bool executeAssembly(AppController *appController, const QString &saveProjectPath = QString());

signals:
    void profilesChanged();
    void projectsChanged();
    void currentProfileChanged();
    void currentProjectChanged();
    void candidateScenesChanged();
    void cuesChanged();
    void isScanningChanged();
    void scanFinished(int totalFound, int conflicts);
    void isTranscribingChanged();
    void transcriptionProgressChanged();
    void transcriptionStatusChanged();
    void validationMessagesChanged();
    void planValidChanged();
    void assemblyFinished(bool success, const QString &message);

private:
    void rebuildCandidates();
    drift::CustomProjectConfig buildInternalConfig() const;
    static QString profilesDirectory();
    static QString projectsDirectory();

    QStringList m_profileList;
    QStringList m_projectList;
    QVariantMap m_currentProfile;
    QVariantMap m_currentProject;

    QString m_primaryFolder;
    QString m_secondaryFolder;
    QMap<int, QStringList> m_primaryFound;
    QMap<int, QStringList> m_secondaryFound;
    QMap<int, QString> m_overrides;
    QSet<int> m_emptyScenes;
    QSet<int> m_lockedScenes;

    QList<drift::SubtitleCue> m_cues;
    QVariantList m_cueList;
    QVariantList m_candidateScenes;

    QList<drift::PlanSilenceRange> m_silenceRanges;

    bool m_isScanning = false;
    bool m_isTranscribing = false;
    double m_transcriptionProgress = 0.0;
    QString m_transcriptionStatus;
    std::atomic<bool> m_cancelTranscription{false};

    drift::CustomProjectPlan m_lastPlan;
    QVariantList m_validationMessages;
    bool m_planValid = false;
    double m_planDurationSeconds = 0.0;
};
