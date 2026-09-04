#include "CustomProjectPlan.h"

#include <QFileInfo>
#include <QRegularExpression>
#include <algorithm>
#include <cmath>
#include <random>

namespace drift {

// --- Enums & Conversions ---

QString videoTrimStrategyToString(VideoTrimStrategy strategy)
{
    switch (strategy) {
    case VideoTrimStrategy::KeepCenter:
        return QStringLiteral("center");
    case VideoTrimStrategy::KeepEnd:
        return QStringLiteral("end");
    case VideoTrimStrategy::KeepStart:
    default:
        return QStringLiteral("start");
    }
}

VideoTrimStrategy videoTrimStrategyFromString(const QString &str)
{
    if (str == QLatin1String("center"))
        return VideoTrimStrategy::KeepCenter;
    if (str == QLatin1String("end"))
        return VideoTrimStrategy::KeepEnd;
    return VideoTrimStrategy::KeepStart;
}

QString brollSelectionModeToString(BRollSelectionMode mode)
{
    switch (mode) {
    case BRollSelectionMode::Random:
        return QStringLiteral("random");
    case BRollSelectionMode::Manual:
        return QStringLiteral("manual");
    case BRollSelectionMode::Distributed:
    default:
        return QStringLiteral("distributed");
    }
}

BRollSelectionMode brollSelectionModeFromString(const QString &str)
{
    if (str == QLatin1String("random"))
        return BRollSelectionMode::Random;
    if (str == QLatin1String("manual"))
        return BRollSelectionMode::Manual;
    return BRollSelectionMode::Distributed;
}

QString customTransitionKindToString(CustomTransitionKind kind)
{
    switch (kind) {
    case CustomTransitionKind::Fixed:
        return QStringLiteral("fixed");
    case CustomTransitionKind::Random:
        return QStringLiteral("random");
    case CustomTransitionKind::None:
    default:
        return QStringLiteral("none");
    }
}

CustomTransitionKind customTransitionKindFromString(const QString &str)
{
    if (str == QLatin1String("fixed"))
        return CustomTransitionKind::Fixed;
    if (str == QLatin1String("random"))
        return CustomTransitionKind::Random;
    return CustomTransitionKind::None;
}

// --- Pure Helper Functions ---

int extractSceneNumber(const QString &filename)
{
    static const QRegularExpression regex(QStringLiteral("^(\\d+)"));
    const QRegularExpressionMatch match = regex.match(filename.trimmed());
    if (!match.hasMatch())
        return -1;
    bool ok = false;
    const int number = match.captured(1).toInt(&ok);
    return ok ? number : -1;
}

bool isSupportedImageFile(const QString &path)
{
    const QString ext = QFileInfo(path).suffix().toLower();
    return ext == QLatin1String("png") || ext == QLatin1String("jpg")
        || ext == QLatin1String("jpeg") || ext == QLatin1String("webp")
        || ext == QLatin1String("bmp") || ext == QLatin1String("gif");
}

bool isSupportedVideoFile(const QString &path)
{
    const QString ext = QFileInfo(path).suffix().toLower();
    return ext == QLatin1String("mp4") || ext == QLatin1String("mov")
        || ext == QLatin1String("mkv") || ext == QLatin1String("webm")
        || ext == QLatin1String("avi") || ext == QLatin1String("m4v")
        || ext == QLatin1String("flv");
}

bool isSupportedMediaFile(const QString &path)
{
    return isSupportedImageFile(path) || isSupportedVideoFile(path);
}

double dbToLinearGain(double db)
{
    return std::pow(10.0, db / 20.0);
}

double linearGainToDb(double gain)
{
    return gain > 0.000001 ? 20.0 * std::log10(gain) : -100.0;
}

// --- Ken Burns Geometry Helper ---

static void computeKenBurnsGeometry(int projW, int projH, int imgW, int imgH,
                                    int sceneIndex, double intensity,
                                    double &outStartX, double &outStartY, double &outStartW, double &outStartH,
                                    double &outEndX, double &outEndY, double &outEndW, double &outEndH)
{
    if (imgW <= 0 || imgH <= 0) {
        imgW = projW;
        imgH = projH;
    }

    const double coverScale = std::max(double(projW) / double(imgW), double(projH) / double(imgH));
    const double baseW = imgW * coverScale;
    const double baseH = imgH * coverScale;
    const double baseX = (projW - baseW) / 2.0;
    const double baseY = (projH - baseH) / 2.0;

    const double zoomFactor = 1.0 + std::clamp(intensity, 0.05, 0.35);
    const double zoomedW = baseW * zoomFactor;
    const double zoomedH = baseH * zoomFactor;
    const double zoomedCenterX = (projW - zoomedW) / 2.0;
    const double zoomedCenterY = (projH - zoomedH) / 2.0;

    const int pattern = sceneIndex % 4;
    switch (pattern) {
    case 0:
        // Zoom in centered
        outStartX = baseX; outStartY = baseY; outStartW = baseW; outStartH = baseH;
        outEndX = zoomedCenterX; outEndY = zoomedCenterY; outEndW = zoomedW; outEndH = zoomedH;
        break;
    case 1:
        // Zoom out centered
        outStartX = zoomedCenterX; outStartY = zoomedCenterY; outStartW = zoomedW; outStartH = zoomedH;
        outEndX = baseX; outEndY = baseY; outEndW = baseW; outEndH = baseH;
        break;
    case 2:
        // Zoom in with slight pan left -> right
        outStartX = baseX - (zoomedW - baseW) * 0.25;
        outStartY = baseY;
        outStartW = baseW;
        outStartH = baseH;
        outEndX = zoomedCenterX + (zoomedW - baseW) * 0.25;
        outEndY = zoomedCenterY;
        outEndW = zoomedW;
        outEndH = zoomedH;
        break;
    case 3:
    default:
        // Zoom out with slight pan top -> bottom
        outStartX = zoomedCenterX;
        outStartY = zoomedCenterY - (zoomedH - baseH) * 0.25;
        outStartW = zoomedW;
        outStartH = zoomedH;
        outEndX = baseX;
        outEndY = baseY + (zoomedH - baseH) * 0.25;
        outEndW = baseW;
        outEndH = baseH;
        break;
    }
}

// --- Music Silence Boost Envelope ---

QMap<TimeUs, double> calculateMusicBoostKeyframes(
    TimeUs clipStartUs, TimeUs clipDurationUs,
    const QList<PlanSilenceRange> &silences,
    double baseGain, double boostGain,
    TimeUs minSilenceDurationUs, TimeUs rampDurationUs)
{
    QMap<TimeUs, double> keyframes;
    if (clipDurationUs <= 0)
        return keyframes;

    // Keyframe at start
    keyframes.insert(0, baseGain);
    keyframes.insert(clipDurationUs, baseGain);

    if (silences.isEmpty() || std::abs(baseGain - boostGain) < 0.001)
        return keyframes;

    const TimeUs clipEndUs = clipStartUs + clipDurationUs;

    // Filter and merge eligible silences
    QList<PlanSilenceRange> merged;
    for (const PlanSilenceRange &sr : silences) {
        if (sr.endUs <= clipStartUs || sr.startUs >= clipEndUs)
            continue;
        if (sr.durationUs() < minSilenceDurationUs)
            continue;

        const TimeUs s = std::max(clipStartUs, sr.startUs);
        const TimeUs e = std::min(clipEndUs, sr.endUs);
        if (e - s < minSilenceDurationUs)
            continue;

        if (!merged.isEmpty() && (s - merged.last().endUs) <= (rampDurationUs * 2)) {
            // Merge very close silences to prevent chattering
            merged.last().endUs = e;
        } else {
            merged.append(PlanSilenceRange{s, e});
        }
    }

    for (const PlanSilenceRange &sr : merged) {
        const TimeUs dur = sr.endUs - sr.startUs;
        const TimeUs effectiveRamp = std::min(rampDurationUs, dur / 3);

        const TimeUs relStart = sr.startUs - clipStartUs;
        const TimeUs relRampUpEnd = relStart + effectiveRamp;
        const TimeUs relRampDownStart = (sr.endUs - clipStartUs) - effectiveRamp;
        const TimeUs relEnd = sr.endUs - clipStartUs;

        if (relStart >= 0 && relStart <= clipDurationUs)
            keyframes.insert(relStart, baseGain);
        if (relRampUpEnd >= 0 && relRampUpEnd <= clipDurationUs)
            keyframes.insert(relRampUpEnd, boostGain);
        if (relRampDownStart >= 0 && relRampDownStart <= clipDurationUs)
            keyframes.insert(relRampDownStart, boostGain);
        if (relEnd >= 0 && relEnd <= clipDurationUs)
            keyframes.insert(relEnd, baseGain);
    }

    return keyframes;
}

// --- B-Roll Scene Selection ---

QList<int> selectBRollScenes(const QList<PlannedSceneSlot> &sceneSlots,
                             const QList<PlannedCtaOccurrence> &ctas,
                             const PlanBRollConfig &config)
{
    if (!config.enabled || sceneSlots.isEmpty() || config.count <= 0)
        return {};

    if (config.mode == BRollSelectionMode::Manual) {
        QList<int> result;
        QSet<int> seen;
        for (int num : config.manualSceneNumbers) {
            for (const PlannedSceneSlot &slot : sceneSlots) {
                if (slot.sceneNumber == num && !slot.isEmpty && !slot.cueText.trimmed().isEmpty() && !seen.contains(num)) {
                    seen.insert(num);
                    result.append(num);
                    break;
                }
            }
        }
        return result;
    }

    // Identify candidate slots
    QList<int> candidateIndices;
    const int totalSlots = static_cast<int>(sceneSlots.size());

    for (int i = 0; i < totalSlots; ++i) {
        const PlannedSceneSlot &slot = sceneSlots.at(i);
        if (slot.isEmpty)
            continue;
        if (slot.cueText.trimmed().isEmpty())
            continue;

        // In automatic modes, avoid first and last block if project has more than 3 slots
        if (totalSlots >= 4 && (i == 0 || i == totalSlots - 1))
            continue;

        // Check CTA collisions: avoid slots that intersect with any CTA visual occurrence
        bool ctaCollision = false;
        for (const PlannedCtaOccurrence &cta : ctas) {
            const TimeUs ctaEnd = cta.visualStartUs + cta.visualDurationUs;
            if (slot.timelineStartUs < ctaEnd && slot.timelineEndUs() > cta.visualStartUs) {
                ctaCollision = true;
                break;
            }
        }
        if (ctaCollision)
            continue;

        candidateIndices.append(i);
    }

    if (candidateIndices.isEmpty())
        return {};

    const int desiredCount = std::min(config.count, static_cast<int>(candidateIndices.size()));

    if (config.mode == BRollSelectionMode::Distributed) {
        // Evenly distributed across candidates without consecutive picks
        QList<int> chosen;
        const double step = double(candidateIndices.size()) / double(desiredCount);
        int lastPickedSlotIdx = -999;

        for (int c = 0; c < desiredCount; ++c) {
            int candIdx = std::clamp<int>(static_cast<int>(std::round(c * step + step / 2.0)), 0, static_cast<int>(candidateIndices.size()) - 1);
            int slotIdx = candidateIndices.at(candIdx);

            // Avoid consecutive slot indices
            if (std::abs(slotIdx - lastPickedSlotIdx) <= 1 && candIdx + 1 < candidateIndices.size()) {
                slotIdx = candidateIndices.at(candIdx + 1);
            }

            if (!chosen.contains(sceneSlots.at(slotIdx).sceneNumber)) {
                chosen.append(sceneSlots.at(slotIdx).sceneNumber);
                lastPickedSlotIdx = slotIdx;
            }
        }
        return chosen;
    }

    // Random mode with seeded deterministic engine
    std::mt19937 rng(config.seed);
    std::vector<int> pool(candidateIndices.begin(), candidateIndices.end());
    std::shuffle(pool.begin(), pool.end(), rng);

    QList<int> chosen;
    for (int slotIdx : pool) {
        if (chosen.size() >= desiredCount)
            break;

        // Ensure not consecutive to already chosen slots
        bool isConsecutive = false;
        for (int pickedNum : chosen) {
            // Find slot index for pickedNum
            for (int j = 0; j < totalSlots; ++j) {
                if (sceneSlots.at(j).sceneNumber == pickedNum) {
                    if (std::abs(j - slotIdx) <= 1)
                        isConsecutive = true;
                    break;
                }
            }
            if (isConsecutive)
                break;
        }

        if (!isConsecutive)
            chosen.append(sceneSlots.at(slotIdx).sceneNumber);
    }

    // If spacing restrictions reduced count below desired, fill with remaining pool
    for (int slotIdx : pool) {
        if (chosen.size() >= desiredCount)
            break;
        const int num = sceneSlots.at(slotIdx).sceneNumber;
        if (!chosen.contains(num))
            chosen.append(num);
    }

    std::sort(chosen.begin(), chosen.end());
    return chosen;
}

// --- Main Planner Implementation ---

CustomProjectPlan planCustomProject(const CustomProjectConfig &config)
{
    CustomProjectPlan plan;
    plan.projectName = config.projectName.isEmpty() ? QStringLiteral("Custom Project") : config.projectName;
    plan.narrationDelayUs = config.narrationDelayUs;
    plan.narrationGain = dbToLinearGain(config.narrationVolumeDb);
    plan.syncCues = config.syncCues;
    plan.targetDurationUs = config.narrationDelayUs + config.audioDurationUs;
    plan.hasVisibleSubtitles = config.subtitle.visible;
    plan.subtitleStyle = config.subtitle.textStyle;

    // --- Validation Checks ---
    if (config.audioDurationUs <= 0) {
        plan.messages.append(PlanValidationMessage{
            PlanValidationMessage::Severity::Error,
            QStringLiteral("Main narration audio duration must be greater than zero.")
        });
        plan.isValid = false;
        return plan;
    }

    if (config.syncCues.isEmpty()) {
        plan.messages.append(PlanValidationMessage{
            PlanValidationMessage::Severity::Error,
            QStringLiteral("No SRT/subtitle cues provided for synchronization.")
        });
        plan.isValid = false;
        return plan;
    }

    const int cueCount = config.syncCues.size();

    // Map resolved candidates by scene number
    QMap<int, SceneMediaCandidate> candidateMap;
    for (const SceneMediaCandidate &cand : config.resolvedScenes) {
        candidateMap.insert(cand.sceneNumber, cand);
        if (cand.isConflict) {
            plan.messages.append(PlanValidationMessage{
                PlanValidationMessage::Severity::Warning,
                QStringLiteral("Conflict in scene %1: multiple candidate files found.").arg(cand.sceneNumber),
                cand.sceneNumber
            });
        }
    }

    // --- 1. Compute Scene Slot Timings & Structure ---
    for (int i = 0; i < cueCount; ++i) {
        const int sceneNum = i + 1;
        const SubtitleCue &cue = config.syncCues.at(i);

        PlannedSceneSlot slot;
        slot.sceneNumber = sceneNum;
        slot.cueText = cue.text;

        // Timing calculations:
        // Scene 1 starts at 0. Ends at narrationDelayUs + cue 2 start (or targetDuration if 1 cue).
        // Scene i > 1 starts at narrationDelayUs + cue i start. Ends at narrationDelayUs + cue i+1 start.
        // Last scene ends at targetDurationUs.
        if (i == 0) {
            slot.timelineStartUs = 0;
            if (cueCount > 1)
                slot.timelineDurationUs = config.narrationDelayUs + config.syncCues.at(1).startUs;
            else
                slot.timelineDurationUs = plan.targetDurationUs;
        } else if (i < cueCount - 1) {
            slot.timelineStartUs = config.narrationDelayUs + cue.startUs;
            const TimeUs nextStartUs = config.narrationDelayUs + config.syncCues.at(i + 1).startUs;
            slot.timelineDurationUs = std::max(TimeUs{1}, nextStartUs - slot.timelineStartUs);
        } else {
            // Last cue
            slot.timelineStartUs = config.narrationDelayUs + cue.startUs;
            slot.timelineDurationUs = std::max(TimeUs{1}, plan.targetDurationUs - slot.timelineStartUs);
        }

        // Warnings for duration bounds (4s to 12s)
        const double durSec = usToSeconds(slot.timelineDurationUs);
        if (durSec < 4.0) {
            plan.messages.append(PlanValidationMessage{
                PlanValidationMessage::Severity::Warning,
                QStringLiteral("Scene %1 duration (%2s) is shorter than recommended 4s.").arg(sceneNum).arg(durSec, 0, 'f', 1),
                sceneNum
            });
        } else if (durSec > 12.0) {
            plan.messages.append(PlanValidationMessage{
                PlanValidationMessage::Severity::Warning,
                QStringLiteral("Scene %1 duration (%2s) is longer than recommended 12s.").arg(sceneNum).arg(durSec, 0, 'f', 1),
                sceneNum
            });
        }

        // Assign media
        if (candidateMap.contains(sceneNum) && !candidateMap.value(sceneNum).path.isEmpty()) {
            slot.media = candidateMap.value(sceneNum);
            slot.isEmpty = false;
        } else {
            slot.isEmpty = true;
            plan.messages.append(PlanValidationMessage{
                PlanValidationMessage::Severity::Warning,
                QStringLiteral("Scene %1 has no media assigned; leaving visual gap.").arg(sceneNum),
                sceneNum
            });
        }

        plan.sceneSlots.append(slot);
    }

    // --- 2. Shuffle Handling ---
    if (config.shuffle) {
        QList<int> eligibleSlotIndices;
        QList<SceneMediaCandidate> eligibleCandidates;

        for (int i = 0; i < plan.sceneSlots.size(); ++i) {
            const PlannedSceneSlot &s = plan.sceneSlots.at(i);
            if (!s.isEmpty && !config.lockedScenes.contains(s.sceneNumber)) {
                eligibleSlotIndices.append(i);
                eligibleCandidates.append(s.media);
            }
        }

        if (eligibleCandidates.size() > 1) {
            std::mt19937 rng(config.shuffleSeed);
            std::vector<SceneMediaCandidate> candVec(eligibleCandidates.begin(), eligibleCandidates.end());
            std::shuffle(candVec.begin(), candVec.end(), rng);

            for (int k = 0; k < eligibleSlotIndices.size(); ++k) {
                const int slotIdx = eligibleSlotIndices.at(k);
                plan.sceneSlots[slotIdx].media = candVec.at(k);
            }

            plan.messages.append(PlanValidationMessage{
                PlanValidationMessage::Severity::Warning,
                QStringLiteral("Shuffle is enabled: media order has been randomized.")
            });
        }
    }

    // --- 3. Video / Image Fitting Calculation ---
    for (int i = 0; i < plan.sceneSlots.size(); ++i) {
        PlannedSceneSlot &slot = plan.sceneSlots[i];
        if (slot.isEmpty)
            continue;

        const TimeUs targetUs = slot.timelineDurationUs;

        if (slot.media.isVideo) {
            const TimeUs srcUs = slot.media.sourceDurationUs;
            if (srcUs <= 0) {
                slot.speed = 1.0;
                slot.srcIn = 0;
                slot.srcOut = targetUs;
                continue;
            }

            const double requiredSpeed = double(srcUs) / double(targetUs);

            if (std::abs(srcUs - targetUs) <= 1000) {
                // S == T
                slot.speed = 1.0;
                slot.srcIn = 0;
                slot.srcOut = srcUs;
            } else if (srcUs < targetUs) {
                // S < T: slow down
                slot.speed = requiredSpeed;
                slot.srcIn = 0;
                slot.srcOut = srcUs;
                if (slot.speed < config.minSpeed) {
                    plan.messages.append(PlanValidationMessage{
                        PlanValidationMessage::Severity::Warning,
                        QStringLiteral("Scene %1 video slowed down to %2x (below min %3x).")
                            .arg(slot.sceneNumber).arg(slot.speed, 0, 'f', 2).arg(config.minSpeed, 0, 'f', 2),
                        slot.sceneNumber
                    });
                }
            } else if (requiredSpeed <= config.maxSpeed) {
                // S > T, requiredSpeed <= maxSpeed: speed up
                slot.speed = requiredSpeed;
                slot.srcIn = 0;
                slot.srcOut = srcUs;
            } else {
                // S > T, requiredSpeed > maxSpeed: keep speed 1.0 and trim
                slot.speed = 1.0;
                const TimeUs trimSpanUs = targetUs;
                switch (config.trimStrategy) {
                case VideoTrimStrategy::KeepCenter:
                    slot.srcIn = (srcUs - trimSpanUs) / 2;
                    slot.srcOut = slot.srcIn + trimSpanUs;
                    break;
                case VideoTrimStrategy::KeepEnd:
                    slot.srcIn = srcUs - trimSpanUs;
                    slot.srcOut = srcUs;
                    break;
                case VideoTrimStrategy::KeepStart:
                default:
                    slot.srcIn = 0;
                    slot.srcOut = trimSpanUs;
                    break;
                }
                plan.messages.append(PlanValidationMessage{
                    PlanValidationMessage::Severity::Warning,
                    QStringLiteral("Scene %1 required speed %2x exceeds max %3x; trimmed keeping %4.")
                        .arg(slot.sceneNumber).arg(requiredSpeed, 0, 'f', 2).arg(config.maxSpeed, 0, 'f', 2)
                        .arg(videoTrimStrategyToString(config.trimStrategy)),
                    slot.sceneNumber
                });
            }
        } else {
            // Image: fits slot exactly
            slot.speed = 1.0;
            slot.srcIn = 0;
            slot.srcOut = targetUs;

            if (config.kenBurns.enabled) {
                slot.hasKenBurns = true;
                computeKenBurnsGeometry(config.projectWidth, config.projectHeight,
                                        slot.media.width, slot.media.height,
                                        slot.sceneNumber, config.kenBurns.intensity,
                                        slot.startX, slot.startY, slot.startW, slot.startH,
                                        slot.endX, slot.endY, slot.endW, slot.endH);
            }
        }
    }

    // --- 4. Recurring CTA Planning ---
    if (config.cta.enabled && !config.cta.visualPath.isEmpty() && config.cta.intervalUs > 0) {
        int occurrenceIndex = 0;
        TimeUs ctaStart = config.cta.firstAtUs;

        while (ctaStart < plan.targetDurationUs) {
            PlannedCtaOccurrence cta;
            cta.visualStartUs = ctaStart;
            cta.visualDurationUs = std::min(config.cta.visualDurationUs, plan.targetDurationUs - ctaStart);
            cta.visualPath = config.cta.visualPath;
            cta.x = config.cta.x;
            cta.y = config.cta.y;
            cta.w = config.cta.width;
            cta.h = config.cta.height;
            cta.opacity = config.cta.opacity;

            if (!config.cta.bellAudioPath.isEmpty()) {
                const TimeUs bellStart = ctaStart + config.cta.bellOffsetUs;
                if (bellStart >= 0 && bellStart < plan.targetDurationUs) {
                    cta.hasBell = true;
                    cta.bellStartUs = bellStart;
                    cta.bellAudioPath = config.cta.bellAudioPath;
                    cta.bellGain = dbToLinearGain(config.cta.bellVolumeDb);
                    cta.bellDurationUs = 3 * kUsPerSecond; // standard bell SFX length cap
                }
            }

            plan.ctaOccurrences.append(cta);
            ctaStart += config.cta.intervalUs;
            ++occurrenceIndex;
        }
    }

    // --- 5. Textual B-Roll Planning ---
    if (config.broll.enabled) {
        plan.selectedBRollSceneNumbers = selectBRollScenes(plan.sceneSlots, plan.ctaOccurrences, config.broll);

        for (int num : plan.selectedBRollSceneNumbers) {
            for (const PlannedSceneSlot &slot : plan.sceneSlots) {
                if (slot.sceneNumber == num && !slot.isEmpty) {
                    PlannedBRoll broll;
                    broll.sceneNumber = num;
                    broll.timelineStartUs = slot.timelineStartUs;
                    broll.timelineDurationUs = slot.timelineDurationUs;
                    broll.text = slot.cueText;
                    broll.textStyle = config.broll.textStyle;
                    broll.darkenOpacity = config.broll.darkenIntensity;

                    const double typeFraction = std::clamp(config.broll.typeDurationFraction, 0.3, 0.9);
                    broll.typeDurationUs = static_cast<TimeUs>(llround(double(slot.timelineDurationUs) * typeFraction));

                    // Configure typewriter animation on style
                    broll.textStyle.animIn.kind = TextAnimKind::Typewriter;
                    broll.textStyle.animIn.unit = TextAnimUnit::Character;
                    broll.textStyle.animIn.durationUs = broll.typeDurationUs;

                    if (!config.broll.keyboardAudioPath.isEmpty()) {
                        broll.hasKeyboardSound = true;
                        broll.keyboardAudioPath = config.broll.keyboardAudioPath;
                        broll.keyboardGain = dbToLinearGain(config.broll.keyboardVolumeDb);
                        broll.keyboardFadeUs = config.broll.keyboardFadeUs;
                    }

                    plan.brolls.append(broll);
                    break;
                }
            }
        }
    }

    // --- 6. Transitions & Whoosh Planning ---
    if (config.transition.kind != CustomTransitionKind::None) {
        static const QStringList kRandomTransitions = {
            QStringLiteral("crossfade"),
            QStringLiteral("wipe_left"),
            QStringLiteral("wipe_right"),
            QStringLiteral("zoom_in"),
            QStringLiteral("push_left")
        };

        for (int i = 0; i < plan.sceneSlots.size() - 1; ++i) {
            const PlannedSceneSlot &fromSlot = plan.sceneSlots.at(i);
            const PlannedSceneSlot &toSlot = plan.sceneSlots.at(i + 1);

            // No transitions across empty gaps
            if (fromSlot.isEmpty || toSlot.isEmpty)
                continue;

            PlannedTransition t;
            t.fromSceneIndex = i;
            t.toSceneIndex = i + 1;
            t.cutTimeUs = fromSlot.timelineEndUs();

            if (config.transition.kind == CustomTransitionKind::Fixed) {
                t.kindId = config.transition.fixedKindId.isEmpty() ? QStringLiteral("crossfade") : config.transition.fixedKindId;
            } else {
                const int randIdx = (i * 3 + 1) % kRandomTransitions.size();
                t.kindId = kRandomTransitions.at(randIdx);
            }

            const TimeUs maxAllowedDur = std::min(fromSlot.timelineDurationUs, toSlot.timelineDurationUs) / 2;
            t.durationUs = std::min(config.transition.durationUs, maxAllowedDur);

            if (!config.transition.whooshAudioPath.isEmpty()) {
                t.hasWhoosh = true;
                t.whooshAudioPath = config.transition.whooshAudioPath;
                t.whooshGain = dbToLinearGain(config.transition.whooshVolumeDb);
                t.whooshDurationUs = 1 * kUsPerSecond;
                t.whooshStartUs = std::max(TimeUs{0}, t.cutTimeUs - t.whooshDurationUs / 2 + config.transition.whooshOffsetUs);
            }

            plan.transitions.append(t);
        }
    }

    // --- 7. Background Music Planning & Multi-Track Allocation ---
    if (!config.musicList.isEmpty()) {
        // Track allocation: trackEndTimes keeps the end of the last clip on each music track
        QList<TimeUs> trackEndTimes;

        for (const PlanMusicConfig &mcfg : config.musicList) {
            if (mcfg.path.isEmpty())
                continue;

            TimeUs mStartUs = mcfg.relativeToNarration ? (config.narrationDelayUs + mcfg.startUs) : mcfg.startUs;
            TimeUs mEndUs = mcfg.relativeToNarration ? (config.narrationDelayUs + mcfg.endUs) : mcfg.endUs;

            if (mEndUs <= mStartUs)
                continue;

            mStartUs = std::clamp(mStartUs, TimeUs{0}, plan.targetDurationUs);
            mEndUs = std::clamp(mEndUs, TimeUs{0}, plan.targetDurationUs);

            if (mEndUs <= mStartUs)
                continue;

            // Find an audio track that is free at mStartUs
            int assignedTrack = -1;
            for (int t = 0; t < trackEndTimes.size(); ++t) {
                if (trackEndTimes.at(t) <= mStartUs) {
                    assignedTrack = t;
                    trackEndTimes[t] = mEndUs;
                    break;
                }
            }
            if (assignedTrack < 0) {
                assignedTrack = trackEndTimes.size();
                trackEndTimes.append(mEndUs);
            }

            PlannedMusicClip clip;
            clip.trackIndex = assignedTrack;
            clip.path = mcfg.path;
            clip.label = mcfg.label.isEmpty() ? QStringLiteral("Music") : mcfg.label;
            clip.timelineStartUs = mStartUs;
            clip.timelineDurationUs = mEndUs - mStartUs;
            clip.srcIn = 0;
            clip.srcOut = clip.timelineDurationUs;
            clip.baseGain = dbToLinearGain(mcfg.volumeDb);
            clip.fadeInUs = mcfg.fadeInUs;
            clip.fadeOutUs = mcfg.fadeOutUs;

            // Compute silence boost keyframes
            if (mcfg.silenceBoost) {
                const double boostGain = dbToLinearGain(mcfg.boostTargetDb);
                clip.volumeKeyframes = calculateMusicBoostKeyframes(
                    clip.timelineStartUs, clip.timelineDurationUs,
                    config.silenceRanges, clip.baseGain, boostGain,
                    mcfg.minSilenceDurationUs, mcfg.rampDurationUs);
            }

            plan.musicClips.append(clip);
        }

        plan.musicTrackCount = std::max(1, static_cast<int>(trackEndTimes.size()));
    }

    return plan;
}

} // namespace drift
