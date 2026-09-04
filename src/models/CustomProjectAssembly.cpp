#include "AppController.h"
#include "core/CustomProjectPlan.h"
#include "core/MediaAsset.h"
#include "core/Project.h"
#include "core/Time.h"
#include "core/Track.h"
#include "core/Transition.h"

#include <QFileInfo>
#include <QUuid>

bool AppController::buildCustomProject(const drift::CustomProjectPlan &plan,
                                       const QMap<QString, QString> &pathToAssetId,
                                       const QVariantMap &options)
{
    if (!plan.isValid) {
        setLastMessage(tr("Custom project plan is invalid"), QStringLiteral("error"));
        return false;
    }

    const drift::Project before = m_project;

    const bool clearTimeline = options.value(QStringLiteral("clearTimeline"), true).toBool();
    if (clearTimeline) {
        m_project.tracks().clear();
    }

    if (!plan.projectName.isEmpty()) {
        m_project.setName(plan.projectName);
    }
    const int projW = options.value(QStringLiteral("projectWidth"), 1920).toInt();
    const int projH = options.value(QStringLiteral("projectHeight"), 1080).toInt();
    const int projFps = options.value(QStringLiteral("projectFps"), 30).toInt();
    m_project.setResolution(projW, projH);
    m_project.setFps(projFps);

    // Track hierarchy from top to bottom (compositor evaluates track 0 topmost):
    // 0: B-Roll Text
    // 1: B-Roll Darken
    // 2: CTA Overlay
    // 3: Subtitles (if enabled)
    // 4: Scenes
    // 5: Narration Audio
    // 6: Sound Effects (Whoosh, Bell, Keyboard)
    // 7+: Background Music tracks

    const int brollTextTrackIdx = m_project.tracks().size();
    m_project.tracks().append(drift::Track{.type = drift::TrackType::Text, .name = tr("B-Roll Text")});

    const int brollDarkenTrackIdx = m_project.tracks().size();
    m_project.tracks().append(drift::Track{.type = drift::TrackType::Shape, .name = tr("B-Roll Darken")});

    const int ctaTrackIdx = m_project.tracks().size();
    m_project.tracks().append(drift::Track{.type = drift::TrackType::Video, .name = tr("CTA")});

    int subTrackIdx = -1;
    if (plan.hasVisibleSubtitles) {
        subTrackIdx = m_project.tracks().size();
        m_project.tracks().append(drift::Track{.type = drift::TrackType::Subtitle, .name = tr("Subtitles")});
    }

    const int scenesTrackIdx = m_project.tracks().size();
    m_project.tracks().append(drift::Track{.type = drift::TrackType::Video, .name = tr("Scenes")});

    const int narrTrackIdx = m_project.tracks().size();
    m_project.tracks().append(drift::Track{.type = drift::TrackType::Audio, .name = tr("Narration")});

    const int sfxTrackIdx = m_project.tracks().size();
    m_project.tracks().append(drift::Track{.type = drift::TrackType::Audio, .name = tr("Sound Effects")});

    const int musicTracksNeeded = qMax(1, plan.musicTrackCount);
    QList<int> musicTrackIdxs;
    for (int i = 0; i < musicTracksNeeded; ++i) {
        musicTrackIdxs.append(m_project.tracks().size());
        m_project.tracks().append(drift::Track{.type = drift::TrackType::Audio, .name = tr("Music %1").arg(i + 1)});
    }

    auto resolveAsset = [&](const QString &path, drift::ClipType clipType) -> QString {
        if (path.isEmpty())
            return QString();
        if (pathToAssetId.contains(path))
            return pathToAssetId.value(path);

        for (auto it = m_project.assets().begin(); it != m_project.assets().end(); ++it) {
            if (it.value().path == path)
                return it.key();
        }

        if (m_assetLibrary) {
            const int idx = m_assetLibrary->indexOfPath(path);
            if (idx >= 0)
                return m_assetLibrary->assetIdAt(idx);
            const QStringList imported = m_assetLibrary->importLocalPaths({path});
            if (!imported.isEmpty())
                return imported.first();
        }

        drift::MediaAsset asset;
        asset.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        asset.path = path;
        asset.name = QFileInfo(path).fileName();
        if (clipType == drift::ClipType::Audio)
            asset.kind = drift::MediaKind::Audio;
        else if (clipType == drift::ClipType::Image)
            asset.kind = drift::MediaKind::Image;
        else
            asset.kind = drift::MediaKind::Video;
        return m_project.addAsset(asset);
    };

    // 1. Populate Scenes
    QMap<int, QString> sceneIndexToClipId;
    drift::Track &scenesTrack = m_project.tracks()[scenesTrackIdx];
    const bool muteSceneAudio = options.value(QStringLiteral("muteSceneAudio"), false).toBool();
    const double sceneAudioVolumeDb = options.value(QStringLiteral("sceneAudioVolumeDb"), -12.0).toDouble();
    const double sceneAudioGain = muteSceneAudio ? 0.0 : drift::dbToLinearGain(sceneAudioVolumeDb);

    for (int i = 0; i < plan.sceneSlots.size(); ++i) {
        const drift::PlannedSceneSlot &slot = plan.sceneSlots.at(i);
        if (slot.isEmpty || slot.media.path.isEmpty()) {
            continue; // Gap preserved as empty space
        }

        drift::Clip clip;
        clip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        clip.type = slot.media.isVideo ? drift::ClipType::Video : drift::ClipType::Image;
        clip.path = slot.media.path;
        clip.assetId = resolveAsset(slot.media.path, clip.type);
        clip.name = QFileInfo(slot.media.path).fileName();
        clip.timelineStart = slot.timelineStartUs;
        clip.timelineDuration = slot.timelineDurationUs;
        clip.srcIn = slot.srcIn;
        clip.srcOut = slot.srcOut;
        clip.speed = slot.speed;

        if (slot.media.isVideo) {
            if (muteSceneAudio || slot.suppressAudio) {
                clip.suppressEmbeddedAudio = true;
            } else {
                clip.suppressEmbeddedAudio = false;
                const double gain = (slot.sceneAudioGain > 0.0) ? slot.sceneAudioGain : sceneAudioGain;
                if (!qFuzzyCompare(gain, 1.0)) {
                    clip.volume.setEnabled(true);
                    clip.volume.setKeyframe(0, gain);
                }
            }
        }

        if (slot.hasKenBurns) {
            clip.transformX.setEnabled(true);
            clip.transformX.setKeyframe(0, slot.startX);
            clip.transformX.setKeyframe(slot.timelineDurationUs, slot.endX);

            clip.transformY.setEnabled(true);
            clip.transformY.setKeyframe(0, slot.startY);
            clip.transformY.setKeyframe(slot.timelineDurationUs, slot.endY);

            clip.transformW.setEnabled(true);
            clip.transformW.setKeyframe(0, slot.startW);
            clip.transformW.setKeyframe(slot.timelineDurationUs, slot.endW);

            clip.transformH.setEnabled(true);
            clip.transformH.setKeyframe(0, slot.startH);
            clip.transformH.setKeyframe(slot.timelineDurationUs, slot.endH);
        }

        scenesTrack.clips.append(clip);
        sceneIndexToClipId.insert(i, clip.id);
    }

    // 2. Transitions and Whoosh SFX
    drift::Track &sfxTrack = m_project.tracks()[sfxTrackIdx];
    for (const drift::PlannedTransition &pt : plan.transitions) {
        if (sceneIndexToClipId.contains(pt.fromSceneIndex) && sceneIndexToClipId.contains(pt.toSceneIndex)) {
            const QString fromId = sceneIndexToClipId.value(pt.fromSceneIndex);
            const QString toId = sceneIndexToClipId.value(pt.toSceneIndex);

            drift::Transition tr;
            tr.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            tr.fromClipId = fromId;
            tr.toClipId = toId;
            tr.kindId = pt.kindId.isEmpty() ? QStringLiteral("crossfade") : pt.kindId;
            tr.durationUs = pt.durationUs;
            scenesTrack.transitions.append(tr);
        }

        if (pt.hasWhoosh && !pt.whooshAudioPath.isEmpty() && pt.whooshDurationUs > 0) {
            drift::Clip whooshClip;
            whooshClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            whooshClip.type = drift::ClipType::Audio;
            whooshClip.path = pt.whooshAudioPath;
            whooshClip.assetId = resolveAsset(pt.whooshAudioPath, drift::ClipType::Audio);
            whooshClip.name = QStringLiteral("Whoosh");
            whooshClip.timelineStart = pt.whooshStartUs;
            whooshClip.timelineDuration = pt.whooshDurationUs;
            whooshClip.srcIn = 0;
            whooshClip.srcOut = pt.whooshDurationUs;
            if (!qFuzzyCompare(pt.whooshGain, 1.0)) {
                whooshClip.volume.setEnabled(true);
                whooshClip.volume.setKeyframe(0, pt.whooshGain);
            }
            sfxTrack.clips.append(whooshClip);
        }
    }

    // 3. CTA (Visual + Bell Chime)
    drift::Track &ctaTrack = m_project.tracks()[ctaTrackIdx];
    for (const drift::PlannedCtaOccurrence &cta : plan.ctaOccurrences) {
        if (!cta.visualPath.isEmpty() && cta.visualDurationUs > 0) {
            drift::Clip visualClip;
            visualClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            visualClip.type = drift::isSupportedVideoFile(cta.visualPath) ? drift::ClipType::Video : drift::ClipType::Image;
            visualClip.path = cta.visualPath;
            visualClip.assetId = resolveAsset(cta.visualPath, visualClip.type);
            visualClip.name = QStringLiteral("CTA");
            visualClip.timelineStart = cta.visualStartUs;
            visualClip.timelineDuration = cta.visualDurationUs;
            visualClip.srcIn = 0;
            visualClip.srcOut = cta.visualDurationUs;
            if (!qFuzzyCompare(cta.opacity, 1.0)) {
                visualClip.opacity.setEnabled(true);
                visualClip.opacity.setKeyframe(0, cta.opacity);
            }
            if (cta.w > 0 && cta.h > 0) {
                visualClip.transformX.setEnabled(true); visualClip.transformX.setKeyframe(0, cta.x);
                visualClip.transformY.setEnabled(true); visualClip.transformY.setKeyframe(0, cta.y);
                visualClip.transformW.setEnabled(true); visualClip.transformW.setKeyframe(0, cta.w);
                visualClip.transformH.setEnabled(true); visualClip.transformH.setKeyframe(0, cta.h);
            }
            ctaTrack.clips.append(visualClip);
        }

        if (cta.hasBell && !cta.bellAudioPath.isEmpty() && cta.bellDurationUs > 0) {
            drift::Clip bellClip;
            bellClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            bellClip.type = drift::ClipType::Audio;
            bellClip.path = cta.bellAudioPath;
            bellClip.assetId = resolveAsset(cta.bellAudioPath, drift::ClipType::Audio);
            bellClip.name = QStringLiteral("Bell");
            bellClip.timelineStart = cta.bellStartUs;
            bellClip.timelineDuration = cta.bellDurationUs;
            bellClip.srcIn = 0;
            bellClip.srcOut = cta.bellDurationUs;
            if (!qFuzzyCompare(cta.bellGain, 1.0)) {
                bellClip.volume.setEnabled(true);
                bellClip.volume.setKeyframe(0, cta.bellGain);
            }
            sfxTrack.clips.append(bellClip);
        }
    }

    // 4. B-Roll (Darken Shape, Text Typewriter, Keyboard SFX)
    drift::Track &brollDarkTrack = m_project.tracks()[brollDarkenTrackIdx];
    drift::Track &brollTextTrack = m_project.tracks()[brollTextTrackIdx];
    for (const drift::PlannedBRoll &broll : plan.brolls) {
        if (broll.timelineDurationUs <= 0)
            continue;

        drift::Clip darkClip;
        darkClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        darkClip.name = QStringLiteral("B-Roll Darken");
        darkClip.type = drift::ClipType::Shape;
        darkClip.timelineStart = broll.timelineStartUs;
        darkClip.timelineDuration = broll.timelineDurationUs;
        darkClip.shapeStyle.kind = drift::ShapeKind::Rectangle;
        darkClip.shapeStyle.fillKind = drift::ShapeFillKind::Solid;
        darkClip.shapeStyle.fill = QColor(0, 0, 0);
        darkClip.shapeStyle.strokeWidth = 0.0;
        darkClip.shapeStyle.strokeStyle = drift::ShapeStrokeStyle::None;
        darkClip.opacity.setEnabled(true);
        darkClip.opacity.setKeyframe(0, broll.darkenOpacity);
        darkClip.transformX.setEnabled(true); darkClip.transformX.setKeyframe(0, 0.0);
        darkClip.transformY.setEnabled(true); darkClip.transformY.setKeyframe(0, 0.0);
        darkClip.transformW.setEnabled(true); darkClip.transformW.setKeyframe(0, static_cast<double>(projW));
        darkClip.transformH.setEnabled(true); darkClip.transformH.setKeyframe(0, static_cast<double>(projH));
        brollDarkTrack.clips.append(darkClip);

        drift::Clip textClip;
        textClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        textClip.name = QStringLiteral("B-Roll Text");
        textClip.type = drift::ClipType::Text;
        textClip.timelineStart = broll.timelineStartUs;
        textClip.timelineDuration = broll.timelineDurationUs;
        textClip.textContent = broll.text;
        textClip.textStyle = broll.textStyle;
        textClip.textStyle.animIn.kind = drift::TextAnimKind::Typewriter;
        textClip.textStyle.animIn.unit = drift::TextAnimUnit::Character;
        textClip.textStyle.animIn.durationUs = broll.typeDurationUs;
        textClip.textStyle.animIn.ease = drift::TextEase::Linear;
        textClip.textStyle.animIn.order = drift::TextAnimOrder::Forward;
        brollTextTrack.clips.append(textClip);

        if (broll.hasKeyboardSound && !broll.keyboardAudioPath.isEmpty()) {
            drift::Clip keyClip;
            keyClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            keyClip.type = drift::ClipType::Audio;
            keyClip.path = broll.keyboardAudioPath;
            keyClip.assetId = resolveAsset(broll.keyboardAudioPath, drift::ClipType::Audio);
            keyClip.name = QStringLiteral("Keyboard");
            keyClip.timelineStart = broll.timelineStartUs;
            keyClip.timelineDuration = broll.typeDurationUs;
            keyClip.srcIn = 0;
            keyClip.srcOut = broll.typeDurationUs;
            if (!qFuzzyCompare(broll.keyboardGain, 1.0)) {
                keyClip.volume.setEnabled(true);
                keyClip.volume.setKeyframe(0, broll.keyboardGain);
            }
            if (broll.keyboardFadeUs > 0) {
                keyClip.fadeOutUs = broll.keyboardFadeUs;
            }
            sfxTrack.clips.append(keyClip);
        }
    }

    // 5. Subtitles
    if (plan.hasVisibleSubtitles && subTrackIdx >= 0 && !plan.syncCues.isEmpty()) {
        drift::Track &subTrack = m_project.tracks()[subTrackIdx];
        drift::Clip subClip;
        subClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        subClip.name = QStringLiteral("Subtitles");
        subClip.type = drift::ClipType::Subtitle;
        const drift::TimeUs subStart = plan.syncCues.first().startUs;
        const drift::TimeUs subEnd = plan.syncCues.last().endUs;
        subClip.timelineStart = subStart;
        subClip.timelineDuration = qMax<drift::TimeUs>(drift::kUsPerSecond, subEnd - subStart);
        subClip.textStyle = plan.subtitleStyle;
        for (const auto &cue : plan.syncCues) {
            drift::SubtitleCue localCue = cue;
            localCue.startUs = qMax<drift::TimeUs>(0, cue.startUs - subStart);
            localCue.endUs = qMax<drift::TimeUs>(localCue.startUs, cue.endUs - subStart);
            subClip.subtitleCues.append(localCue);
        }
        subTrack.clips.append(subClip);
    }

    // 6. Narration Audio
    const QString narrPath = options.value(QStringLiteral("narrationPath")).toString();
    if (!narrPath.isEmpty() && narrTrackIdx >= 0) {
        drift::Track &narrTrack = m_project.tracks()[narrTrackIdx];
        drift::Clip narrClip;
        narrClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
        narrClip.type = drift::ClipType::Audio;
        narrClip.path = narrPath;
        narrClip.assetId = resolveAsset(narrPath, drift::ClipType::Audio);
        narrClip.name = QFileInfo(narrPath).fileName();
        narrClip.timelineStart = plan.narrationDelayUs;
        narrClip.timelineDuration = plan.targetDurationUs;
        narrClip.srcIn = 0;
        narrClip.srcOut = plan.targetDurationUs;
        if (!qFuzzyCompare(plan.narrationGain, 1.0)) {
            narrClip.volume.setEnabled(true);
            narrClip.volume.setKeyframe(0, plan.narrationGain);
        }
        narrTrack.clips.append(narrClip);
    }

    // 7. Background Music
    for (const drift::PlannedMusicClip &music : plan.musicClips) {
        if (music.path.isEmpty() || music.timelineDurationUs <= 0)
            continue;

        int targetTrackIdx = -1;
        if (music.trackIndex >= 0 && music.trackIndex < musicTrackIdxs.size())
            targetTrackIdx = musicTrackIdxs.at(music.trackIndex);
        else if (!musicTrackIdxs.isEmpty())
            targetTrackIdx = musicTrackIdxs.first();

        if (targetTrackIdx < 0 || targetTrackIdx >= m_project.tracks().size())
            continue;

        drift::Track &mTrack = m_project.tracks()[targetTrackIdx];
        const MediaInfo minfo = MediaProbe::probe(music.path);
        const drift::TimeUs fileDur = (minfo.ok && minfo.durationUs > 0) ? minfo.durationUs : music.timelineDurationUs;

        if (music.loop && fileDur > 0 && music.timelineDurationUs > fileDur) {
            drift::TimeUs currStart = music.timelineStartUs;
            const drift::TimeUs totalEnd = music.timelineStartUs + music.timelineDurationUs;
            int loopIndex = 0;
            while (currStart < totalEnd) {
                const drift::TimeUs chunkDur = std::min(fileDur, totalEnd - currStart);
                drift::Clip mClip;
                mClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
                mClip.type = drift::ClipType::Audio;
                mClip.path = music.path;
                mClip.assetId = resolveAsset(music.path, drift::ClipType::Audio);
                mClip.name = QStringLiteral("%1 (Loop %2)").arg(music.label.isEmpty() ? QFileInfo(music.path).fileName() : music.label).arg(loopIndex + 1);
                mClip.timelineStart = currStart;
                mClip.timelineDuration = chunkDur;
                mClip.srcIn = 0;
                mClip.srcOut = chunkDur;
                if (loopIndex == 0) mClip.fadeInUs = music.fadeInUs;
                if (currStart + chunkDur >= totalEnd) mClip.fadeOutUs = music.fadeOutUs;

                if (!music.volumeKeyframes.isEmpty()) {
                    mClip.volume.setEnabled(true);
                    for (auto it = music.volumeKeyframes.begin(); it != music.volumeKeyframes.end(); ++it) {
                        const drift::TimeUs localTime = it.key();
                        if (localTime >= (currStart - music.timelineStartUs) && localTime <= (currStart - music.timelineStartUs + chunkDur)) {
                            mClip.volume.setKeyframe(localTime - (currStart - music.timelineStartUs), it.value());
                        }
                    }
                } else if (!qFuzzyCompare(music.baseGain, 1.0)) {
                    mClip.volume.setEnabled(true);
                    mClip.volume.setKeyframe(0, music.baseGain);
                }
                mTrack.clips.append(mClip);
                currStart += chunkDur;
                loopIndex++;
            }
        } else {
            drift::Clip mClip;
            mClip.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
            mClip.type = drift::ClipType::Audio;
            mClip.path = music.path;
            mClip.assetId = resolveAsset(music.path, drift::ClipType::Audio);
            mClip.name = music.label.isEmpty() ? QFileInfo(music.path).fileName() : music.label;
            mClip.timelineStart = music.timelineStartUs;
            mClip.timelineDuration = music.timelineDurationUs;
            mClip.srcIn = music.srcIn;
            mClip.srcOut = std::min(music.srcOut, (fileDur > 0) ? fileDur : music.srcOut);
            mClip.fadeInUs = music.fadeInUs;
            mClip.fadeOutUs = music.fadeOutUs;

            if (!music.volumeKeyframes.isEmpty()) {
                mClip.volume.setEnabled(true);
                for (auto it = music.volumeKeyframes.begin(); it != music.volumeKeyframes.end(); ++it) {
                    mClip.volume.setKeyframe(it.key(), it.value());
                }
            } else if (!qFuzzyCompare(music.baseGain, 1.0)) {
                mClip.volume.setEnabled(true);
                mClip.volume.setKeyframe(0, music.baseGain);
            }
            mTrack.clips.append(mClip);
        }
    }

    // Single-step undo transaction
    pushProjectEdit(before, tr("Assemble Custom Project"));
    finishEdit(tr("Custom Project assembled"));

    return true;
}
