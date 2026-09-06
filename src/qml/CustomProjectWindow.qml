import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import Drift 1.0
import "components"

Window {
    id: root

    width: 1200
    height: 820
    minimumWidth: 960
    minimumHeight: 640
    title: qsTr("Projeto Personalizado - Drift") + " • " + Qt.application.version
    color: Theme.appBackground
    onClosing: stopAudioPreview()

    function openSession() {
        if (Qt.platform.os !== "windows")
            return
        CustomProject.refreshLists()
        if (CustomProject.projectList.length > 0 && projectCombo.currentIndex < 0) {
            projectCombo.currentIndex = 0
            const p = CustomProject.loadProjectConfig(CustomProject.projectList[0])
            root.syncFromProject(p)
        }
        if (CustomProject.profileList.length > 0 && profileCombo.currentIndex < 0) {
            profileCombo.currentIndex = 0
            const prof = CustomProject.loadProfile(CustomProject.profileList[0])
            root.syncFromProfile(prof)
        }
        root.show()
        root.raise()
        root.requestActivate()
    }

    // Local working state
    property string activeTab: "scenes"

    // Form data bound to current project & profile
    property string primaryFolder: ""
    property string secondaryFolder: ""
    property string narrationPath: ""
    property string srtPath: ""
    property double narrationDelaySeconds: 0.0
    property double narrationVolumeDb: 0.0

    // Video fitting
    property string videoTrimStrategy: "start"
    property real minSpeed: 0.65
    property real maxSpeed: 1.25
    property bool muteSceneAudio: false
    property real sceneAudioVolumeDb: -12.0
    property bool shuffle: false
    property int shuffleSeed: 42

    // Ken Burns
    property bool kenBurnsEnabled: true
    property real kenBurnsIntensity: 0.15

    // CTA
    property bool ctaEnabled: false
    property string ctaVisualPath: ""
    property string ctaBellAudioPath: ""
    property real ctaFirstAtSeconds: 480.0
    property real ctaIntervalSeconds: 480.0
    property real ctaVisualDurationSeconds: 5.0
    property real ctaOpacity: 1.0
    property real ctaBellVolumeDb: 0.0
    property real ctaBellAudioOffsetSeconds: 0.0

    // B-Roll
    property bool brollEnabled: false
    property int brollCount: 3
    property string brollMode: "distributed"
    property real brollDarkenIntensity: 0.55
    property string brollKeyboardAudioPath: ""
    property real brollKeyboardVolumeDb: -10.0
    property real brollKeyboardFadeSeconds: 0.05

    // Transitions
    property string transitionKind: "none"
    property string transitionFixedKindId: "crossfade"
    property real transitionDurationSeconds: 0.5
    property string transitionWhooshAudioPath: ""
    property real transitionWhooshVolumeDb: -6.0

    // Subtitles
    property bool subtitlesVisible: false
    property string subtitleFontFamily: "Inter"
    property int subtitlePixelSize: 64
    property bool subtitleBold: true
    property string subtitleColor: "#ffffff"
    property bool subtitleOutlineEnabled: true
    property real subtitleOutlineWidth: 3.0
    property string subtitleOutlineColor: "#000000"
    property bool subtitleShadowEnabled: true
    property bool subtitleBoxEnabled: false
    property string subtitleBoxColor: "#80000000"
    property string subtitleAnimIn: "fade"
    property string subtitleAnimOut: "fade"
    property real subtitleAnimDurationSeconds: 0.35

    // Music
    property var musicList: []
    property real uniformMusicVolumeDb: -12.0
    property string audioActionFeedback: ""

    // Latest validation result is shared by Scenes and Review. Keeping it at the window scope
    // also lets "Process and fit" refresh both tabs instead of trying to call a nested function.
    property var planSummary: ({})
    property bool preparationComplete: false
    property bool operationBusy: false
    property bool assemblySucceeded: false
    property string operationStatus: qsTr("Execute as etapas 1–6 para preparar a revisão.")

    readonly property color readableText: Theme.darkMode ? "#f2f2f2" : "#202124"
    readonly property color readableMuted: Theme.darkMode ? "#a6adb7" : "#5f6670"
    readonly property color readableSurface: Theme.darkMode ? "#202226" : "#f4f5f7"

    readonly property var subtitleFontChoices: {
        const preferred = [
            "Inter", "Arial", "Helvetica", "Roboto", "Montserrat", "Poppins",
            "Open Sans", "Bebas Neue", "Anton", "Oswald", "Noto Sans",
            "Segoe UI", "Verdana", "Tahoma", "Trebuchet MS", "Georgia",
            "Times New Roman", "Impact"
        ]
        const installed = Qt.fontFamilies()
        const result = []
        for (let p = 0; p < preferred.length; ++p) {
            for (let i = 0; i < installed.length; ++i) {
                if (installed[i].toLowerCase() === preferred[p].toLowerCase()) {
                    if (result.indexOf(installed[i]) < 0)
                        result.push(installed[i])
                    break
                }
            }
        }
        if (result.indexOf(root.subtitleFontFamily) < 0)
            result.unshift(root.subtitleFontFamily)
        return result
    }

    // Save project destination
    property string saveProjectPath: ""

    // Path sanitization helper for URLs and Windows paths
    function urlToLocalPath(urlOrPath) {
        if (!urlOrPath) return ""
        var str = urlOrPath.toString().trim()
        if (str.indexOf("file:///") === 0) {
            str = str.substring(8)
        } else if (str.indexOf("file://") === 0) {
            str = str.substring(7)
        }
        try {
            str = decodeURIComponent(str)
        } catch(e) {}
        if ((str.startsWith('"') && str.endsWith('"')) || (str.startsWith("'") && str.endsWith("'"))) {
            str = str.substring(1, str.length - 1).trim()
        }
        return str
    }

    function toFileUrl(path) {
        if (!path || path.length === 0) return ""
        var p = urlToLocalPath(path)
        if (typeof CustomProject !== "undefined" && CustomProject.fileUrl) {
            return CustomProject.fileUrl(p)
        }
        if (typeof EditorState !== "undefined" && EditorState.fileUrl) {
            return EditorState.fileUrl(p)
        }
        return "file:///" + p.replace(/\\/g, "/")
    }

    // Audio & Media preview player
    MediaPlayer {
        id: previewAudioPlayer
        audioOutput: AudioOutput {
            id: previewAudioOutput
            volume: 1.0
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) {
                playingAudioSource = ""
                previewAudioPlayer.stop()
                previewAudioPlayer.setPosition(0)
            }
        }
    }
    property string playingAudioSource: ""

    function playAudioPreview(path, volumeDb) {
        var local = urlToLocalPath(path)
        if (!local || local.length === 0) return
        if (playingAudioSource === local && previewAudioPlayer.playbackState === MediaPlayer.PlayingState) {
            previewAudioPlayer.stop()
            playingAudioSource = ""
            return
        }
        previewAudioPlayer.stop()
        playingAudioSource = local
        var gain = 1.0
        if (volumeDb !== undefined && volumeDb !== null) {
            gain = Math.pow(10.0, volumeDb / 20.0)
        }
        previewAudioOutput.volume = Math.max(0.0, gain)
        previewAudioPlayer.source = toFileUrl(local)
        previewAudioPlayer.setPosition(0)
        previewAudioPlayer.play()
    }

    function stopAudioPreview() {
        previewAudioPlayer.stop()
        previewAudioPlayer.setPosition(0)
        playingAudioSource = ""
    }

    function isVideoPath(path) {
        if (!path) return false
        const clean = urlToLocalPath(path).toLowerCase()
        return /\.(mp4|mov|mkv|webm|avi|m4v|wmv)$/.test(clean)
    }

    function sceneActionFor(sceneNumber) {
        const actions = root.planSummary.sceneActions || []
        for (let i = 0; i < actions.length; ++i) {
            if (actions[i].sceneNumber === sceneNumber)
                return actions[i]
        }
        return null
    }

    function runValidation() {
        const result = CustomProject.buildPlanSummary(root.fullConfig())
        root.planSummary = result || ({})
        return root.planSummary
    }

    function executeStepsOneToSix() {
        if (root.operationBusy)
            return
        root.operationBusy = true
        root.preparationComplete = false
        root.assemblySucceeded = false
        root.operationStatus = qsTr("Executando etapas 1–6: SRT, mídias, áudio, CTA, B-Rolls e legendas...")
        Qt.callLater(function() {
            if (!root.srtPath || root.srtPath.length === 0) {
                root.operationStatus = qsTr("Etapa 1 pendente: selecione um arquivo SRT.")
                root.operationBusy = false
                return
            }
            if (!CustomProject.loadSrtFile(root.srtPath)) {
                root.operationStatus = qsTr("Falha na etapa 1: não foi possível ler o SRT.")
                root.operationBusy = false
                return
            }
            if ((!root.primaryFolder || root.primaryFolder.length === 0)
                    && (!root.secondaryFolder || root.secondaryFolder.length === 0)) {
                root.operationStatus = qsTr("Etapa 1 pendente: selecione ao menos uma pasta de mídias.")
                root.operationBusy = false
                return
            }
            CustomProject.scanFolders(root.primaryFolder, root.secondaryFolder)
            CustomProject.resolveAllConflicts()
            const summary = root.runValidation()
            root.preparationComplete = (summary.sceneActions || []).length > 0
            root.operationStatus = summary.isValid
                ? qsTr("Etapas 1–6 executadas. Projeto pronto para validar e visualizar.")
                : qsTr("Etapas 1–6 executadas com %1 erro(s) e %2 aviso(s).")
                    .arg(summary.errorCount || 0).arg(summary.warningCount || 0)
            root.operationBusy = false
            root.activeTab = "review"
            reviewTabItem.resetFlowPreview()
        })
    }

    function startFolderScan() {
        if ((!root.primaryFolder || root.primaryFolder.length === 0)
                && (!root.secondaryFolder || root.secondaryFolder.length === 0)) {
            scanFeedbackText.text = qsTr("Selecione ao menos uma pasta antes de escanear.")
            return
        }
        scanFeedbackText.text = qsTr("Escaneando pastas e subpastas...")
        // Let the status paint before media probing starts on a large folder.
        Qt.callLater(function() {
            CustomProject.scanFolders(root.primaryFolder, root.secondaryFolder)
        })
    }

    function processScenesFromSrt() {
        if (!root.srtPath || root.srtPath.length === 0) {
            scanFeedbackText.text = qsTr("Carregue um arquivo SRT antes de processar as cenas.")
            return
        }
        scanFeedbackText.text = qsTr("Lendo o SRT e calculando cortes e velocidades...")
        Qt.callLater(function() {
            if (!CustomProject.loadSrtFile(root.srtPath)) {
                scanFeedbackText.text = qsTr("Não foi possível ler o SRT selecionado.")
                return
            }
            if ((root.primaryFolder && root.primaryFolder.length > 0)
                    || (root.secondaryFolder && root.secondaryFolder.length > 0))
                CustomProject.scanFolders(root.primaryFolder, root.secondaryFolder)
            CustomProject.resolveAllConflicts()
            const summary = root.runValidation()
            scanFeedbackText.text = summary.isValid
                ? qsTr("Processado: cortes e velocidades calculados para %1 cena(s).").arg(summary.slotsCount || 0)
                : qsTr("Processado com %1 erro(s) e %2 aviso(s). Veja os detalhes na Revisão.")
                    .arg(summary.errorCount || 0).arg(summary.warningCount || 0)
        })
    }

    function syncToProfile() {
        return {
            videoTrimStrategy: root.videoTrimStrategy,
            minSpeed: root.minSpeed,
            maxSpeed: root.maxSpeed,
            muteSceneAudio: root.muteSceneAudio,
            sceneAudioVolumeDb: root.sceneAudioVolumeDb,
            kenBurnsEnabled: root.kenBurnsEnabled,
            kenBurnsIntensity: root.kenBurnsIntensity,
            ctaEnabled: root.ctaEnabled,
            ctaVisualPath: root.ctaVisualPath,
            ctaBellAudioPath: root.ctaBellAudioPath,
            ctaFirstAtSeconds: root.ctaFirstAtSeconds,
            ctaIntervalSeconds: root.ctaIntervalSeconds,
            ctaVisualDurationSeconds: root.ctaVisualDurationSeconds,
            ctaOpacity: root.ctaOpacity,
            ctaBellVolumeDb: root.ctaBellVolumeDb,
            ctaBellAudioOffsetSeconds: root.ctaBellAudioOffsetSeconds,
            brollEnabled: root.brollEnabled,
            brollCount: root.brollCount,
            brollMode: root.brollMode,
            brollDarkenIntensity: root.brollDarkenIntensity,
            brollKeyboardAudioPath: root.brollKeyboardAudioPath,
            brollKeyboardVolumeDb: root.brollKeyboardVolumeDb,
            brollKeyboardFadeSeconds: root.brollKeyboardFadeSeconds,
            transitionKind: root.transitionKind,
            transitionFixedKindId: root.transitionFixedKindId,
            transitionDurationSeconds: root.transitionDurationSeconds,
            transitionWhooshAudioPath: root.transitionWhooshAudioPath,
            transitionWhooshVolumeDb: root.transitionWhooshVolumeDb,
            subtitlesVisible: root.subtitlesVisible,
            subtitleFontFamily: root.subtitleFontFamily,
            subtitlePixelSize: root.subtitlePixelSize,
            subtitleBold: root.subtitleBold,
            subtitleColor: root.subtitleColor,
            subtitleOutlineEnabled: root.subtitleOutlineEnabled,
            subtitleOutlineWidth: root.subtitleOutlineWidth,
            subtitleOutlineColor: root.subtitleOutlineColor,
            subtitleShadowEnabled: root.subtitleShadowEnabled,
            subtitleBoxEnabled: root.subtitleBoxEnabled,
            subtitleBoxColor: root.subtitleBoxColor,
            subtitleAnimIn: root.subtitleAnimIn,
            subtitleAnimOut: root.subtitleAnimOut,
            subtitleAnimDurationSeconds: root.subtitleAnimDurationSeconds,
            musicList: root.musicList,
            projectWidth: 1920,
            projectHeight: 1080,
            projectFps: 30
        }
    }

    function syncFromProfile(p) {
        if (!p) return
        if (p.videoTrimStrategy !== undefined) root.videoTrimStrategy = p.videoTrimStrategy
        if (p.minSpeed !== undefined) root.minSpeed = p.minSpeed
        if (p.maxSpeed !== undefined) root.maxSpeed = p.maxSpeed
        if (p.muteSceneAudio !== undefined) root.muteSceneAudio = p.muteSceneAudio
        if (p.sceneAudioVolumeDb !== undefined) root.sceneAudioVolumeDb = p.sceneAudioVolumeDb
        if (p.kenBurnsEnabled !== undefined) root.kenBurnsEnabled = p.kenBurnsEnabled
        if (p.kenBurnsIntensity !== undefined) root.kenBurnsIntensity = p.kenBurnsIntensity
        if (p.ctaEnabled !== undefined) root.ctaEnabled = p.ctaEnabled
        if (p.ctaVisualPath !== undefined) root.ctaVisualPath = p.ctaVisualPath
        if (p.ctaBellAudioPath !== undefined) root.ctaBellAudioPath = p.ctaBellAudioPath
        if (p.ctaFirstAtSeconds !== undefined) root.ctaFirstAtSeconds = p.ctaFirstAtSeconds
        if (p.ctaIntervalSeconds !== undefined) root.ctaIntervalSeconds = p.ctaIntervalSeconds
        if (p.ctaVisualDurationSeconds !== undefined) root.ctaVisualDurationSeconds = p.ctaVisualDurationSeconds
        if (p.ctaOpacity !== undefined) root.ctaOpacity = p.ctaOpacity
        if (p.ctaBellVolumeDb !== undefined) root.ctaBellVolumeDb = p.ctaBellVolumeDb
        if (p.ctaBellAudioOffsetSeconds !== undefined) root.ctaBellAudioOffsetSeconds = p.ctaBellAudioOffsetSeconds
        if (p.brollEnabled !== undefined) root.brollEnabled = p.brollEnabled
        if (p.brollCount !== undefined) root.brollCount = p.brollCount
        if (p.brollMode !== undefined) root.brollMode = p.brollMode
        if (p.brollDarkenIntensity !== undefined) root.brollDarkenIntensity = p.brollDarkenIntensity
        if (p.brollKeyboardAudioPath !== undefined) root.brollKeyboardAudioPath = p.brollKeyboardAudioPath
        if (p.brollKeyboardVolumeDb !== undefined) root.brollKeyboardVolumeDb = p.brollKeyboardVolumeDb
        if (p.brollKeyboardFadeSeconds !== undefined) root.brollKeyboardFadeSeconds = p.brollKeyboardFadeSeconds
        if (p.transitionKind !== undefined) root.transitionKind = p.transitionKind
        if (p.transitionFixedKindId !== undefined) root.transitionFixedKindId = p.transitionFixedKindId
        if (p.transitionDurationSeconds !== undefined) root.transitionDurationSeconds = p.transitionDurationSeconds
        if (p.transitionWhooshAudioPath !== undefined) root.transitionWhooshAudioPath = p.transitionWhooshAudioPath
        if (p.transitionWhooshVolumeDb !== undefined) root.transitionWhooshVolumeDb = p.transitionWhooshVolumeDb
        if (p.subtitlesVisible !== undefined) root.subtitlesVisible = p.subtitlesVisible
        if (p.subtitleFontFamily !== undefined) root.subtitleFontFamily = p.subtitleFontFamily
        if (p.subtitlePixelSize !== undefined) root.subtitlePixelSize = p.subtitlePixelSize
        if (p.subtitleBold !== undefined) root.subtitleBold = p.subtitleBold
        if (p.subtitleColor !== undefined) root.subtitleColor = p.subtitleColor
        if (p.subtitleOutlineEnabled !== undefined) root.subtitleOutlineEnabled = p.subtitleOutlineEnabled
        if (p.subtitleOutlineWidth !== undefined) root.subtitleOutlineWidth = p.subtitleOutlineWidth
        if (p.subtitleOutlineColor !== undefined) root.subtitleOutlineColor = p.subtitleOutlineColor
        if (p.subtitleShadowEnabled !== undefined) root.subtitleShadowEnabled = p.subtitleShadowEnabled
        if (p.subtitleBoxEnabled !== undefined) root.subtitleBoxEnabled = p.subtitleBoxEnabled
        if (p.subtitleBoxColor !== undefined) root.subtitleBoxColor = p.subtitleBoxColor
        if (p.subtitleAnimIn !== undefined) root.subtitleAnimIn = p.subtitleAnimIn
        if (p.subtitleAnimOut !== undefined) root.subtitleAnimOut = p.subtitleAnimOut
        if (p.subtitleAnimDurationSeconds !== undefined) root.subtitleAnimDurationSeconds = p.subtitleAnimDurationSeconds
        if (p.musicList !== undefined) {
            root.musicList = p.musicList
            if (p.musicList.length > 0 && p.musicList[0].volumeDb !== undefined)
                root.uniformMusicVolumeDb = p.musicList[0].volumeDb
        }
    }

    function syncToProject() {
        return {
            primaryFolder: root.primaryFolder,
            secondaryFolder: root.secondaryFolder,
            narrationPath: root.narrationPath,
            srtPath: root.srtPath,
            narrationDelaySeconds: root.narrationDelaySeconds,
            narrationVolumeDb: root.narrationVolumeDb,
            shuffle: root.shuffle,
            shuffleSeed: root.shuffleSeed
        }
    }

    function fullConfig() {
        var conf = syncToProfile()
        var proj = syncToProject()
        for (var k in proj) {
            conf[k] = proj[k]
        }
        return conf
    }

    function syncFromProject(proj) {
        if (!proj) return
        if (proj.primaryFolder !== undefined) root.primaryFolder = proj.primaryFolder
        if (proj.secondaryFolder !== undefined) root.secondaryFolder = proj.secondaryFolder
        if (proj.narrationPath !== undefined) root.narrationPath = proj.narrationPath
        if (proj.srtPath !== undefined) root.srtPath = proj.srtPath
        if (proj.narrationDelaySeconds !== undefined) root.narrationDelaySeconds = proj.narrationDelaySeconds
        if (proj.narrationVolumeDb !== undefined) root.narrationVolumeDb = proj.narrationVolumeDb
        if (proj.shuffle !== undefined) root.shuffle = proj.shuffle
        if (proj.shuffleSeed !== undefined) root.shuffleSeed = proj.shuffleSeed
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        // Top Navigation & Profiles/Projects Bar
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: topHeaderLayout.implicitHeight + Theme.spacingMd * 2
            color: root.readableSurface
            radius: Theme.radiusMd
            border.color: Theme.panelBorder
            border.width: 1

            ColumnLayout {
                id: topHeaderLayout
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingSm

                // Top line: Title, Subtitle, and prominent "+ Novo Projeto" button
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingMd

                    IconGlyph {
                        glyph: Theme.icons.wand
                        iconSize: Theme.iconSizeLg
                        iconColor: Theme.primary
                    }

                    Column {
                        Text {
                            text: qsTr("Projeto Personalizado")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.DemiBold
                            color: root.readableText
                        }
                        Text {
                            text: qsTr("Montagem de vídeo orientada a SRT no Drift")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: root.readableMuted
                        }
                        Text {
                            text: qsTr("Build %1").arg(Qt.application.version)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.primary
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ThemedButton {
                        text: qsTr("+ Novo Projeto")
                        variant: "primary"
                        glyph: Theme.icons.plus
                        onClicked: newProjectDialog.openDialog()
                    }
                }

                // Bottom line: Project Selector & Profile Selector with full CRUD
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingLg

                    // Project Group
                    Row {
                        spacing: Theme.spacingSm
                        Layout.alignment: Qt.AlignVCenter

                        ThemedLabel {
                            text: qsTr("Projeto:")
                            anchors.verticalCenter: parent.verticalCenter
                            font.weight: Font.DemiBold
                        }

                        ThemedComboBox {
                            id: projectCombo
                            width: 170
                            model: CustomProject.projectList
                            onActivated: (index) => {
                                if (index >= 0 && index < CustomProject.projectList.length) {
                                    const p = CustomProject.loadProjectConfig(CustomProject.projectList[index])
                                    root.syncFromProject(p)
                                }
                            }
                        }

                        ThemedButton {
                            text: qsTr("Salvar")
                            glyph: Theme.icons.save
                            variant: "secondary"
                            tooltip: qsTr("Salvar alterações no projeto atual")
                            onClicked: {
                                const name = projectCombo.currentText.trim()
                                if (name.length > 0) {
                                    CustomProject.saveProjectConfig(name, root.syncToProject())
                                } else {
                                    newProjectDialog.openDialog()
                                }
                            }
                        }

                        ThemedButton {
                            text: qsTr("Excluir")
                            glyph: Theme.icons.trash
                            variant: "destructive"
                            tooltip: qsTr("Excluir projeto selecionado")
                            enabled: CustomProject.projectList.length > 0 && projectCombo.currentIndex >= 0
                            onClicked: {
                                if (projectCombo.currentText.length > 0)
                                    deleteProjectDialog.openWith(projectCombo.currentText)
                            }
                        }
                    }

                    // Vertical Separator
                    Rectangle {
                        width: 1
                        height: 24
                        color: Theme.panelBorder
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Profile Group
                    Row {
                        spacing: Theme.spacingSm
                        Layout.alignment: Qt.AlignVCenter

                        ThemedLabel {
                            text: qsTr("Perfil:")
                            anchors.verticalCenter: parent.verticalCenter
                            font.weight: Font.DemiBold
                        }

                        ThemedComboBox {
                            id: profileCombo
                            width: 170
                            model: CustomProject.profileList
                            onActivated: (index) => {
                                if (index >= 0 && index < CustomProject.profileList.length) {
                                    const p = CustomProject.loadProfile(CustomProject.profileList[index])
                                    root.syncFromProfile(p)
                                }
                            }
                        }

                        ThemedButton {
                            text: qsTr("+ Perfil")
                            glyph: Theme.icons.plus
                            variant: "ghost"
                            tooltip: qsTr("Criar novo perfil de canal")
                            onClicked: newProfileDialog.openDialog()
                        }

                        ThemedButton {
                            text: qsTr("Salvar")
                            glyph: Theme.icons.save
                            variant: "secondary"
                            tooltip: qsTr("Salvar alterações no perfil atual")
                            onClicked: {
                                const name = profileCombo.currentText.trim()
                                if (name.length > 0) {
                                    CustomProject.saveProfile(name, root.syncToProfile())
                                } else {
                                    newProfileDialog.openDialog()
                                }
                            }
                        }

                        ThemedButton {
                            text: qsTr("Excluir")
                            glyph: Theme.icons.trash
                            variant: "destructive"
                            tooltip: qsTr("Excluir perfil selecionado")
                            enabled: CustomProject.profileList.length > 0 && profileCombo.currentIndex >= 0
                            onClicked: {
                                if (profileCombo.currentText.length > 0)
                                    deleteProfileDialog.openWith(profileCombo.currentText)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }

        // Tab Navigation Bar
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            ThemedToggleButton {
                text: qsTr("1. Cenas e Mídias")
                checked: root.activeTab === "scenes"
                onClicked: root.activeTab = "scenes"
            }
            ThemedToggleButton {
                text: qsTr("2. Ajuste e Ken Burns")
                checked: root.activeTab === "fitting"
                onClicked: root.activeTab = "fitting"
            }
            ThemedToggleButton {
                text: qsTr("3. Narração e Músicas")
                checked: root.activeTab === "audio"
                onClicked: root.activeTab = "audio"
            }
            ThemedToggleButton {
                text: qsTr("4. CTA Recorrente")
                checked: root.activeTab === "cta"
                onClicked: root.activeTab = "cta"
            }
            ThemedToggleButton {
                text: qsTr("5. B-Rolls Textuais")
                checked: root.activeTab === "broll"
                onClicked: root.activeTab = "broll"
            }
            ThemedToggleButton {
                text: qsTr("6. Transições e Legendas")
                checked: root.activeTab === "transitions"
                onClicked: root.activeTab = "transitions"
            }
            ThemedToggleButton {
                text: qsTr("7. Revisão e Montagem")
                checked: root.activeTab === "review"
                onClicked: root.activeTab = "review"
            }
        }

        // Tab Content Area
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.readableSurface
            radius: Theme.radiusMd
            border.color: Theme.panelBorder
            border.width: 1
            clip: true

            // TAB 1: SCENES & MEDIA
            Item {
                anchors.fill: parent
                visible: root.activeTab === "scenes"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMd
                    spacing: Theme.spacingMd

                    // Directory Pickers Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            Text {
                                text: qsTr("Pasta Primária de Mídias (Cenas numeradas):")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                color: root.readableMuted
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                ThemedTextField {
                                    Layout.fillWidth: true
                                    text: root.primaryFolder
                                    onTextChanged: root.primaryFolder = text
                                }
                                ThemedButton {
                                    text: qsTr("Selecionar...")
                                    onClicked: {
                                        const url = FileDialogs.openDirectory(qsTr("Pasta Primária"))
                                        if (url && url.toString().length > 0) {
                                            root.primaryFolder = urlToLocalPath(url)
                                            root.startFolderScan()
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            Text {
                                text: qsTr("Pasta Secundária de Mídias (Fallback):")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                color: root.readableMuted
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                ThemedTextField {
                                    Layout.fillWidth: true
                                    text: root.secondaryFolder
                                    onTextChanged: root.secondaryFolder = text
                                }
                                ThemedButton {
                                    text: qsTr("Selecionar...")
                                    onClicked: {
                                        const url = FileDialogs.openDirectory(qsTr("Pasta Secundária"))
                                        if (url && url.toString().length > 0) {
                                            root.secondaryFolder = urlToLocalPath(url)
                                            root.startFolderScan()
                                        }
                                    }
                                }
                            }
                        }

                        ThemedButton {
                            text: CustomProject.isScanning ? qsTr("Escaneando...") : qsTr("Escanear Pastas")
                            variant: "primary"
                            glyph: Theme.icons.refresh
                            Layout.alignment: Qt.AlignBottom
                            enabled: !CustomProject.isScanning
                            tooltip: qsTr("Procura mídias numeradas também dentro das subpastas")
                            onClicked: root.startFolderScan()
                        }

                        ThemedButton {
                            text: qsTr("Processar e Ajustar ao SRT")
                            variant: "secondary"
                            glyph: Theme.icons.wand
                            Layout.alignment: Qt.AlignBottom
                            onClicked: root.processScenesFromSrt()
                        }
                    }

                    // SRT / Whisper Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXs
                            Text {
                                text: qsTr("Arquivo SRT de Legenda / Narração:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                color: root.readableMuted
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                ThemedTextField {
                                    Layout.fillWidth: true
                                    text: root.srtPath
                                    onTextChanged: root.srtPath = text
                                }
                                ThemedButton {
                                    text: qsTr("Carregar SRT...")
                                    onClicked: {
                                        const url = FileDialogs.openFile(qsTr("Abrir SRT"), qsTr("SubRip Subtitles (*.srt);;Todos os Arquivos (*.*)"))
                                        if (url && url.toString().length > 0) {
                                            const p = urlToLocalPath(url)
                                            root.srtPath = p
                                            CustomProject.loadSrtFile(p)
                                        }
                                    }
                                }
                            }
                        }

                        ThemedButton {
                            text: qsTr("Transcrever com Whisper")
                            variant: "secondary"
                            glyph: Theme.icons.wand
                            Layout.alignment: Qt.AlignBottom
                            onClicked: {
                                if (root.narrationPath.length > 0)
                                    CustomProject.transcribeAudio(root.narrationPath)
                            }
                        }
                    }

                    // Summary Chips & Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        Text {
                            text: qsTr("Total de Blocos: %1").arg(CustomProject.totalScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: root.readableText
                        }
                        Text {
                            text: qsTr("Preenchidos: %1").arg(CustomProject.filledScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.constructive
                        }
                        Text {
                            text: qsTr("Gaps / Em Branco: %1").arg(CustomProject.gapScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        Text {
                            text: qsTr("Conflitos: %1").arg(CustomProject.conflictScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: CustomProject.conflictScenesCount > 0 ? Theme.warning : root.readableMuted
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            id: scanFeedbackText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: Theme.primary
                        }
                    }

                    Connections {
                        target: CustomProject
                        function onScanFinished(totalFound, conflicts) {
                            scanFeedbackText.text = qsTr("Varredura concluída: %1 cenas mapeadas (%2 conflitos)").arg(totalFound).arg(conflicts)
                        }
                        function onScanReportReady(totalFound, supportedFiles, ignoredUnnumbered, invalidFolders) {
                            if (invalidFolders > 0 && supportedFiles === 0) {
                                scanFeedbackText.text = qsTr("A pasta selecionada não existe ou não pode ser lida.")
                            } else if (supportedFiles === 0) {
                                scanFeedbackText.text = qsTr("Nenhuma mídia compatível foi encontrada nas pastas selecionadas.")
                            } else if (totalFound === 0) {
                                scanFeedbackText.text = qsTr("%1 mídia(s) encontrada(s), mas nenhuma possui número de cena no nome.").arg(supportedFiles)
                            } else {
                                scanFeedbackText.text = qsTr("Varredura concluída: %1 cena(s) mapeada(s) em %2 mídia(s); %3 sem numeração.")
                                    .arg(totalFound).arg(supportedFiles).arg(ignoredUnnumbered)
                            }
                        }
                    }

                    // Quick Navigation & Scene Search Bar
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ThemedTextField {
                            id: sceneSearchField
                            placeholderText: qsTr("Ir para cena # (ex: 45)...")
                            Layout.preferredWidth: 200
                            onAccepted: jumpToScene()
                        }
                        ThemedButton {
                            text: qsTr("Ir para Cena")
                            variant: "secondary"
                            glyph: Theme.icons.search
                            onClicked: jumpToScene()
                        }

                        function jumpToScene() {
                            const num = parseInt(sceneSearchField.text.trim())
                            if (!isNaN(num) && num > 0) {
                                for (let i = 0; i < CustomProject.candidateScenes.length; ++i) {
                                    if (CustomProject.candidateScenes[i].sceneNumber === num) {
                                        scenesList.positionViewAtIndex(i, ListView.Beginning)
                                        return
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ThemedButton {
                            visible: CustomProject.conflictScenesCount > 0
                            text: qsTr("Ir para Próximo Conflito")
                            variant: "ghost"
                            glyph: Theme.icons.warning
                            onClicked: {
                                for (let i = 0; i < CustomProject.candidateScenes.length; ++i) {
                                    if (CustomProject.candidateScenes[i].isConflict) {
                                        scenesList.positionViewAtIndex(i, ListView.Beginning)
                                        break
                                    }
                                }
                            }
                        }
                    }

                    // Scenes ListView
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.appBackground
                        radius: Theme.radiusSm
                        border.color: Theme.panelBorder
                        border.width: 1

                        ListView {
                            id: scenesList
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSm
                            clip: true
                            model: CustomProject.candidateScenes
                            spacing: 4
                            headerPositioning: ListView.OverlayHeader

                            header: Rectangle {
                                width: scenesList.width - (scenesListScrollBar.visible ? scenesListScrollBar.width + 4 : 0)
                                height: 28
                                z: 2
                                color: root.readableSurface
                                border.color: Theme.panelBorder

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingSm
                                    anchors.rightMargin: Theme.spacingSm
                                    spacing: Theme.spacingMd
                                    Text { text: qsTr("Cena"); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.readableMuted; Layout.preferredWidth: 40 }
                                    Text { text: qsTr("Trecho SRT"); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.readableMuted; Layout.preferredWidth: 160 }
                                    Text { text: qsTr("Mídia"); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.readableMuted; Layout.fillWidth: true }
                                    Text { text: qsTr("Antes"); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.readableMuted; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 58 }
                                    Text { text: qsTr("Depois"); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.readableMuted; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 58 }
                                    Text { text: qsTr("Origem"); font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: root.readableMuted; horizontalAlignment: Text.AlignHCenter; Layout.preferredWidth: 70 }
                                    Item { Layout.preferredWidth: 350 }
                                }
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: scenesListScrollBar
                                active: true
                                policy: ScrollBar.AlwaysOn
                            }

                            delegate: Rectangle {
                                id: sceneRow
                                property var plannedAction: root.sceneActionFor(modelData.sceneNumber)
                                width: scenesList.width - (scenesListScrollBar.visible ? scenesListScrollBar.width + 4 : 0)
                                height: 48
                                radius: Theme.radiusSm
                                color: modelData.isConflict ? Qt.rgba(1, 0.7, 0, 0.15) : (modelData.isEmpty ? Qt.rgba(1, 1, 1, 0.03) : root.readableSurface)
                                border.color: modelData.isConflict ? Theme.warning : Theme.panelBorder
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingSm
                                    spacing: Theme.spacingMd

                                    Text {
                                        text: "#" + modelData.sceneNumber
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Font.Bold
                                        color: root.readableText
                                        Layout.preferredWidth: 40
                                    }

                                    Text {
                                        text: modelData.cueText || qsTr("(Sem texto SRT)")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                        elide: Text.ElideRight
                                        Layout.preferredWidth: 160
                                    }

                                    Text {
                                        text: modelData.isEmpty ? qsTr("[ESPAÇO VAZIO / GAP PRESERVADO]") : (modelData.fileName + (modelData.isVideo ? " (Vídeo)" : " (Imagem)"))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: modelData.isEmpty ? Font.Normal : Font.DemiBold
                                        color: modelData.isEmpty ? root.readableMuted : root.readableText
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: modelData.isVideo && modelData.durationSeconds > 0
                                              ? Number(modelData.durationSeconds).toFixed(1) + "s"
                                              : (modelData.isEmpty ? "--" : qsTr("Imagem"))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                        horizontalAlignment: Text.AlignHCenter
                                        Layout.preferredWidth: 58
                                    }

                                    Text {
                                        text: sceneRow.plannedAction
                                              ? Number(sceneRow.plannedAction.timelineDurationSeconds).toFixed(1) + "s"
                                              : "--"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        font.weight: Font.DemiBold
                                        color: sceneRow.plannedAction ? Theme.constructive : root.readableMuted
                                        horizontalAlignment: Text.AlignHCenter
                                        Layout.preferredWidth: 58
                                    }

                                    // Origin Badge
                                    Rectangle {
                                        height: 22
                                        width: 70
                                        radius: Theme.radiusXs
                                        color: modelData.origin === "primary" ? Qt.rgba(0, 0.6, 1, 0.2) : (modelData.origin === "secondary" ? Qt.rgba(0.6, 0.2, 1, 0.2) : (modelData.origin === "override" ? Qt.rgba(0, 0.8, 0.4, 0.2) : Qt.rgba(1, 1, 1, 0.05)))
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.origin.toUpperCase()
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.Bold
                                            color: root.readableText
                                        }
                                    }

                                    // Conflict Warning
                                    IconGlyph {
                                        visible: modelData.isConflict
                                        glyph: Theme.icons.warning
                                        iconSize: Theme.iconSizeMd
                                        iconColor: Theme.warning
                                    }

                                    // Action buttons
                                    ThemedButton {
                                        visible: !modelData.isEmpty && modelData.path.length > 0
                                        text: playingAudioSource === urlToLocalPath(modelData.path) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar") : qsTr("Preview")
                                        variant: "ghost"
                                        glyph: playingAudioSource === urlToLocalPath(modelData.path) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                                        onClicked: playAudioPreview(modelData.path, root.sceneAudioVolumeDb)
                                    }

                                    ThemedButton {
                                        text: modelData.locked ? qsTr("Travado") : qsTr("Travar")
                                        variant: modelData.locked ? "primary" : "ghost"
                                        onClicked: CustomProject.setSceneLocked(modelData.sceneNumber, !modelData.locked)
                                    }

                                    ThemedButton {
                                        text: modelData.isEmpty ? qsTr("Restaurar") : qsTr("Deixar Vazio")
                                        variant: "ghost"
                                        onClicked: CustomProject.setSceneEmpty(modelData.sceneNumber, !modelData.isEmpty)
                                    }

                                    ThemedButton {
                                        text: qsTr("Substituir...")
                                        variant: "secondary"
                                        onClicked: {
                                            const url = FileDialogs.openFile(
                                                qsTr("Selecionar Mídia para Cena #%1").arg(modelData.sceneNumber),
                                                [qsTr("Arquivos de Vídeo e Imagem (*.mp4 *.mov *.png *.jpg *.jpeg *.webp *.gif *.bmp *.mkv *.webm *.avi)"), qsTr("Todos os Arquivos (*.*)")]
                                            )
                                            if (url && url.toString().length > 0) {
                                                const p = urlToLocalPath(url)
                                                CustomProject.setSceneOverride(modelData.sceneNumber, p)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // TAB 2: FITTING & KEN BURNS
            Item {
                anchors.fill: parent
                visible: root.activeTab === "fitting"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Text {
                        text: qsTr("Estratégia de Enquadramento e Ajuste de Duração de Vídeos:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: root.readableText
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Corte de Vídeos Longos:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedComboBox {
                            width: 200
                            model: [qsTr("Preservar Início (Keep Start)"), qsTr("Preservar Centro (Keep Center)"), qsTr("Preservar Fim (Keep End)")]
                            currentIndex: root.videoTrimStrategy === "center" ? 1 : (root.videoTrimStrategy === "end" ? 2 : 0)
                            onActivated: (idx) => {
                                root.videoTrimStrategy = idx === 1 ? "center" : (idx === 2 ? "end" : "start")
                            }
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Faixa de Ajuste Automático de Velocidade:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 240
                            from: 0.5
                            to: 1.0
                            value: root.minSpeed
                            onValueChanged: root.minSpeed = Math.round(value * 100) / 100
                        }
                        Text {
                            text: "Min: " + Math.round(root.minSpeed * 100) + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                        ThemedSlider {
                            width: 240
                            from: 1.0
                            to: 2.0
                            value: root.maxSpeed
                            onValueChanged: root.maxSpeed = Math.round(value * 100) / 100
                        }
                        Text {
                            text: "Max: " + Math.round(root.maxSpeed * 100) + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        ThemedCheckBox {
                            text: qsTr("Silenciar áudio original dos vídeos das cenas")
                            checked: root.muteSceneAudio
                            onCheckedChanged: root.muteSceneAudio = checked
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        visible: !root.muteSceneAudio
                        Text {
                            text: qsTr("Volume padrão do áudio dos vídeos:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 220
                            from: -40.0
                            to: 15.0
                            value: root.sceneAudioVolumeDb
                            onValueChanged: root.sceneAudioVolumeDb = Math.round(value * 10) / 10
                        }
                        Text {
                            text: (root.sceneAudioVolumeDb > 0 ? "+" : "") + root.sceneAudioVolumeDb + " dB"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                        ThemedButton {
                            text: playingAudioSource === "scene_volume_test" && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar") : qsTr("Ouvir Volume de Teste")
                            variant: "ghost"
                            glyph: playingAudioSource === "scene_volume_test" && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                            enabled: CustomProject.candidateScenes.length > 0
                            onClicked: {
                                if (playingAudioSource === "scene_volume_test" && previewAudioPlayer.playbackState === MediaPlayer.PlayingState) {
                                    stopAudioPreview()
                                    return
                                }
                                var samplePath = ""
                                for (var i = 0; i < CustomProject.candidateScenes.length; ++i) {
                                    if (CustomProject.candidateScenes[i].path && CustomProject.candidateScenes[i].path.length > 0) {
                                        samplePath = CustomProject.candidateScenes[i].path
                                        break
                                    }
                                }
                                if (samplePath.length > 0) {
                                    playingAudioSource = "scene_volume_test"
                                    var gain = Math.pow(10.0, root.sceneAudioVolumeDb / 20.0)
                                    previewAudioOutput.volume = Math.max(0.0, gain)
                                    previewAudioPlayer.source = toFileUrl(samplePath)
                                    previewAudioPlayer.setPosition(0)
                                    previewAudioPlayer.play()
                                }
                            }
                        }
                    }

                    ThemedCheckBox {
                        text: qsTr("Embaralhar cenas destravadas (Shuffle) mantendo cenas travadas no lugar")
                        checked: root.shuffle
                        onCheckedChanged: root.shuffle = checked
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.panelBorder
                    }

                    Text {
                        text: qsTr("Efeito Ken Burns em Imagens Estáticas:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: root.readableText
                    }

                    ThemedCheckBox {
                        text: qsTr("Ativar Ken Burns (Zoom/Pan suave alternado para preencher a tela)")
                        checked: root.kenBurnsEnabled
                        onCheckedChanged: root.kenBurnsEnabled = checked
                    }

                    RowLayout {
                        spacing: Theme.spacingMd
                        visible: root.kenBurnsEnabled
                        Text {
                            text: qsTr("Intensidade do Zoom:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 300
                            from: 0.05
                            to: 0.35
                            value: root.kenBurnsIntensity
                            onValueChanged: root.kenBurnsIntensity = Math.round(value * 100) / 100
                        }
                        Text {
                            text: Math.round(root.kenBurnsIntensity * 100) + "%"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 3: AUDIO & MUSIC
            Item {
                anchors.fill: parent
                visible: root.activeTab === "audio"

                function distributeMusicAcrossScenes() {
                    if (!root.musicList || root.musicList.length === 0) {
                        root.audioActionFeedback = qsTr("Adicione músicas antes de distribuir.")
                        return
                    }
                    const oldY = musicListView.contentY
                    var total = CustomProject.totalScenesCount
                    if (total <= 0) {
                        total = (CustomProject.candidateScenes && CustomProject.candidateScenes.length > 0)
                            ? CustomProject.candidateScenes.length : 100
                    }
                    var count = root.musicList.length
                    var list = []
                    for (var i = 0; i < count; ++i) {
                        const updated = cloneMusicEntry(root.musicList[i])
                        updated.startScene = Math.min(total, Math.floor(i * total / count) + 1)
                        updated.endScene = Math.max(updated.startScene,
                                                    Math.floor((i + 1) * total / count))
                        updated.loop = true
                        list.push(updated)
                    }
                    root.musicList = list
                    root.audioActionFeedback = qsTr("%1 música(s) distribuída(s) pelas cenas 1–%2.")
                        .arg(count).arg(total)
                    restoreMusicScroll(oldY)
                }

                function cloneMusicEntry(source) {
                    const copy = ({})
                    for (const key in source)
                        copy[key] = source[key]
                    return copy
                }

                function restoreMusicScroll(contentY) {
                    Qt.callLater(function() {
                        const maximum = Math.max(musicListView.originY,
                                                 musicListView.contentHeight - musicListView.height)
                        musicListView.contentY = Math.max(musicListView.originY,
                                                          Math.min(contentY, maximum))
                    })
                }

                function updateMusicEntry(entryIndex, field, newValue) {
                    if (entryIndex < 0 || entryIndex >= root.musicList.length)
                        return
                    const oldY = musicListView.contentY
                    const list = root.musicList.slice()
                    const updated = cloneMusicEntry(list[entryIndex])
                    updated[field] = newValue
                    list[entryIndex] = updated
                    root.musicList = list
                    restoreMusicScroll(oldY)
                }

                function applyUniformMusicVolume() {
                    if (!root.musicList || root.musicList.length === 0)
                        return
                    const oldY = musicListView.contentY
                    const rounded = Math.round(root.uniformMusicVolumeDb * 10) / 10
                    const list = []
                    for (let i = 0; i < root.musicList.length; ++i) {
                        const updated = cloneMusicEntry(root.musicList[i])
                        updated.volumeDb = rounded
                        list.push(updated)
                    }
                    root.musicList = list
                    root.audioActionFeedback = qsTr("Volume de %1 dB aplicado às %2 músicas.")
                        .arg(rounded.toFixed(1)).arg(list.length)
                    restoreMusicScroll(oldY)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Text {
                        text: qsTr("Narração Principal:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: root.readableText
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        ThemedTextField {
                            Layout.fillWidth: true
                            text: root.narrationPath
                            placeholderText: qsTr("Caminho do arquivo de áudio da narração (.wav, .mp3)")
                            onTextChanged: root.narrationPath = text
                        }
                        ThemedButton {
                            text: qsTr("Selecionar...")
                            onClicked: {
                                const url = FileDialogs.openFile(qsTr("Selecionar Narração"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.m4a *.flac *.ogg)"))
                                if (url && url.toString().length > 0) {
                                    root.narrationPath = urlToLocalPath(url)
                                    CustomProject.analyzeSilence(root.narrationPath, 2.0)
                                }
                            }
                        }
                        ThemedButton {
                            text: playingAudioSource === urlToLocalPath(root.narrationPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar") : qsTr("Ouvir Narração")
                            variant: "ghost"
                            enabled: root.narrationPath.length > 0
                            glyph: playingAudioSource === urlToLocalPath(root.narrationPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                            onClicked: playAudioPreview(root.narrationPath, root.narrationVolumeDb)
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Volume da narração:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 220
                            from: -40.0
                            to: 15.0
                            value: root.narrationVolumeDb
                            onValueChanged: root.narrationVolumeDb = Math.round(value * 10) / 10
                        }
                        Text {
                            text: (root.narrationVolumeDb > 0 ? "+" : "") + root.narrationVolumeDb + " dB"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }

                        Item { Layout.preferredWidth: Theme.spacingLg }

                        Text {
                            text: qsTr("Atraso inicial:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 200
                            from: 0.0
                            to: 5.0
                            value: root.narrationDelaySeconds
                            onValueChanged: root.narrationDelaySeconds = Math.round(value * 10) / 10
                        }
                        Text {
                            text: root.narrationDelaySeconds + " s"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.panelBorder
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: qsTr("Músicas de Fundo (Background Music - selecione múltiplas faixas):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.DemiBold
                            color: root.readableText
                        }
                        Item { Layout.fillWidth: true }
                        ThemedButton {
                            text: qsTr("Distribuir entre as Cenas")
                            glyph: Theme.icons.columns
                            variant: "secondary"
                            enabled: root.musicList.length > 0
                            onClicked: distributeMusicAcrossScenes()
                        }
                        ThemedButton {
                            text: qsTr("Adicionar Músicas...")
                            glyph: Theme.icons.fileText
                            onClicked: {
                                const urls = FileDialogs.openFiles(qsTr("Adicionar Músicas de Fundo"), [
                                    qsTr("Arquivos de Áudio (*.mp3 *.wav *.aac *.ogg *.flac *.m4a)"),
                                    qsTr("Todos os Arquivos (*.*)")
                                ])
                                if (urls && urls.length > 0) {
                                    const list = root.musicList.slice()
                                    for (var i = 0; i < urls.length; ++i) {
                                        const p = urlToLocalPath(urls[i])
                                        if (!p || p.length === 0) continue
                                        const baseName = p.split(/[\\/]/).pop()
                                        list.push({
                                            path: p,
                                            label: baseName || ("Música " + (list.length + 1)),
                                            volumeDb: root.uniformMusicVolumeDb,
                                            silenceBoost: true,
                                            boostTargetDb: -3.0,
                                            startScene: 0,
                                            endScene: 0,
                                            loop: false,
                                            minSilenceSeconds: 2.0,
                                            rampSeconds: 0.5,
                                            fadeInSeconds: 0.5,
                                            fadeOutSeconds: 0.5
                                        })
                                    }
                                    root.musicList = list
                                    root.audioActionFeedback = qsTr("%1 música(s) adicionada(s).")
                                        .arg(urls.length)
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        Text {
                            text: qsTr("Volume comum para todas:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            Layout.preferredWidth: 220
                            from: -40.0
                            to: 15.0
                            value: root.uniformMusicVolumeDb
                            onValueChanged: root.uniformMusicVolumeDb = Math.round(value * 10) / 10
                        }
                        Text {
                            text: (root.uniformMusicVolumeDb > 0 ? "+" : "") + root.uniformMusicVolumeDb + " dB"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                            Layout.preferredWidth: 62
                        }
                        ThemedButton {
                            text: qsTr("Aplicar a Todas")
                            glyph: Theme.icons.check
                            variant: "secondary"
                            enabled: root.musicList.length > 0
                            onClicked: applyUniformMusicVolume()
                        }
                        Text {
                            text: root.audioActionFeedback
                            visible: text.length > 0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            color: root.readableMuted
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ListView {
                        id: musicListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.musicList
                        spacing: Theme.spacingSm
                        clip: true

                        ScrollBar.vertical: ScrollBar {
                            active: true
                            policy: ScrollBar.AlwaysOn
                        }

                        delegate: Rectangle {
                            width: parent.width
                            height: 84
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            border.width: 1
                            radius: Theme.radiusSm

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingSm
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMd

                                    Text {
                                        text: modelData.label || "Música"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Font.DemiBold
                                        color: root.readableText
                                        Layout.preferredWidth: 120
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.path
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: qsTr("Vol:")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                    }
                                    ThemedSlider {
                                        id: musicVolumeSlider
                                        Layout.preferredWidth: 120
                                        from: -40.0
                                        to: 15.0
                                        value: (modelData.volumeDb !== undefined) ? modelData.volumeDb : -12.0
                                        onValueChanged: {
                                            const rounded = Math.round(value * 10) / 10
                                            if (modelData.volumeDb !== rounded)
                                                updateMusicEntry(index, "volumeDb", rounded)
                                        }
                                    }
                                    Text {
                                        text: (musicVolumeSlider.value > 0 ? "+" : "") + (Math.round(musicVolumeSlider.value * 10) / 10) + " dB"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableText
                                        Layout.preferredWidth: 52
                                    }
                                    ThemedCheckBox {
                                        text: qsTr("Boost")
                                        checked: modelData.silenceBoost !== undefined ? modelData.silenceBoost : true
                                        onCheckedChanged: {
                                            if (modelData.silenceBoost !== checked)
                                                updateMusicEntry(index, "silenceBoost", checked)
                                        }
                                    }
                                    ThemedCheckBox {
                                        text: qsTr("Loop")
                                        checked: modelData.loop !== undefined ? modelData.loop : false
                                        onCheckedChanged: {
                                            if (modelData.loop !== checked)
                                                updateMusicEntry(index, "loop", checked)
                                        }
                                    }
                                    ThemedButton {
                                        text: playingAudioSource === urlToLocalPath(modelData.path) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar") : qsTr("Ouvir")
                                        variant: "ghost"
                                        glyph: playingAudioSource === urlToLocalPath(modelData.path) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                                        onClicked: playAudioPreview(modelData.path, modelData.volumeDb !== undefined ? modelData.volumeDb : -12.0)
                                    }
                                    ThemedButton {
                                        text: qsTr("Remover")
                                        variant: "ghost"
                                        onClicked: {
                                            if (playingAudioSource === urlToLocalPath(modelData.path)) {
                                                stopAudioPreview()
                                            }
                                            const oldY = musicListView.contentY
                                            const list = root.musicList.slice()
                                            list.splice(index, 1)
                                            root.musicList = list
                                            restoreMusicScroll(oldY)
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingMd

                                    Text {
                                        text: qsTr("Início na Cena #:")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                    }
                                    ThemedTextField {
                                        Layout.preferredWidth: 55
                                        text: (modelData.startScene !== undefined && modelData.startScene > 0) ? String(modelData.startScene) : "0"
                                        placeholderText: "0"
                                        onEditingFinished: {
                                            const val = parseInt(text) || 0
                                            updateMusicEntry(index, "startScene", Math.max(0, val))
                                        }
                                    }
                                    Text {
                                        text: "(0 = início)"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: root.readableMuted
                                    }

                                    Item { Layout.preferredWidth: Theme.spacingMd }

                                    Text {
                                        text: qsTr("Fim na Cena #:")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                    }
                                    ThemedTextField {
                                        Layout.preferredWidth: 55
                                        text: (modelData.endScene !== undefined && modelData.endScene > 0) ? String(modelData.endScene) : "0"
                                        placeholderText: "0"
                                        onEditingFinished: {
                                            const val = parseInt(text) || 0
                                            updateMusicEntry(index, "endScene", Math.max(0, val))
                                        }
                                    }
                                    Text {
                                        text: "(0 = fim do vídeo)"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        color: root.readableMuted
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
            }

            // TAB 4: CTA
            Item {
                anchors.fill: parent
                visible: root.activeTab === "cta"

                MediaPlayer {
                    id: ctaPreviewVideoPlayer
                    source: root.isVideoPath(root.ctaVisualPath) ? toFileUrl(root.ctaVisualPath) : ""
                    videoOutput: ctaPreviewVideoOutput
                    loops: MediaPlayer.Infinite
                    audioOutput: AudioOutput { muted: true }
                    onMediaStatusChanged: {
                        if (mediaStatus === MediaPlayer.EndOfMedia && ctaIsPlayingPreview) {
                            ctaPreviewStopTimer.stop()
                            ctaIsPlayingPreview = false
                            stopAudioPreview()
                        }
                    }
                }

                Timer {
                    id: ctaBellOffsetTimer
                    interval: Math.max(10, Math.round(root.ctaBellAudioOffsetSeconds * 1000))
                    repeat: false
                    onTriggered: {
                        if (root.ctaBellAudioPath.length > 0) {
                            playAudioPreview(root.ctaBellAudioPath, root.ctaBellVolumeDb)
                        }
                    }
                }

                Timer {
                    id: ctaPreviewStopTimer
                    interval: Math.max(500, Math.round(root.ctaVisualDurationSeconds * 1000))
                    repeat: false
                    onTriggered: {
                        ctaPreviewImage.playing = false
                        ctaPreviewVideoPlayer.stop()
                        ctaIsPlayingPreview = false
                        ctaPreviewProgress = 0
                        stopAudioPreview()
                    }
                }
                property bool ctaIsPlayingPreview: false
                property real ctaPreviewProgress: 0.0

                Timer {
                    interval: 33
                    repeat: true
                    running: ctaIsPlayingPreview
                    onTriggered: {
                        const durationMs = Math.max(500, root.ctaVisualDurationSeconds * 1000)
                        ctaPreviewProgress = Math.min(1.0, ctaPreviewProgress + interval / durationMs)
                    }
                }

                function toggleCtaPreview() {
                    if (ctaIsPlayingPreview) {
                        ctaBellOffsetTimer.stop()
                        ctaPreviewStopTimer.stop()
                        ctaPreviewImage.playing = false
                        ctaPreviewVideoPlayer.stop()
                        ctaIsPlayingPreview = false
                        ctaPreviewProgress = 0
                        stopAudioPreview()
                        return
                    }
                    stopAudioPreview()
                    ctaIsPlayingPreview = true
                    ctaPreviewProgress = 0
                    if (root.isVideoPath(root.ctaVisualPath)) {
                        ctaPreviewImage.playing = false
                        ctaPreviewVideoPlayer.stop()
                        ctaPreviewVideoPlayer.setPosition(0)
                        ctaPreviewVideoPlayer.play()
                    } else {
                        try {
                            ctaPreviewImage.currentFrame = 0
                        } catch (e) {}
                        ctaPreviewImage.paused = false
                        ctaPreviewImage.playing = true
                    }
                    if (root.ctaBellAudioOffsetSeconds <= 0.05) {
                        if (root.ctaBellAudioPath.length > 0) {
                            playAudioPreview(root.ctaBellAudioPath, root.ctaBellVolumeDb)
                        }
                    } else {
                        ctaBellOffsetTimer.interval = Math.max(10, Math.round(root.ctaBellAudioOffsetSeconds * 1000))
                        ctaBellOffsetTimer.restart()
                    }
                    ctaPreviewStopTimer.interval = Math.max(500, Math.round(root.ctaVisualDurationSeconds * 1000))
                    ctaPreviewStopTimer.restart()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingMd

                    ThemedCheckBox {
                        text: qsTr("Ativar Chamada para Ação Recorrente (CTA - Inscreva-se / Like)")
                        checked: root.ctaEnabled
                        onCheckedChanged: root.ctaEnabled = checked
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        visible: root.ctaEnabled

                        Text {
                            text: qsTr("Arquivo Visual do CTA (GIF animado, vídeo transparente ou imagem):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField {
                                Layout.fillWidth: true
                                text: root.ctaVisualPath
                                placeholderText: qsTr("Selecione um arquivo .gif, .mov, .mp4, .png...")
                                onTextChanged: root.ctaVisualPath = text
                            }
                            ThemedButton {
                                text: qsTr("Selecionar...")
                                onClicked: {
                                    const url = FileDialogs.openFile(qsTr("Selecionar Visual CTA"), qsTr("Arquivos Visuais (*.gif *.mov *.mp4 *.webm *.png *.jpg *.jpeg *.webp);;GIFs Animados (*.gif);;Todos os Arquivos (*.*)"))
                                    if (url && url.toString().length > 0) {
                                        root.ctaVisualPath = urlToLocalPath(url)
                                    }
                                }
                            }
                        }

                        Text {
                            text: qsTr("Efeito Sonoro do CTA (Sino / Chime):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField {
                                Layout.fillWidth: true
                                text: root.ctaBellAudioPath
                                placeholderText: qsTr("Selecione um arquivo de som de sino (.wav, .mp3)...")
                                onTextChanged: root.ctaBellAudioPath = text
                            }
                            ThemedButton {
                                text: qsTr("Selecionar...")
                                onClicked: {
                                    const url = FileDialogs.openFile(qsTr("Selecionar Efeito Sonoro CTA"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.ogg)"))
                                    if (url && url.toString().length > 0) {
                                        root.ctaBellAudioPath = urlToLocalPath(url)
                                    }
                                }
                            }
                            ThemedButton {
                                text: playingAudioSource === urlToLocalPath(root.ctaBellAudioPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar Som") : qsTr("Ouvir Som")
                                variant: "ghost"
                                enabled: root.ctaBellAudioPath.length > 0
                                glyph: playingAudioSource === urlToLocalPath(root.ctaBellAudioPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                                onClicked: playAudioPreview(root.ctaBellAudioPath, root.ctaBellVolumeDb)
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Duração visual do CTA:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 170
                                from: 1.0
                                to: 15.0
                                value: root.ctaVisualDurationSeconds
                                onValueChanged: root.ctaVisualDurationSeconds = Math.round(value * 10) / 10
                            }
                            Text {
                                text: root.ctaVisualDurationSeconds + " s"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }

                            Item { Layout.preferredWidth: Theme.spacingMd }

                            Text {
                                text: qsTr("Momento do som (Offset no GIF):")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 170
                                from: 0.0
                                to: Math.max(1.0, root.ctaVisualDurationSeconds)
                                value: root.ctaBellAudioOffsetSeconds
                                onValueChanged: root.ctaBellAudioOffsetSeconds = Math.round(value * 10) / 10
                            }
                            Text {
                                text: root.ctaBellAudioOffsetSeconds + " s"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Volume do som do CTA:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 170
                                from: -40.0
                                to: 15.0
                                value: root.ctaBellVolumeDb
                                onValueChanged: root.ctaBellVolumeDb = Math.round(value * 10) / 10
                            }
                            Text {
                                text: (root.ctaBellVolumeDb > 0 ? "+" : "") + root.ctaBellVolumeDb + " dB"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }

                            Item { Layout.preferredWidth: Theme.spacingMd }

                            Text {
                                text: qsTr("Primeira exibição:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 160
                                from: 0
                                to: 1200
                                value: root.ctaFirstAtSeconds
                                onValueChanged: root.ctaFirstAtSeconds = value
                            }
                            Text {
                                text: Math.round(root.ctaFirstAtSeconds / 60) + " min (" + Math.round(root.ctaFirstAtSeconds) + "s)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Intervalo de repetição:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 170
                                from: 120
                                to: 1200
                                value: root.ctaIntervalSeconds
                                onValueChanged: root.ctaIntervalSeconds = value
                            }
                            Text {
                                text: Math.round(root.ctaIntervalSeconds / 60) + " min (" + Math.round(root.ctaIntervalSeconds) + "s)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }
                        }

                        // Preview Box
                        Rectangle {
                            Layout.fillWidth: true
                            height: 150
                            color: Theme.appBackground
                            radius: Theme.radiusSm
                            border.color: Theme.panelBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMd
                                spacing: Theme.spacingLg

                                Rectangle {
                                    id: ctaVisualPreviewFrame
                                    width: 180
                                    height: 110
                                    color: Qt.rgba(0, 0, 0, 0.4)
                                    radius: Theme.radiusXs
                                    border.color: Theme.panelBorder
                                    border.width: 1
                                    clip: true
                                    scale: ctaIsPlayingPreview ? 1.0 : 0.94

                                    Behavior on scale {
                                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                    }

                                    AnimatedImage {
                                        id: ctaPreviewImage
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width, implicitWidth > 0 ? implicitWidth : parent.width)
                                        height: Math.min(parent.height, implicitHeight > 0 ? implicitHeight : parent.height)
                                        fillMode: Image.PreserveAspectFit
                                        source: root.isVideoPath(root.ctaVisualPath) ? "" : toFileUrl(root.ctaVisualPath)
                                        playing: false
                                        visible: root.ctaVisualPath.length > 0
                                                 && !root.isVideoPath(root.ctaVisualPath)
                                                 && status !== Image.Error
                                    }

                                    VideoOutput {
                                        id: ctaPreviewVideoOutput
                                        anchors.fill: parent
                                        fillMode: VideoOutput.PreserveAspectFit
                                        visible: root.ctaVisualPath.length > 0
                                                 && root.isVideoPath(root.ctaVisualPath)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: (!root.isVideoPath(root.ctaVisualPath) && ctaPreviewImage.status === Image.Error)
                                              || (root.isVideoPath(root.ctaVisualPath) && ctaPreviewVideoPlayer.error !== MediaPlayer.NoError)
                                              ? qsTr("Erro ao carregar visual")
                                              : (root.ctaVisualPath.length > 0 ? "" : qsTr("Sem imagem/GIF/vídeo"))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                        visible: root.ctaVisualPath.length === 0
                                                 || (!root.isVideoPath(root.ctaVisualPath) && ctaPreviewImage.status === Image.Error)
                                                 || (root.isVideoPath(root.ctaVisualPath) && ctaPreviewVideoPlayer.error !== MediaPlayer.NoError)
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 4
                                        color: Theme.panelBorder

                                        Rectangle {
                                            width: parent.width * ctaPreviewProgress
                                            height: parent.height
                                            color: Theme.primary
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm

                                    Text {
                                        text: qsTr("Preview do CTA Sincronizado")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeMd
                                        font.weight: Font.DemiBold
                                        color: root.readableText
                                    }

                                    Text {
                                        text: qsTr("Testa o visual (%1s) com o som do sino disparado exatamente aos %2s.").arg(root.ctaVisualDurationSeconds).arg(root.ctaBellAudioOffsetSeconds)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: root.readableMuted
                                    }

                                    RowLayout {
                                        spacing: Theme.spacingMd

                                        ThemedButton {
                                            Layout.preferredWidth: 300
                                            text: ctaIsPlayingPreview ? qsTr("Parar Visualização") : qsTr("Testar Preview CTA (Visual + Sino)")
                                            variant: ctaIsPlayingPreview ? "destructive" : "primary"
                                            glyph: ctaIsPlayingPreview ? Theme.icons.pause : Theme.icons.play
                                            enabled: root.ctaVisualPath.length > 0 || root.ctaBellAudioPath.length > 0
                                            onClicked: toggleCtaPreview()
                                        }

                                        Text {
                                            text: ctaIsPlayingPreview
                                                  ? qsTr("Reproduzindo %1%").arg(Math.round(ctaPreviewProgress * 100))
                                                  : qsTr("Pronto para visualizar")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                            color: root.readableMuted
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 5: B-ROLL TEXTUAL
            Item {
                id: brollTabItem
                anchors.fill: parent
                visible: root.activeTab === "broll"

                property int previewIndex: 0
                property real previewProgress: 0.0
                property bool previewPlaying: false
                readonly property var previewItems: root.planSummary.brollActions || []
                readonly property var currentPreview: previewItems.length > 0
                                                      ? previewItems[Math.min(previewIndex, previewItems.length - 1)]
                                                      : null

                function refreshPreview() {
                    root.runValidation()
                    previewIndex = Math.max(0, Math.min(previewIndex, previewItems.length - 1))
                    previewProgress = 0
                    previewPlaying = false
                    loadPreviewMedia()
                }

                function loadPreviewMedia() {
                    brollPreviewPlayer.stop()
                    if (!currentPreview || !currentPreview.isVideo) {
                        brollPreviewPlayer.source = ""
                        return
                    }
                    brollPreviewPlayer.source = toFileUrl(currentPreview.mediaPath)
                    brollPreviewPlayer.playbackRate = Math.max(0.05, currentPreview.speed || 1.0)
                    brollPreviewPlayer.setPosition(Math.round((currentPreview.sourceInSeconds || 0) * 1000))
                }

                function togglePreview() {
                    if (!currentPreview)
                        return
                    previewPlaying = !previewPlaying
                    if (previewPlaying) {
                        previewProgress = 0
                        loadPreviewMedia()
                        if (currentPreview.isVideo)
                            brollPreviewPlayer.play()
                        if (root.brollKeyboardAudioPath.length > 0)
                            playAudioPreview(root.brollKeyboardAudioPath, root.brollKeyboardVolumeDb)
                    } else {
                        brollPreviewPlayer.pause()
                        stopAudioPreview()
                    }
                }

                function visiblePreviewText() {
                    if (!currentPreview)
                        return ""
                    const value = currentPreview.text || ""
                    if (!previewPlaying)
                        return value
                    const duration = Math.max(0.01, currentPreview.timelineDurationSeconds || 1.0)
                    const typingFraction = Math.max(0.01, (currentPreview.typeDurationSeconds || duration * 0.7) / duration)
                    const ratio = Math.min(1.0, previewProgress / typingFraction)
                    return value.substring(0, Math.ceil(value.length * ratio))
                }

                MediaPlayer {
                    id: brollPreviewPlayer
                    videoOutput: brollPreviewVideoOutput
                    audioOutput: AudioOutput { muted: true }
                    onMediaStatusChanged: {
                        if ((mediaStatus === MediaPlayer.LoadedMedia
                                || mediaStatus === MediaPlayer.BufferedMedia)
                                && brollTabItem.currentPreview) {
                            setPosition(Math.round((brollTabItem.currentPreview.sourceInSeconds || 0) * 1000))
                            if (brollTabItem.previewPlaying)
                                play()
                            else
                                pause()
                        }
                    }
                }

                Timer {
                    interval: 33
                    repeat: true
                    running: brollTabItem.previewPlaying
                    onTriggered: {
                        const item = brollTabItem.currentPreview
                        const duration = item ? Math.max(0.2, item.timelineDurationSeconds || 1.0) : 1.0
                        brollTabItem.previewProgress += interval / (duration * 1000)
                        if (brollTabItem.previewProgress >= 1.0) {
                            brollTabItem.previewProgress = 1.0
                            brollTabItem.previewPlaying = false
                            brollPreviewPlayer.pause()
                            stopAudioPreview()
                        }
                    }
                }

                onVisibleChanged: {
                    if (visible && root.brollEnabled)
                        refreshPreview()
                    else if (!visible) {
                        previewPlaying = false
                        brollPreviewPlayer.stop()
                        stopAudioPreview()
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    ThemedCheckBox {
                        text: qsTr("Ativar B-Rolls Textuais (Efeito Máquina de Escrever + Escurecimento da Cena)")
                        checked: root.brollEnabled
                        onCheckedChanged: root.brollEnabled = checked
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        visible: root.brollEnabled

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Quantidade de Cenas com B-Roll:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 200
                                from: 1
                                to: 10
                                stepSize: 1
                                value: root.brollCount
                                onValueChanged: root.brollCount = Math.round(value)
                            }
                            Text {
                                text: root.brollCount + " cenas"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Intensidade do Escurecimento (Darken):")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 200
                                from: 0.2
                                to: 0.9
                                value: root.brollDarkenIntensity
                                onValueChanged: root.brollDarkenIntensity = Math.round(value * 100) / 100
                            }
                            Text {
                                text: Math.round(root.brollDarkenIntensity * 100) + "%"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }
                        }

                        Text {
                            text: qsTr("Efeito Sonoro de Teclado Mecânico (Keyboard Typing SFX):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField {
                                Layout.fillWidth: true
                                text: root.brollKeyboardAudioPath
                                placeholderText: qsTr("Selecione um efeito sonoro de digitação...")
                                onTextChanged: root.brollKeyboardAudioPath = text
                            }
                            ThemedButton {
                                text: qsTr("Selecionar...")
                                onClicked: {
                                    const url = FileDialogs.openFile(qsTr("Selecionar Som de Teclado"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.ogg)"))
                                    if (url && url.toString().length > 0) {
                                        root.brollKeyboardAudioPath = urlToLocalPath(url)
                                    }
                                }
                            }
                            ThemedButton {
                                text: playingAudioSource === urlToLocalPath(root.brollKeyboardAudioPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar Som") : qsTr("Ouvir Digitação")
                                variant: "ghost"
                                enabled: root.brollKeyboardAudioPath.length > 0
                                glyph: playingAudioSource === urlToLocalPath(root.brollKeyboardAudioPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                                onClicked: playAudioPreview(root.brollKeyboardAudioPath, root.brollKeyboardVolumeDb)
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Volume do som de digitação:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableMuted
                            }
                            ThemedSlider {
                                width: 200
                                from: -40.0
                                to: 15.0
                                value: root.brollKeyboardVolumeDb
                                onValueChanged: root.brollKeyboardVolumeDb = Math.round(value * 10) / 10
                            }
                            Text {
                                text: (root.brollKeyboardVolumeDb > 0 ? "+" : "") + root.brollKeyboardVolumeDb + " dB"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 320
                            color: root.readableSurface
                            radius: Theme.radiusSm
                            border.color: Theme.panelBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMd
                                spacing: Theme.spacingMd

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#080a0d"
                                    radius: Theme.radiusXs
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: brollTabItem.currentPreview && !brollTabItem.currentPreview.isVideo
                                                ? toFileUrl(brollTabItem.currentPreview.mediaPath) : ""
                                        fillMode: Image.PreserveAspectFit
                                        visible: source.toString().length > 0
                                    }

                                    VideoOutput {
                                        id: brollPreviewVideoOutput
                                        anchors.fill: parent
                                        fillMode: VideoOutput.PreserveAspectFit
                                        visible: brollTabItem.currentPreview
                                                 && brollTabItem.currentPreview.isVideo === true
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "#000000"
                                        opacity: brollTabItem.currentPreview
                                                 ? Number(brollTabItem.currentPreview.darkenOpacity || root.brollDarkenIntensity)
                                                 : 0
                                        visible: brollTabItem.currentPreview !== null
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width * 0.82
                                        text: brollTabItem.visiblePreviewText()
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 28
                                        font.weight: Font.Bold
                                        color: "#ffffff"
                                        style: Text.Outline
                                        styleColor: "#000000"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        wrapMode: Text.WordWrap
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        width: brollSceneBadge.implicitWidth + 14
                                        height: 24
                                        radius: 3
                                        color: Qt.rgba(0, 0, 0, 0.78)
                                        visible: brollTabItem.currentPreview !== null

                                        Text {
                                            id: brollSceneBadge
                                            anchors.centerIn: parent
                                            text: brollTabItem.currentPreview
                                                  ? qsTr("Cena #%1 • %2s").arg(brollTabItem.currentPreview.sceneNumber)
                                                        .arg(Number(brollTabItem.currentPreview.timelineStartSeconds || 0).toFixed(1))
                                                  : ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                            font.weight: Font.DemiBold
                                            color: Theme.primary
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 4
                                        color: Qt.rgba(1, 1, 1, 0.18)
                                        Rectangle {
                                            width: parent.width * brollTabItem.previewProgress
                                            height: parent.height
                                            color: Theme.primary
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 40
                                        visible: brollTabItem.currentPreview === null
                                        text: qsTr("Execute ou atualize a prévia para ver as cenas que receberão B-Roll textual.")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        color: "#c5cad2"
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: 310
                                    Layout.fillHeight: true
                                    spacing: Theme.spacingSm

                                    Text {
                                        Layout.fillWidth: true
                                        text: qsTr("Pré-visualização das cenas com B-Roll")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeMd
                                        font.weight: Font.Bold
                                        color: root.readableText
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: brollTabItem.currentPreview
                                              ? qsTr("Cena %1 de %2 • duração %3s")
                                                    .arg(brollTabItem.previewIndex + 1)
                                                    .arg(brollTabItem.previewItems.length)
                                                    .arg(Number(brollTabItem.currentPreview.timelineDurationSeconds || 0).toFixed(1))
                                              : qsTr("Nenhuma inserção planejada ainda.")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        color: root.readableMuted
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: brollTabItem.currentPreview ? (brollTabItem.currentPreview.text || "") : ""
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        color: root.readableText
                                        wrapMode: Text.WordWrap
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXs

                                        ThemedButton {
                                            Layout.preferredWidth: 44
                                            glyph: Theme.icons.chevronLeft
                                            enabled: brollTabItem.previewIndex > 0
                                            tooltip: qsTr("Cena B-Roll anterior")
                                            onClicked: {
                                                brollTabItem.previewPlaying = false
                                                brollTabItem.previewProgress = 0
                                                brollTabItem.previewIndex--
                                                brollTabItem.loadPreviewMedia()
                                            }
                                        }
                                        ThemedButton {
                                            Layout.fillWidth: true
                                            text: brollTabItem.previewPlaying ? qsTr("Pausar") : qsTr("Visualizar")
                                            glyph: brollTabItem.previewPlaying ? Theme.icons.pause : Theme.icons.play
                                            enabled: brollTabItem.currentPreview !== null
                                            variant: "primary"
                                            onClicked: brollTabItem.togglePreview()
                                        }
                                        ThemedButton {
                                            Layout.preferredWidth: 44
                                            glyph: Theme.icons.chevronRight
                                            enabled: brollTabItem.previewIndex + 1 < brollTabItem.previewItems.length
                                            tooltip: qsTr("Próxima cena B-Roll")
                                            onClicked: {
                                                brollTabItem.previewPlaying = false
                                                brollTabItem.previewProgress = 0
                                                brollTabItem.previewIndex++
                                                brollTabItem.loadPreviewMedia()
                                            }
                                        }
                                    }

                                    ThemedButton {
                                        Layout.fillWidth: true
                                        text: qsTr("Atualizar Cenas Planejadas")
                                        glyph: Theme.icons.refresh
                                        onClicked: brollTabItem.refreshPreview()
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 6: TRANSITIONS & SUBTITLES
            Item {
                id: transitionsTabItem
                anchors.fill: parent
                visible: root.activeTab === "transitions"

                property var subtitleAnimationIds: ["none", "fade", "slideUp", "pop", "rise", "bounce", "wave", "typewriter"]
                property var subtitleAnimationLabels: [
                    qsTr("Nenhuma"), qsTr("Fade"), qsTr("Deslizar para Cima"), qsTr("Pop"),
                    qsTr("Subir"), qsTr("Bounce"), qsTr("Onda"), qsTr("Máquina de Escrever")
                ]

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Text {
                        text: qsTr("Transições de Cena:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: root.readableText
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Modo de Transição:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedComboBox {
                            width: 220
                            model: [qsTr("Nenhuma (Corte Seco)"), qsTr("Fixa (Escolher Tipo)"), qsTr("Aleatória (15 Efeitos YouTube)")]
                            currentIndex: root.transitionKind === "fixed" ? 1 : (root.transitionKind === "random" ? 2 : 0)
                            onActivated: (idx) => {
                                root.transitionKind = idx === 1 ? "fixed" : (idx === 2 ? "random" : "none")
                            }
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        visible: root.transitionKind === "fixed"
                        Text {
                            text: qsTr("Tipo de Transição Fixa:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedComboBox {
                            width: 280
                            property var transitionList: [
                                { id: "crossfade", name: qsTr("Crossfade Suave") },
                                { id: "push_left", name: qsTr("Push / Deslizar para Esquerda") },
                                { id: "wipe_left", name: qsTr("Wipe / Varredura Esquerda") },
                                { id: "wipe_right", name: qsTr("Wipe / Varredura Direita") },
                                { id: "wipe_up", name: qsTr("Wipe / Varredura Cima") },
                                { id: "wipe_down", name: qsTr("Wipe / Varredura Baixo") },
                                { id: "zoom_in", name: qsTr("Zoom In Dinâmico") },
                                { id: "cross_zoom_swirl", name: qsTr("Cross Zoom com Espiral") },
                                { id: "radial_zoom_blur", name: qsTr("Radial Zoom Blur") },
                                { id: "dip", name: qsTr("Dip to Black (Fade Preto)") },
                                { id: "dip_white", name: qsTr("Dip to White (Flash Branco)") },
                                { id: "luma_fade", name: qsTr("Luma Fade Suave") },
                                { id: "vhs_scanline", name: qsTr("VHS Glitch Scanlines") },
                                { id: "rgb_displacement", name: qsTr("RGB Glitch Displacement") },
                                { id: "pixelate_matrix", name: qsTr("Pixelate / Mosaico") }
                            ]
                            model: transitionList.map(function(t) { return t.name })
                            currentIndex: {
                                for (var i = 0; i < transitionList.length; ++i) {
                                    if (transitionList[i].id === root.transitionFixedKindId) return i
                                }
                                return 0
                            }
                            onActivated: (idx) => {
                                if (idx >= 0 && idx < transitionList.length) {
                                    root.transitionFixedKindId = transitionList[idx].id
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        visible: root.transitionKind !== "none"
                        Text {
                            text: qsTr("Duração da Transição:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 200
                            from: 0.2
                            to: 2.0
                            value: root.transitionDurationSeconds
                            onValueChanged: root.transitionDurationSeconds = Math.round(value * 10) / 10
                        }
                        Text {
                            text: root.transitionDurationSeconds + " s"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                    }

                    Text {
                        text: qsTr("Efeito Sonoro Whoosh (sincronizado nos cortes com transição):")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: root.readableMuted
                        visible: root.transitionKind !== "none"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.transitionKind !== "none"
                        ThemedTextField {
                            Layout.fillWidth: true
                            text: root.transitionWhooshAudioPath
                            placeholderText: qsTr("Selecione o som de transição Whoosh (.wav, .mp3)...")
                            onTextChanged: root.transitionWhooshAudioPath = text
                        }
                        ThemedButton {
                            text: qsTr("Selecionar...")
                            onClicked: {
                                const url = FileDialogs.openFile(qsTr("Selecionar Som Whoosh"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.ogg)"))
                                if (url && url.toString().length > 0) {
                                    root.transitionWhooshAudioPath = urlToLocalPath(url)
                                }
                            }
                        }
                        ThemedButton {
                            text: playingAudioSource === urlToLocalPath(root.transitionWhooshAudioPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? qsTr("Parar Som") : qsTr("Ouvir Whoosh")
                            variant: "ghost"
                            enabled: root.transitionWhooshAudioPath.length > 0
                            glyph: playingAudioSource === urlToLocalPath(root.transitionWhooshAudioPath) && previewAudioPlayer.playbackState === MediaPlayer.PlayingState ? Theme.icons.pause : Theme.icons.play
                            onClicked: playAudioPreview(root.transitionWhooshAudioPath, root.transitionWhooshVolumeDb)
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        visible: root.transitionKind !== "none"
                        Text {
                            text: qsTr("Volume do som Whoosh:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableMuted
                        }
                        ThemedSlider {
                            width: 200
                            from: -40.0
                            to: 15.0
                            value: root.transitionWhooshVolumeDb
                            onValueChanged: root.transitionWhooshVolumeDb = Math.round(value * 10) / 10
                        }
                        Text {
                            text: (root.transitionWhooshVolumeDb > 0 ? "+" : "") + root.transitionWhooshVolumeDb + " dB"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: root.readableText
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.panelBorder
                    }

                    Text {
                        text: qsTr("Legendas Visíveis na Timeline:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: root.readableText
                    }

                    ThemedCheckBox {
                        text: qsTr("Adicionar faixa de legendas visíveis na timeline geradas a partir do SRT")
                        checked: root.subtitlesVisible
                        onCheckedChanged: root.subtitlesVisible = checked
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.subtitlesVisible
                        spacing: Theme.spacingMd

                        Text { text: qsTr("Fonte:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedComboBox {
                            Layout.preferredWidth: 170
                            model: root.subtitleFontChoices
                            currentIndex: Math.max(0, root.subtitleFontChoices.indexOf(root.subtitleFontFamily))
                            tooltip: qsTr("Fontes populares para legendas de filmes e YouTube instaladas neste computador")
                            onActivated: root.subtitleFontFamily = root.subtitleFontChoices[index]
                        }
                        Text { text: qsTr("Tamanho:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedSlider {
                            Layout.preferredWidth: 150
                            from: 24
                            to: 120
                            stepSize: 1
                            value: root.subtitlePixelSize
                            onValueChanged: root.subtitlePixelSize = Math.round(value)
                        }
                        Text { text: root.subtitlePixelSize + " px"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableText; Layout.preferredWidth: 48 }
                        ThemedCheckBox {
                            text: qsTr("Negrito")
                            checked: root.subtitleBold
                            onCheckedChanged: root.subtitleBold = checked
                        }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.subtitlesVisible
                        spacing: Theme.spacingMd

                        Text { text: qsTr("Cor do texto:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedTextField {
                            Layout.preferredWidth: 105
                            text: root.subtitleColor
                            placeholderText: "#ffffff"
                            onEditingFinished: root.subtitleColor = text.trim()
                        }
                        ThemedCheckBox {
                            text: qsTr("Contorno")
                            checked: root.subtitleOutlineEnabled
                            onCheckedChanged: root.subtitleOutlineEnabled = checked
                        }
                        Text { visible: root.subtitleOutlineEnabled; text: qsTr("Cor:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedTextField {
                            visible: root.subtitleOutlineEnabled
                            Layout.preferredWidth: 105
                            text: root.subtitleOutlineColor
                            placeholderText: "#000000"
                            onEditingFinished: root.subtitleOutlineColor = text.trim()
                        }
                        Text { visible: root.subtitleOutlineEnabled; text: qsTr("Espessura:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedSlider {
                            visible: root.subtitleOutlineEnabled
                            Layout.preferredWidth: 120
                            from: 0
                            to: 10
                            stepSize: 0.5
                            value: root.subtitleOutlineWidth
                            onValueChanged: root.subtitleOutlineWidth = Math.round(value * 2) / 2
                        }
                        Text { visible: root.subtitleOutlineEnabled; text: root.subtitleOutlineWidth.toFixed(1) + " px"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableText }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.subtitlesVisible
                        spacing: Theme.spacingLg

                        ThemedCheckBox {
                            text: qsTr("Sombra")
                            checked: root.subtitleShadowEnabled
                            onCheckedChanged: root.subtitleShadowEnabled = checked
                        }
                        ThemedCheckBox {
                            text: qsTr("Fundo atrás da legenda")
                            checked: root.subtitleBoxEnabled
                            onCheckedChanged: root.subtitleBoxEnabled = checked
                        }
                        Text { visible: root.subtitleBoxEnabled; text: qsTr("Cor do fundo:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedTextField {
                            visible: root.subtitleBoxEnabled
                            Layout.preferredWidth: 115
                            text: root.subtitleBoxColor
                            placeholderText: "#80000000"
                            onEditingFinished: root.subtitleBoxColor = text.trim()
                        }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.subtitlesVisible
                        spacing: Theme.spacingMd

                        Text { text: qsTr("Entrada:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedComboBox {
                            Layout.preferredWidth: 175
                            model: transitionsTabItem.subtitleAnimationLabels
                            currentIndex: Math.max(0, transitionsTabItem.subtitleAnimationIds.indexOf(root.subtitleAnimIn))
                            onActivated: (idx) => root.subtitleAnimIn = transitionsTabItem.subtitleAnimationIds[idx]
                        }
                        Text { text: qsTr("Saída:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedComboBox {
                            Layout.preferredWidth: 175
                            model: transitionsTabItem.subtitleAnimationLabels
                            currentIndex: Math.max(0, transitionsTabItem.subtitleAnimationIds.indexOf(root.subtitleAnimOut))
                            onActivated: (idx) => root.subtitleAnimOut = transitionsTabItem.subtitleAnimationIds[idx]
                        }
                        Text { text: qsTr("Duração:"); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableMuted }
                        ThemedSlider {
                            Layout.preferredWidth: 130
                            from: 0.1
                            to: 1.5
                            stepSize: 0.05
                            value: root.subtitleAnimDurationSeconds
                            onValueChanged: root.subtitleAnimDurationSeconds = Math.round(value * 20) / 20
                        }
                        Text { text: root.subtitleAnimDurationSeconds.toFixed(2) + "s"; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; color: root.readableText }
                        Item { Layout.fillWidth: true }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 7: REVIEW & ASSEMBLE
            Item {
                id: reviewTabItem
                anchors.fill: parent
                visible: root.activeTab === "review"
                onVisibleChanged: {
                    if (visible) {
                        if (root.preparationComplete) {
                            root.runValidation()
                            resetFlowPreview()
                        } else {
                            pauseFlow()
                            root.operationStatus = qsTr("Execute as etapas 1–6 antes de validar, visualizar e montar.")
                        }
                    }
                }

                property bool flowIsPlaying: false
                property double flowPlayheadSeconds: 0.0
                property var currentSceneAction: null
                property string currentCueText: ""
                property string flowScenePath: ""

                function resetFlowPreview() {
                    pauseFlow()
                    flowPlayheadSeconds = 0
                    flowNarrPlayer.setPosition(0)
                    updateFlowState()
                }

                function formatTimecode(secs) {
                    if (!secs || isNaN(secs) || secs < 0) secs = 0
                    const m = Math.floor(secs / 60)
                    const s = Math.floor(secs % 60)
                    const mm = (m < 10 ? "0" : "") + m
                    const ss = (s < 10 ? "0" : "") + s
                    return mm + ":" + ss
                }

                MediaPlayer {
                    id: flowNarrPlayer
                    audioOutput: AudioOutput {
                        id: flowNarrAudioOutput
                        volume: Math.max(0.0, Math.pow(10.0, root.narrationVolumeDb / 20.0))
                    }
                    onPositionChanged: {
                        if (flowIsPlaying && playbackState === MediaPlayer.PlayingState) {
                            flowPlayheadSeconds = position / 1000.0
                            updateFlowState()
                        }
                    }
                    onMediaStatusChanged: {
                        if (mediaStatus === MediaPlayer.EndOfMedia) {
                            pauseFlow()
                            flowPlayheadSeconds = 0
                            setPosition(0)
                            updateFlowState()
                        }
                    }
                    onErrorOccurred: function(error, errorString) {
                        if (error !== MediaPlayer.NoError)
                            root.operationStatus = qsTr("A narração não pôde ser reproduzida; a prévia visual continuará sem áudio: %1").arg(errorString)
                    }
                }

                MediaPlayer {
                    id: flowScenePlayer
                    videoOutput: flowVideoOutput
                    audioOutput: AudioOutput { muted: true }
                    onMediaStatusChanged: {
                        if (mediaStatus === MediaPlayer.LoadedMedia
                                || mediaStatus === MediaPlayer.BufferedMedia)
                            reviewTabItem.syncFlowVideoPosition()
                    }
                }

                Timer {
                    id: flowTimer
                    interval: 33
                    repeat: true
                    running: flowIsPlaying
                    onTriggered: {
                        if (flowNarrPlayer.playbackState === MediaPlayer.PlayingState)
                            flowPlayheadSeconds = flowNarrPlayer.position / 1000.0
                        else
                            flowPlayheadSeconds += interval / 1000.0
                        const totalSec = Math.max(1.0, CustomProject.planDurationSeconds)
                        if (flowPlayheadSeconds >= totalSec) {
                            pauseFlow()
                            flowPlayheadSeconds = 0
                        }
                        updateFlowState()
                    }
                }

                function updateFlowState() {
                    const actions = root.planSummary.sceneActions || []
                    let found = null
                    for (let i = 0; i < actions.length; ++i) {
                        const a = actions[i]
                        if (flowPlayheadSeconds >= a.timelineStartSeconds && flowPlayheadSeconds < (a.timelineStartSeconds + a.timelineDurationSeconds)) {
                            found = a
                            break
                        }
                    }
                    currentSceneAction = found
                    if (found) {
                        currentCueText = found.cueText || ""
                        if (found.mediaPath && found.mediaPath.length > 0) {
                            if (found.isVideo) {
                                flowMonitorImage.source = ""
                                const localPath = urlToLocalPath(found.mediaPath)
                                if (flowScenePath !== localPath) {
                                    flowScenePlayer.stop()
                                    flowScenePath = localPath
                                    flowScenePlayer.source = toFileUrl(localPath)
                                }
                                syncFlowVideoPosition()
                            } else {
                                flowScenePlayer.stop()
                                flowScenePath = ""
                                flowScenePlayer.source = ""
                                flowMonitorImage.source = toFileUrl(found.mediaPath)
                            }
                        } else {
                            flowScenePlayer.stop()
                            flowScenePath = ""
                            flowScenePlayer.source = ""
                            flowMonitorImage.source = ""
                        }
                    } else {
                        currentCueText = ""
                        flowScenePlayer.stop()
                        flowScenePath = ""
                        flowScenePlayer.source = ""
                        flowMonitorImage.source = ""
                    }
                }

                function syncFlowVideoPosition() {
                    const action = currentSceneAction
                    if (!action || !action.isVideo || !flowScenePath)
                        return
                    const localTimelineSeconds = Math.max(0, flowPlayheadSeconds - action.timelineStartSeconds)
                    const sourceInSeconds = action.sourceInSeconds || 0
                    const rate = Math.max(0.05, action.speed || 1.0)
                    const wantedMs = Math.max(0, Math.round((sourceInSeconds + localTimelineSeconds * rate) * 1000))
                    flowScenePlayer.playbackRate = rate
                    if (Math.abs(flowScenePlayer.position - wantedMs) > 250)
                        flowScenePlayer.setPosition(wantedMs)
                    if (flowIsPlaying)
                        flowScenePlayer.play()
                    else
                        flowScenePlayer.pause()
                }

                function toggleFlowPlay() {
                    if (flowIsPlaying) {
                        pauseFlow()
                    } else {
                        playFlow()
                    }
                }

                function playFlow() {
                    stopAudioPreview()
                    if (!root.planSummary.sceneActions || root.planSummary.sceneActions.length === 0) {
                        root.operationStatus = qsTr("Execute as etapas 1–6 para criar a prévia antes de reproduzir.")
                        return
                    }
                    flowIsPlaying = true
                    root.operationStatus = qsTr("Reproduzindo a prévia do projeto...")
                    if (root.narrationPath && root.narrationPath.length > 0) {
                        flowNarrPlayer.source = toFileUrl(root.narrationPath)
                        flowNarrPlayer.setPosition(Math.round(flowPlayheadSeconds * 1000))
                        flowNarrPlayer.play()
                    }
                    updateFlowState()
                }

                function pauseFlow() {
                    flowIsPlaying = false
                    flowNarrPlayer.pause()
                    flowScenePlayer.pause()
                }

                function seekFlow(targetSec) {
                    flowPlayheadSeconds = targetSec
                    if (root.narrationPath && root.narrationPath.length > 0) {
                        flowNarrPlayer.setPosition(Math.round(targetSec * 1000))
                    }
                    updateFlowState()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingMd

                    // Top Bar: Validation & Status
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ThemedButton {
                            text: root.operationBusy ? qsTr("Executando Etapas 1–6...") : qsTr("Executar Etapas 1–6")
                            glyph: Theme.icons.wand
                            variant: "primary"
                            enabled: !root.operationBusy
                            onClicked: root.executeStepsOneToSix()
                        }

                        ThemedButton {
                            text: qsTr("Validar e Analisar Projeto")
                            glyph: Theme.icons.check
                            variant: "secondary"
                            enabled: root.preparationComplete && !root.operationBusy
                            onClicked: {
                                const summary = root.runValidation()
                                root.operationStatus = summary.isValid
                                        ? qsTr("Projeto validado e pronto para visualização.")
                                        : qsTr("Validação concluída: consulte as inconsistências abaixo.")
                                resetFlowPreview()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: !root.preparationComplete
                                  ? qsTr("Aguardando execução das etapas 1–6")
                                  : root.planSummary.isValid === true
                                  ? ((root.planSummary.warningCount || 0) > 0
                                     ? qsTr("✓ Plano válido com %1 aviso(s) — %2").arg(root.planSummary.warningCount).arg(formatTimecode(CustomProject.planDurationSeconds))
                                     : qsTr("✓ Plano válido! Duração total: %1 (%2s)").arg(formatTimecode(CustomProject.planDurationSeconds)).arg(Math.round(CustomProject.planDurationSeconds)))
                                  : qsTr("✕ Plano inválido — %1 erro(s), %2 aviso(s)").arg(root.planSummary.errorCount || 0).arg(root.planSummary.warningCount || 0)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: !root.preparationComplete ? root.readableMuted
                                   : (root.planSummary.isValid === true ? Theme.constructive : Theme.destructive)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.operationStatus
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        color: root.assemblySucceeded ? Theme.constructive : root.readableMuted
                        wrapMode: Text.WordWrap
                    }

                    // Summary Category Cards Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSm

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: Theme.radiusSm
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 2
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Total de Cenas"); font.family: Theme.fontFamily; font.pixelSize: 10; color: root.readableMuted }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(root.planSummary.slotsCount !== undefined ? root.planSummary.slotsCount : (CustomProject.totalScenesCount || 0)); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: root.readableText }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: Theme.radiusSm
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 2
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Cenas Cortadas (Keep)"); font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.primary }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(root.planSummary.cutScenesCount || 0); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: Theme.primary }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: Theme.radiusSm
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 2
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Aceleradas / Retimed"); font.family: Theme.fontFamily; font.pixelSize: 10; color: root.readableMuted }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(root.planSummary.retimedScenesCount || 0); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: root.readableText }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: Theme.radiusSm
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 2
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Exatas / Ken Burns"); font.family: Theme.fontFamily; font.pixelSize: 10; color: Theme.constructive }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(root.planSummary.exactScenesCount || 0); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: Theme.constructive }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: Theme.radiusSm
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 2
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Estendidas / Gaps"); font.family: Theme.fontFamily; font.pixelSize: 10; color: (root.planSummary.extendedScenesCount > 0 ? Theme.warning : root.readableMuted) }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(root.planSummary.extendedScenesCount || 0); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: (root.planSummary.extendedScenesCount > 0 ? Theme.warning : root.readableText) }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 48
                            radius: Theme.radiusSm
                            color: root.readableSurface
                            border.color: Theme.panelBorder
                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 8
                                spacing: 2
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("CTAs recorrentes"); font.family: Theme.fontFamily; font.pixelSize: 10; color: root.readableMuted }
                                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: String(root.planSummary.ctaOccurrencesCount || 0); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.Bold; color: (root.planSummary.ctaOccurrencesCount > 0 ? Theme.primary : root.readableText) }
                            }
                        }
                    }

                    // Main Interactive Section: Monitor + Table Split
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Theme.spacingMd

                        // Left: Flow Preview Player
                        Rectangle {
                            Layout.preferredWidth: 460
                            Layout.fillHeight: true
                            color: Theme.appBackground
                            radius: Theme.radiusSm
                            border.color: Theme.panelBorder
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingSm
                                spacing: Theme.spacingSm

                                // Video Monitor Box
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#0a0c10"
                                    radius: Theme.radiusXs
                                    clip: true

                                    Image {
                                        id: flowMonitorImage
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectFit
                                        visible: source.toString().length > 0
                                    }

                                    VideoOutput {
                                        id: flowVideoOutput
                                        anchors.fill: parent
                                        fillMode: VideoOutput.PreserveAspectFit
                                        visible: currentSceneAction !== null
                                                 && currentSceneAction.isVideo === true
                                                 && flowScenePath.length > 0
                                    }

                                    // Placeholder when no media
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        visible: currentSceneAction === null
                                                 || !currentSceneAction.mediaPath
                                                 || currentSceneAction.mediaPath.length === 0
                                        IconGlyph {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            glyph: Theme.icons.play
                                            iconSize: 32
                                            iconColor: root.readableMuted
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: qsTr("Monitor de Preview do Fluxo")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                            color: root.readableMuted
                                        }
                                    }

                                    // Active Scene Badge Overlay
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.margins: 8
                                        height: 22
                                        width: sceneBadgeText.implicitWidth + 14
                                        radius: 3
                                        color: Qt.rgba(0, 0, 0, 0.75)
                                        visible: currentSceneAction !== null

                                        Text {
                                            id: sceneBadgeText
                                            anchors.centerIn: parent
                                            text: currentSceneAction ? ("#" + currentSceneAction.sceneNumber + " (" + currentSceneAction.actionDescription + ")") : ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                            color: Theme.primary
                                        }
                                    }

                                    // Subtitle Caption Overlay
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 10
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(parent.width - 24, flowSubText.implicitWidth + 24)
                                        height: flowSubText.implicitHeight + 8
                                        radius: 4
                                        color: Qt.rgba(0, 0, 0, 0.8)
                                        visible: currentCueText.length > 0

                                        Text {
                                            id: flowSubText
                                            anchors.centerIn: parent
                                            width: parent.width - 16
                                            text: currentCueText
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                            font.weight: Font.Bold
                                            color: "#ffffff"
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                // Transport Bar
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm

                                    ThemedButton {
                                        text: flowIsPlaying ? qsTr("Pausar") : qsTr("Play")
                                        variant: flowIsPlaying ? "secondary" : "primary"
                                        glyph: flowIsPlaying ? Theme.icons.pause : Theme.icons.play
                                        Layout.preferredWidth: 110
                                        Layout.minimumWidth: 100
                                        enabled: root.preparationComplete && (root.planSummary.sceneActions || []).length > 0
                                        tooltip: flowIsPlaying ? qsTr("Pausar prévia") : qsTr("Reproduzir prévia das cenas")
                                        onClicked: toggleFlowPlay()
                                    }

                                    ThemedSlider {
                                        id: flowScrubber
                                        Layout.fillWidth: true
                                        from: 0.0
                                        to: Math.max(1.0, CustomProject.planDurationSeconds)
                                        value: flowPlayheadSeconds
                                        onMoved: seekFlow(value)
                                    }

                                    Text {
                                        text: formatTimecode(flowPlayheadSeconds) + " / " + formatTimecode(Math.max(1.0, CustomProject.planDurationSeconds))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        font.weight: Font.DemiBold
                                        color: root.readableText
                                        Layout.preferredWidth: 72
                                    }
                                }
                            }
                        }

                        // Right: Scene Actions Table & Warnings
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.appBackground
                            radius: Theme.radiusSm
                            border.color: Theme.panelBorder
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingSm
                                spacing: Theme.spacingSm

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: qsTr("Detalhamento de Cenas e Ações:")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: Font.Bold
                                        color: root.readableText
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: ((root.planSummary.errorCount || 0) > 0)
                                              ? qsTr("%1 erro(s) • %2 aviso(s)").arg(root.planSummary.errorCount).arg(root.planSummary.warningCount || 0)
                                              : ((root.planSummary.warningCount || 0) > 0
                                                 ? qsTr("%1 aviso(s)").arg(root.planSummary.warningCount)
                                                 : qsTr("Nenhuma inconsistência"))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: (root.planSummary.errorCount || 0) > 0
                                               ? Theme.destructive
                                               : ((root.planSummary.warningCount || 0) > 0 ? Theme.warning : Theme.constructive)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Math.min(112, 30 + (root.planSummary.messages || []).length * 24)
                                    visible: (root.planSummary.messages || []).length > 0
                                    color: Qt.rgba(1, 0.55, 0, 0.08)
                                    radius: Theme.radiusXs
                                    border.color: (root.planSummary.errorCount || 0) > 0 ? Theme.destructive : Theme.warning

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3

                                        Text {
                                            text: qsTr("Inconsistências e avisos encontrados:")
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeXs
                                            font.weight: Font.Bold
                                            color: root.readableText
                                        }

                                        ListView {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            model: root.planSummary.messages || []
                                            spacing: 2
                                            delegate: Text {
                                                width: ListView.view.width
                                                text: (modelData.severity === "error" ? "✕ " : "⚠ ")
                                                      + (modelData.sceneNumber > 0 ? qsTr("Cena %1: ").arg(modelData.sceneNumber) : "")
                                                      + modelData.message
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                color: modelData.severity === "error" ? Theme.destructive : Theme.warning
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }

                                ListView {
                                    id: sceneActionsListView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: root.planSummary.sceneActions || []
                                    spacing: 3

                                    ScrollBar.vertical: ScrollBar {
                                        id: sceneActionsScrollBar
                                        active: true
                                        policy: ScrollBar.AlwaysOn
                                    }

                                    delegate: Rectangle {
                                        width: sceneActionsListView.width - (sceneActionsScrollBar.visible ? sceneActionsScrollBar.width + 4 : 0)
                                        height: 38
                                        radius: Theme.radiusXs
                                        color: (currentSceneAction && currentSceneAction.sceneNumber === modelData.sceneNumber)
                                               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                                               : (modelData.isEmpty ? Qt.rgba(1, 1, 1, 0.02) : root.readableSurface)
                                        border.color: (currentSceneAction && currentSceneAction.sceneNumber === modelData.sceneNumber)
                                                      ? Theme.primary
                                                      : Theme.panelBorder
                                        border.width: 1

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: seekFlow(modelData.timelineStartSeconds)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: Theme.spacingSm

                                            Text {
                                                text: "#" + modelData.sceneNumber
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                                font.weight: Font.Bold
                                                color: root.readableText
                                                Layout.preferredWidth: 36
                                            }

                                            Text {
                                                text: formatTimecode(modelData.timelineStartSeconds)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                color: root.readableMuted
                                                Layout.preferredWidth: 44
                                            }

                                            Text {
                                                text: (modelData.actionDescription || qsTr("Normal"))
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                                font.weight: Font.DemiBold
                                                color: modelData.isEmpty ? Theme.destructive : (modelData.actionDescription && modelData.actionDescription.indexOf("Cortado") >= 0 ? Theme.primary : root.readableText)
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: modelData.isVideo && modelData.sourceDurationSeconds > 0
                                                      ? Number(modelData.sourceDurationSeconds).toFixed(1) + "s"
                                                      : "--"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                color: root.readableMuted
                                                horizontalAlignment: Text.AlignRight
                                                Layout.preferredWidth: 42
                                            }

                                            Text {
                                                text: "→"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                color: root.readableMuted
                                            }

                                            Text {
                                                text: Number(modelData.timelineDurationSeconds).toFixed(1) + "s"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                font.weight: Font.DemiBold
                                                color: Theme.constructive
                                                Layout.preferredWidth: 42
                                            }

                                            ThemedButton {
                                                text: qsTr("Pular")
                                                variant: "ghost"
                                                onClicked: seekFlow(modelData.timelineStartSeconds)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Save as .drift file picker
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd
                        ThemedTextField {
                            Layout.fillWidth: true
                            text: root.saveProjectPath
                            placeholderText: qsTr("Salvar automaticamente em arquivo .drift nativo (opcional)")
                            onTextChanged: root.saveProjectPath = text
                        }
                        ThemedButton {
                            text: qsTr("Destino .drift...")
                            onClicked: {
                                const url = FileDialogs.saveFile(qsTr("Salvar Projeto Drift"), qsTr("Projetos Drift (*.drift)"), "drift")
                                if (url && url.toString().length > 0) {
                                    root.saveProjectPath = urlToLocalPath(url)
                                }
                            }
                        }
                    }

                    // Project Configuration Quick Status & Save
                    Rectangle {
                        Layout.fillWidth: true
                        height: 44
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                        radius: Theme.radiusSm
                        border.color: Theme.primary
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSm
                            spacing: Theme.spacingMd

                            IconGlyph {
                                glyph: Theme.icons.save
                                iconSize: Theme.iconSizeMd
                                iconColor: Theme.primary
                            }

                            Text {
                                text: projectCombo.currentText.length > 0
                                      ? qsTr("Projeto salvo ativo: <b>%1</b>").arg(projectCombo.currentText)
                                      : qsTr("Nenhum projeto salvo selecionado (configuração temporária)")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: root.readableText
                                textFormat: Text.RichText
                            }

                            Item { Layout.fillWidth: true }

                            ThemedButton {
                                text: qsTr("Salvar Configuração do Projeto")
                                variant: "secondary"
                                glyph: Theme.icons.save
                                onClicked: {
                                    const name = projectCombo.currentText.trim()
                                    if (name.length > 0) {
                                        CustomProject.saveProjectConfig(name, root.syncToProject())
                                    } else {
                                        newProjectDialog.openDialog()
                                    }
                                }
                            }
                        }
                    }

                    // Big Execute Button
                    ThemedButton {
                        Layout.fillWidth: true
                        height: 48
                        text: root.operationBusy ? qsTr("MONTANDO PROJETO NA TIMELINE...")
                                                 : qsTr("MONTAR PROJETO PERSONALIZADO NA TIMELINE")
                        variant: "primary"
                        glyph: Theme.icons.wand
                        enabled: root.preparationComplete
                                 && root.planSummary.isValid === true
                                 && !root.operationBusy
                        onClicked: {
                            pauseFlow()
                            stopAudioPreview()
                            root.operationBusy = true
                            root.assemblySucceeded = false
                            root.operationStatus = qsTr("Montando o projeto personalizado na timeline...")
                            const started = CustomProject.executeAssembly(AppController, root.saveProjectPath)
                            if (started === false) {
                                root.operationBusy = false
                                root.operationStatus = qsTr("Não foi possível iniciar a montagem. Verifique as inconsistências acima.")
                            }
                        }
                    }

                    ThemedButton {
                        Layout.fillWidth: true
                        visible: root.assemblySucceeded
                        text: qsTr("FECHAR E VER O PROJETO NA TIMELINE")
                        variant: "secondary"
                        glyph: Theme.icons.check
                        onClicked: root.close()
                    }
                }
            }
        }
    }

    Connections {
        target: CustomProject
        function onAssemblyFinished(success, message) {
            root.operationBusy = false
            root.assemblySucceeded = success
            root.operationStatus = success
                    ? qsTr("Projeto montado com sucesso. Feche esta janela para revisar a timeline.")
                    : qsTr("Falha ao montar o projeto: %1").arg(message)
        }
    }

    // Dialogs for Project & Profile Management
    ThemedDialog {
        id: newProjectDialog
        title: qsTr("Novo Projeto Personalizado")
        acceptText: qsTr("Criar Projeto")
        rejectText: qsTr("Cancelar")
        preferredWidth: Theme.dialogWidthSm
        acceptOnReturn: true

        function openDialog() {
            projectNameField.text = ""
            open()
            projectNameField.forceActiveFocus()
        }

        onAccepted: {
            const name = projectNameField.text.trim()
            if (name.length > 0) {
                CustomProject.saveProjectConfig(name, root.syncToProject())
                const idx = CustomProject.projectList.indexOf(name)
                if (idx >= 0)
                    projectCombo.currentIndex = idx
            }
        }

        contentItem: Column {
            spacing: Theme.spacingMd
            width: parent ? parent.width : 320

            ThemedLabel {
                text: qsTr("Digite o nome do novo projeto:")
            }

            ThemedTextField {
                id: projectNameField
                width: parent.width
                placeholderText: qsTr("Ex: Meu_Video_01")
            }
        }
    }

    ThemedDialog {
        id: deleteProjectDialog
        title: qsTr("Excluir Projeto")
        acceptText: qsTr("Excluir")
        rejectText: qsTr("Cancelar")
        acceptVariant: "destructive"
        acceptOnReturn: false
        preferredWidth: Theme.dialogWidthSm

        property string projectNameToDelete: ""

        function openWith(name) {
            projectNameToDelete = name
            open()
        }

        onAccepted: {
            if (projectNameToDelete.length > 0) {
                CustomProject.deleteProjectConfig(projectNameToDelete)
                if (CustomProject.projectList.length > 0) {
                    projectCombo.currentIndex = 0
                    const p = CustomProject.loadProjectConfig(CustomProject.projectList[0])
                    root.syncFromProject(p)
                }
            }
        }

        contentItem: Column {
            spacing: Theme.spacingMd
            width: parent ? parent.width : 320

            ThemedLabel {
                wrapMode: Text.WordWrap
                width: parent.width
                text: qsTr("Tem certeza que deseja excluir o projeto \"%1\"?\nEsta ação removerá a configuração salva.").arg(deleteProjectDialog.projectNameToDelete)
            }
        }
    }

    ThemedDialog {
        id: newProfileDialog
        title: qsTr("Novo Perfil de Canal")
        acceptText: qsTr("Criar Perfil")
        rejectText: qsTr("Cancelar")
        preferredWidth: Theme.dialogWidthSm
        acceptOnReturn: true

        function openDialog() {
            profileNameField.text = ""
            open()
            profileNameField.forceActiveFocus()
        }

        onAccepted: {
            const name = profileNameField.text.trim()
            if (name.length > 0) {
                CustomProject.saveProfile(name, root.syncToProfile())
                const idx = CustomProject.profileList.indexOf(name)
                if (idx >= 0)
                    profileCombo.currentIndex = idx
            }
        }

        contentItem: Column {
            spacing: Theme.spacingMd
            width: parent ? parent.width : 320

            ThemedLabel {
                text: qsTr("Digite o nome do novo perfil de canal:")
            }

            ThemedTextField {
                id: profileNameField
                width: parent.width
                placeholderText: qsTr("Ex: Canal_Principal")
            }
        }
    }

    ThemedDialog {
        id: deleteProfileDialog
        title: qsTr("Excluir Perfil")
        acceptText: qsTr("Excluir")
        rejectText: qsTr("Cancelar")
        acceptVariant: "destructive"
        acceptOnReturn: false
        preferredWidth: Theme.dialogWidthSm

        property string profileNameToDelete: ""

        function openWith(name) {
            profileNameToDelete = name
            open()
        }

        onAccepted: {
            if (profileNameToDelete.length > 0) {
                CustomProject.deleteProfile(profileNameToDelete)
                if (CustomProject.profileList.length > 0) {
                    profileCombo.currentIndex = 0
                    const p = CustomProject.loadProfile(CustomProject.profileList[0])
                    root.syncFromProfile(p)
                }
            }
        }

        contentItem: Column {
            spacing: Theme.spacingMd
            width: parent ? parent.width : 320

            ThemedLabel {
                wrapMode: Text.WordWrap
                width: parent.width
                text: qsTr("Tem certeza que deseja excluir o perfil \"%1\"?\nEsta ação removerá o perfil salvo.").arg(deleteProfileDialog.profileNameToDelete)
            }
        }
    }
}
