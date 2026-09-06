import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtMultimedia
import Drift

// Self-contained preview used by Custom Project automation features. Its clock keeps
// moving for still images and missing audio, so every Play action has visible feedback.
ThemedDialog {
    id: root

    property string previewKind: "cta" // cta | broll | subtitle
    property url mediaUrl: ""
    property bool mediaIsVideo: false
    property real durationSeconds: 5.0
    property real sourceInSeconds: 0.0
    property real playbackRate: 1.0
    property real darkenOpacity: 0.0
    property string overlayText: ""
    property bool typewriter: false
    property real typewriterFraction: 0.72
    property string detailText: ""

    property string soundPath: ""
    property real soundVolumeDb: 0.0
    property real soundOffsetSeconds: 0.0

    property string textFontFamily: Theme.fontFamily
    property int textPixelSize: 52
    property bool textBold: true
    property color textColor: "#ffffff"
    property bool outlineEnabled: true
    property color outlineColor: "#000000"
    property real outlineWidth: 3.0
    property bool boxEnabled: false
    property color boxColor: "#80000000"
    property string animationKind: "fade"
    property real animationDurationSeconds: 0.35

    property bool playing: false
    property real progress: 0.0
    property string previewStatus: qsTr("Pronto para reproduzir")
    property bool soundTriggered: false

    signal playSoundRequested(string path, real volumeDb)
    signal stopSoundRequested()

    title: previewKind === "cta" ? qsTr("Pré-visualização do CTA")
          : (previewKind === "broll" ? qsTr("Pré-visualização do B-Roll textual")
                                      : qsTr("Pré-visualização da legenda"))
    preferredWidth: 1000
    showAccept: false
    showReject: true
    rejectText: qsTr("Fechar")
    acceptOnReturn: false

    readonly property real safeDuration: Math.max(1.0, durationSeconds)
    readonly property real elapsedSeconds: progress * safeDuration
    readonly property real animationFraction: Math.min(1.0,
        elapsedSeconds / Math.max(0.05, animationDurationSeconds))
    readonly property string visibleOverlayText: {
        if (!typewriter || !playing)
            return overlayText
        const ratio = Math.min(1.0, progress / Math.max(0.05, typewriterFraction))
        return overlayText.substring(0, Math.ceil(overlayText.length * ratio))
    }
    readonly property real animatedTextOpacity: {
        if (!playing || animationKind === "none" || animationKind === "typewriter")
            return 1.0
        return animationFraction
    }
    readonly property real animatedTextScale: {
        if (!playing)
            return 1.0
        if (animationKind === "pop" || animationKind === "bounce")
            return 0.72 + 0.28 * Math.min(1.0, animationFraction * 1.25)
        return 1.0
    }
    readonly property real animatedTextOffset: {
        if (!playing)
            return 0.0
        if (animationKind === "slideUp" || animationKind === "rise")
            return 42.0 * (1.0 - animationFraction)
        if (animationKind === "wave")
            return Math.sin(progress * Math.PI * 8.0) * 5.0
        if (animationKind === "bounce")
            return Math.sin(Math.min(1.0, animationFraction) * Math.PI) * -18.0
        return 0.0
    }
    readonly property var outlineOffsets: [
        { dx: -1, dy: -1 }, { dx: 0, dy: -1 }, { dx: 1, dy: -1 },
        { dx: -1, dy: 0 },                         { dx: 1, dy: 0 },
        { dx: -1, dy: 1 },  { dx: 0, dy: 1 },  { dx: 1, dy: 1 }
    ]

    function restartPreview() {
        stopPreview()
        progress = 0
        soundTriggered = false
        previewStatus = qsTr("Carregando prévia...")
        if (mediaIsVideo && mediaUrl.toString().length > 0) {
            previewVideo.stop()
            previewVideo.source = mediaUrl
            previewVideo.playbackRate = Math.max(0.05, playbackRate)
            previewVideo.setPosition(Math.round(sourceInSeconds * 1000))
        } else if (mediaUrl.toString().length > 0) {
            try { previewImage.currentFrame = 0 } catch (e) {}
        }
        playing = true
        previewStatus = qsTr("Reproduzindo")
        if (mediaIsVideo && mediaUrl.toString().length > 0)
            previewVideo.play()
        maybeTriggerSound()
    }

    function stopPreview() {
        playing = false
        previewVideo.pause()
        stopSoundRequested()
        previewStatus = qsTr("Prévia pausada")
    }

    function togglePreview() {
        if (playing) {
            stopPreview()
            return
        }
        if (progress >= 0.999) {
            restartPreview()
            return
        }
        playing = true
        previewStatus = qsTr("Reproduzindo")
        if (mediaIsVideo && mediaUrl.toString().length > 0)
            previewVideo.play()
        maybeTriggerSound()
    }

    function seekTo(ratio) {
        progress = Math.max(0.0, Math.min(1.0, ratio))
        soundTriggered = elapsedSeconds >= soundOffsetSeconds
        if (mediaIsVideo && mediaUrl.toString().length > 0) {
            const sourceSeconds = sourceInSeconds + elapsedSeconds * Math.max(0.05, playbackRate)
            previewVideo.setPosition(Math.round(sourceSeconds * 1000))
        }
    }

    function maybeTriggerSound() {
        if (!playing || soundTriggered || soundPath.length === 0)
            return
        if (elapsedSeconds + 0.02 < Math.max(0.0, soundOffsetSeconds))
            return
        soundTriggered = true
        playSoundRequested(soundPath, soundVolumeDb)
    }

    onOpened: Qt.callLater(restartPreview)
    onClosed: {
        stopPreview()
        progress = 0
    }

    MediaPlayer {
        id: previewVideo
        videoOutput: previewVideoOutput
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput { muted: true }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia
                    || mediaStatus === MediaPlayer.BufferedMedia) {
                const sourceSeconds = root.sourceInSeconds
                        + root.elapsedSeconds * Math.max(0.05, root.playbackRate)
                setPosition(Math.round(sourceSeconds * 1000))
                if (root.playing)
                    play()
            }
        }
        onErrorOccurred: function(error, errorString) {
            if (error !== MediaPlayer.NoError)
                root.previewStatus = qsTr("Falha ao carregar o vídeo: %1").arg(errorString)
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: root.playing
        onTriggered: {
            root.progress = Math.min(1.0, root.progress + interval / (root.safeDuration * 1000.0))
            root.maybeTriggerSound()
            if (root.progress >= 1.0) {
                root.playing = false
                previewVideo.pause()
                root.stopSoundRequested()
                root.previewStatus = qsTr("Prévia concluída — use Repetir para assistir novamente")
            }
        }
    }

    contentItem: ColumnLayout {
        width: parent ? parent.width : 920
        height: Math.min(640, root.availableContentHeight)
        spacing: Theme.spacingMd

        Rectangle {
            id: previewCanvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 390
            color: "#090b10"
            radius: Theme.radiusSm
            border.width: 1
            border.color: Theme.panelBorder
            clip: true

            // Simple studio backdrop makes subtitle previews readable even without media.
            Rectangle {
                anchors.fill: parent
                visible: root.mediaUrl.toString().length === 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#233248" }
                    GradientStop { position: 0.55; color: "#121a27" }
                    GradientStop { position: 1.0; color: "#080a0f" }
                }
            }

            AnimatedImage {
                id: previewImage
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                source: !root.mediaIsVideo ? root.mediaUrl : ""
                fillMode: Image.PreserveAspectFit
                cache: false
                playing: root.playing
                visible: source.toString().length > 0 && status !== Image.Error
                opacity: root.previewKind === "cta" && root.playing
                         ? Math.min(1.0, root.progress * 12.0) : 1.0
                scale: root.previewKind === "cta" && root.playing
                       ? 0.84 + Math.min(0.16, root.progress * 2.0) : 1.0
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                onStatusChanged: {
                    if (status === Image.Error)
                        root.previewStatus = qsTr("Falha ao carregar a imagem ou GIF")
                }
            }

            VideoOutput {
                id: previewVideoOutput
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                visible: root.mediaIsVideo && root.mediaUrl.toString().length > 0
                opacity: root.previewKind === "cta" && root.playing
                         ? Math.min(1.0, root.progress * 12.0) : 1.0
                scale: root.previewKind === "cta" && root.playing
                       ? 0.84 + Math.min(0.16, root.progress * 2.0) : 1.0
            }

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: Math.max(0.0, Math.min(0.95, root.darkenOpacity))
                visible: opacity > 0.001
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.previewKind === "subtitle" ? 58 : parent.height * 0.28
                width: Math.min(parent.width - 80, 780)
                height: previewText.implicitHeight + 20
                radius: 6
                color: root.boxEnabled ? root.boxColor : "transparent"
                visible: root.visibleOverlayText.length > 0
                opacity: root.animatedTextOpacity
                scale: root.animatedTextScale
                transform: Translate { y: root.animatedTextOffset }

                Repeater {
                    model: root.outlineEnabled ? root.outlineOffsets : []
                    delegate: Text {
                        x: previewText.x + modelData.dx * Math.max(0.5, root.outlineWidth)
                        y: previewText.y + modelData.dy * Math.max(0.5, root.outlineWidth)
                        width: previewText.width
                        height: previewText.height
                        text: root.visibleOverlayText
                        font.family: root.textFontFamily
                        font.pixelSize: Math.max(18, Math.min(root.textPixelSize, 76))
                        font.bold: root.textBold
                        color: root.outlineColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    id: previewText
                    anchors.centerIn: parent
                    width: parent.width - 36
                    text: root.visibleOverlayText
                    font.family: root.textFontFamily
                    font.pixelSize: Math.max(18, Math.min(root.textPixelSize, 76))
                    font.bold: root.textBold
                    color: root.textColor
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.WordWrap
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: root.previewKind !== "subtitle"
                         && root.mediaUrl.toString().length === 0

                IconGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    glyph: Theme.icons.warning
                    iconSize: 34
                    iconColor: Theme.warning
                }
                Text {
                    text: qsTr("Nenhuma mídia selecionada para esta prévia")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    color: "#d4d8df"
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 6
                color: Qt.rgba(1, 1, 1, 0.16)
                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    color: Theme.primary
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMd

            ThemedButton {
                Layout.preferredWidth: 132
                text: root.playing ? qsTr("Pausar") : qsTr("Reproduzir")
                glyph: root.playing ? Theme.icons.pause : Theme.icons.play
                variant: "primary"
                onClicked: root.togglePreview()
            }
            ThemedButton {
                Layout.preferredWidth: 112
                text: qsTr("Repetir")
                glyph: Theme.icons.refresh
                onClicked: root.restartPreview()
            }
            ThemedSlider {
                Layout.fillWidth: true
                from: 0.0
                to: 1.0
                value: root.progress
                showValueTooltip: false
                onMoved: root.seekTo(value)
            }
            Text {
                text: Number(root.elapsedSeconds).toFixed(1) + "s / "
                      + Number(root.safeDuration).toFixed(1) + "s"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                color: Theme.panelForeground
                Layout.preferredWidth: 82
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: root.previewStatus
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                color: root.previewStatus.indexOf(qsTr("Falha")) === 0
                       ? Theme.destructive : Theme.mutedForeground
                wrapMode: Text.WordWrap
            }
            Text {
                text: root.detailText
                visible: text.length > 0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
                color: Theme.mutedForeground
            }
        }
    }
}
