#pragma once

#include "Clip.h"
#include "SubtitleCue.h"
#include "TextStyle.h"
#include "Time.h"

#include <QColor>
#include <QList>
#include <QMap>
#include <QSet>
#include <QString>
#include <QVector>

#include <cstdint>
#include <vector>

namespace drift {

// --- Enums & Basic Types ---

enum class MediaOrigin {
    PrimaryFolder,
    SecondaryFolder,
    ManualOverride
};

enum class VideoTrimStrategy {
    KeepStart,
    KeepCenter,
    KeepEnd
};

QString videoTrimStrategyToString(VideoTrimStrategy strategy);
VideoTrimStrategy videoTrimStrategyFromString(const QString &str);

enum class BRollSelectionMode {
    Distributed,
    Random,
    Manual
};

QString brollSelectionModeToString(BRollSelectionMode mode);
BRollSelectionMode brollSelectionModeFromString(const QString &str);

enum class CustomTransitionKind {
    None,
    Fixed,
    Random
};

QString customTransitionKindToString(CustomTransitionKind kind);
CustomTransitionKind customTransitionKindFromString(const QString &str);

// Pure silence range (microseconds)
struct PlanSilenceRange {
    TimeUs startUs = 0;
    TimeUs endUs = 0;

    TimeUs durationUs() const { return endUs > startUs ? endUs - startUs : 0; }
};

// Candidate media file resolved from disk or manual override
struct SceneMediaCandidate {
    int sceneNumber = 0;
    QString path;
    bool isVideo = false;
    TimeUs sourceDurationUs = 0;
    TimeUs durationUs = 0;
    int width = 0;
    int height = 0;
    bool hasAudio = false;
    MediaOrigin origin = MediaOrigin::PrimaryFolder;
    bool isConflict = false;
    QStringList conflictPaths; // when multiple candidates exist in same folder
};

// Configuration for a background music segment
struct PlanMusicConfig {
    QString path;
    QString label;
    int startScene = 0; // 0 = start of project or relativeToNarration
    int endScene = 0;   // 0 = end of project or cue count
    bool loop = false;
    TimeUs startUs = 0;
    TimeUs endUs = 0;
    bool relativeToNarration = true;
    double volumeDb = -17.0;
    bool silenceBoost = false;
    double boostTargetDb = -3.0;
    TimeUs minSilenceDurationUs = 2 * kUsPerSecond;
    TimeUs rampDurationUs = 500'000; // 0.5s ramp up/down
    TimeUs fadeInUs = 0;
    TimeUs fadeOutUs = 0;
};

// Configuration for recurring Call-To-Action (CTA)
struct PlanCtaConfig {
    bool enabled = false;
    QString visualPath;
    QString bellAudioPath;
    TimeUs firstAtUs = 8 * 60 * kUsPerSecond; // 8 minutes
    TimeUs intervalUs = 8 * 60 * kUsPerSecond; // 8 minutes
    TimeUs visualDurationUs = 5 * kUsPerSecond;
    double x = 0.0;
    double y = 0.0;
    double width = 0.0;
    double height = 0.0;
    double opacity = 1.0;
    double bellVolumeDb = 0.0;
    TimeUs bellOffsetUs = 0;
};

// Configuration for textual B-roll
struct PlanBRollConfig {
    bool enabled = false;
    int count = 3;
    BRollSelectionMode mode = BRollSelectionMode::Distributed;
    uint32_t seed = 12345;
    QList<int> manualSceneNumbers;
    double darkenIntensity = 0.55; // 55%
    TextStyle textStyle;
    double typeDurationFraction = 0.70; // 70% typing, 30% hold
    QString keyboardAudioPath;
    double keyboardVolumeDb = -10.0;
    TimeUs keyboardFadeUs = 50'000; // 50ms
};

// Configuration for transitions & Whoosh SFX
struct PlanTransitionConfig {
    CustomTransitionKind kind = CustomTransitionKind::None;
    QString fixedKindId = QStringLiteral("crossfade");
    TimeUs durationUs = 500'000; // 0.5s
    QString whooshAudioPath;
    double whooshVolumeDb = -6.0;
    TimeUs whooshOffsetUs = 0; // centered at cut by default
    TimeUs minWhooshIntervalUs = 4 * kUsPerSecond; // minimum interval between whooshes
};

// Configuration for visible subtitles
struct PlanSubtitleConfig {
    bool visible = false;
    TextStyle textStyle;
};

// Ken Burns configuration for image scenes
struct PlanKenBurnsConfig {
    bool enabled = true;
    double intensity = 0.15; // 15% zoom
};

// Master input configuration passed into CustomProjectPlan
struct CustomProjectConfig {
    QString projectName;
    TimeUs audioDurationUs = 0;
    TimeUs narrationDelayUs = 0;
    double narrationVolumeDb = 0.0;
    QList<SubtitleCue> syncCues;
    QList<SceneMediaCandidate> resolvedScenes; // 1 per cue or with gaps
    VideoTrimStrategy trimStrategy = VideoTrimStrategy::KeepStart;
    double minSpeed = 0.65;
    double maxSpeed = 1.25;
    bool muteSceneAudio = false;
    double sceneAudioVolumeDb = -12.0;
    bool shuffle = false;
    uint32_t shuffleSeed = 42;
    QSet<int> lockedScenes;
    QList<PlanMusicConfig> musicList;
    PlanCtaConfig cta;
    PlanBRollConfig broll;
    PlanTransitionConfig transition;
    PlanSubtitleConfig subtitle;
    PlanKenBurnsConfig kenBurns;
    QList<PlanSilenceRange> silenceRanges;
    int projectWidth = 1920;
    int projectHeight = 1080;
    int projectFps = 30;
};

// --- Output Plan Data Structures ---

struct PlanValidationMessage {
    enum class Severity { Warning, Error };
    Severity severity = Severity::Warning;
    QString message;
    int sceneNumber = -1;
};

struct PlannedSceneSlot {
    int sceneNumber = 0;
    TimeUs timelineStartUs = 0;
    TimeUs timelineDurationUs = 0;
    TimeUs timelineEndUs() const { return timelineStartUs + timelineDurationUs; }
    QString cueText;
    bool isEmpty = false;
    SceneMediaCandidate media;

    // Computed fitting parameters
    double speed = 1.0;
    TimeUs srcIn = 0;
    TimeUs srcOut = 0;
    bool suppressAudio = false;
    double sceneAudioGain = 1.0;
    bool hasKenBurns = false;
    // Ken Burns keyframe bounds (local clip time)
    double startX = 0, startY = 0, startW = 0, startH = 0;
    double endX = 0, endY = 0, endW = 0, endH = 0;
    QString actionDescription;
};

struct PlannedMusicClip {
    int trackIndex = 0; // assigned audio track
    QString path;
    QString label;
    TimeUs timelineStartUs = 0;
    TimeUs timelineDurationUs = 0;
    TimeUs srcIn = 0;
    TimeUs srcOut = 0;
    double baseGain = 1.0;
    bool loop = false;
    // Volume keyframes (local time -> linear gain)
    QMap<TimeUs, double> volumeKeyframes;
    TimeUs fadeInUs = 0;
    TimeUs fadeOutUs = 0;
};

struct PlannedCtaOccurrence {
    TimeUs visualStartUs = 0;
    TimeUs visualDurationUs = 0;
    QString visualPath;
    double x = 0, y = 0, w = 0, h = 0, opacity = 1.0;

    bool hasBell = false;
    TimeUs bellStartUs = 0;
    TimeUs bellDurationUs = 0;
    QString bellAudioPath;
    double bellGain = 1.0;
};

struct PlannedBRoll {
    int sceneNumber = 0;
    TimeUs timelineStartUs = 0;
    TimeUs timelineDurationUs = 0;
    QString text;
    TextStyle textStyle;
    double darkenOpacity = 0.55;
    TimeUs typeDurationUs = 0;

    bool hasKeyboardSound = false;
    QString keyboardAudioPath;
    double keyboardGain = 1.0;
    TimeUs keyboardFadeUs = 0;
};

struct PlannedTransition {
    int fromSceneIndex = -1; // index in planned slots
    int toSceneIndex = -1;
    QString kindId;
    TimeUs durationUs = 500'000;
    TimeUs cutTimeUs = 0;

    bool hasWhoosh = false;
    QString whooshAudioPath;
    TimeUs whooshStartUs = 0;
    TimeUs whooshDurationUs = 0;
    double whooshGain = 1.0;
};

// Complete immutable plan ready for timeline assembly
struct CustomProjectPlan {
    QString projectName;
    TimeUs targetDurationUs = 0;
    TimeUs narrationDelayUs = 0;
    double narrationGain = 1.0;
    QList<SubtitleCue> syncCues;

    QList<PlannedSceneSlot> sceneSlots;
    QList<PlannedMusicClip> musicClips;
    int musicTrackCount = 1;
    QList<PlannedCtaOccurrence> ctaOccurrences;
    QList<PlannedBRoll> brolls;
    QList<int> selectedBRollSceneNumbers;
    QList<PlannedTransition> transitions;
    bool hasVisibleSubtitles = false;
    TextStyle subtitleStyle;

    int cutScenesCount = 0;
    int retimedScenesCount = 0;
    int extendedScenesCount = 0;
    int exactScenesCount = 0;

    QList<PlanValidationMessage> messages;
    bool isValid = true;
};

// --- Pure Helper Functions ---

// Extracts initial decimal number: ^(\d+) -> integer, or -1 if not matching
int extractSceneNumber(const QString &filename);

// Checks file extensions against supported types
bool isSupportedImageFile(const QString &path);
bool isSupportedVideoFile(const QString &path);
bool isSupportedMediaFile(const QString &path);

// Decibels <-> linear gain conversion
double dbToLinearGain(double db);
double linearGainToDb(double gain);

// Pure planner entry point
CustomProjectPlan planCustomProject(const CustomProjectConfig &config);

// Helper to select B-Roll scene numbers deterministically
QList<int> selectBRollScenes(const QList<PlannedSceneSlot> &sceneSlots,
                             const QList<PlannedCtaOccurrence> &ctas,
                             const PlanBRollConfig &config);

// Helper to calculate silence boost keyframes for a music clip
QMap<TimeUs, double> calculateMusicBoostKeyframes(
    TimeUs clipStartUs, TimeUs clipDurationUs,
    const QList<PlanSilenceRange> &silences,
    double baseGain, double boostGain,
    TimeUs minSilenceDurationUs, TimeUs rampDurationUs);

} // namespace drift
