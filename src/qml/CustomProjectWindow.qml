import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import Drift 1.0
import "components"

Window {
    id: root

    width: 1200
    height: 820
    minimumWidth: 960
    minimumHeight: 640
    title: qsTr("Projeto Personalizado - Drift")
    color: Theme.appBackground

    function openSession() {
        if (Qt.platform.os !== "windows")
            return
        CustomProject.refreshLists()
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
    property bool muteSceneAudio: true
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

    // Music
    property var musicList: []

    // Save project destination
    property string saveProjectPath: ""

    function syncToProfile() {
        return {
            videoTrimStrategy: root.videoTrimStrategy,
            minSpeed: root.minSpeed,
            maxSpeed: root.maxSpeed,
            muteSceneAudio: root.muteSceneAudio,
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
            brollEnabled: root.brollEnabled,
            brollCount: root.brollCount,
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
        if (p.brollEnabled !== undefined) root.brollEnabled = p.brollEnabled
        if (p.brollCount !== undefined) root.brollCount = p.brollCount
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
        if (p.musicList !== undefined) root.musicList = p.musicList
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
            height: 64
            color: Theme.panelBackground
            radius: Theme.radiusMd
            border.color: Theme.panelBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingMd

                IconGlyph {
                    glyph: Theme.icons.wand
                    size: Theme.iconSizeLg
                    color: Theme.primary
                }

                Column {
                    Text {
                        text: qsTr("Projeto Personalizado")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Theme.panelForeground
                    }
                    Text {
                        text: qsTr("Montagem de vídeo orientada a SRT no Drift")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                        color: Theme.panelMuted
                    }
                }

                Item { Layout.fillWidth: true }

                // Profile Selector
                Row {
                    spacing: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: qsTr("Perfil:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.panelMuted
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    ThemedComboBox {
                        id: profileCombo
                        width: 160
                        model: CustomProject.profileList
                        onActivated: (index) => {
                            if (index >= 0 && index < CustomProject.profileList.length) {
                                const p = CustomProject.loadProfile(CustomProject.profileList[index])
                                root.syncFromProfile(p)
                            }
                        }
                    }

                    ThemedButton {
                        text: qsTr("Salvar Perfil")
                        variant: "secondary"
                        onClicked: {
                            const name = profileCombo.currentText.length > 0 ? profileCombo.currentText : "Canal_Principal"
                            CustomProject.saveProfile(name, root.syncToProfile())
                        }
                    }
                }

                // Project Selector
                Row {
                    spacing: Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: qsTr("Projeto:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.panelMuted
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    ThemedComboBox {
                        id: projectCombo
                        width: 160
                        model: CustomProject.projectList
                        onActivated: (index) => {
                            if (index >= 0 && index < CustomProject.projectList.length) {
                                const p = CustomProject.loadProjectConfig(CustomProject.projectList[index])
                                root.syncFromProject(p)
                            }
                        }
                    }

                    ThemedButton {
                        text: qsTr("Salvar Config")
                        variant: "secondary"
                        onClicked: {
                            const name = projectCombo.currentText.length > 0 ? projectCombo.currentText : "Video_01"
                            CustomProject.saveProjectConfig(name, root.syncToProject())
                        }
                    }
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
            color: Theme.panelBackground
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
                                color: Theme.panelMuted
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
                                            root.primaryFolder = url.toLocalFile ? url.toLocalFile() : url.toString()
                                            CustomProject.scanFolders(root.primaryFolder, root.secondaryFolder)
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
                                color: Theme.panelMuted
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
                                            root.secondaryFolder = url.toLocalFile ? url.toLocalFile() : url.toString()
                                            CustomProject.scanFolders(root.primaryFolder, root.secondaryFolder)
                                        }
                                    }
                                }
                            }
                        }

                        ThemedButton {
                            text: qsTr("Escanear Pastas")
                            variant: "primary"
                            glyph: Theme.icons.refresh
                            Layout.alignment: Qt.AlignBottom
                            onClicked: CustomProject.scanFolders(root.primaryFolder, root.secondaryFolder)
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
                                color: Theme.panelMuted
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
                                            const p = url.toLocalFile ? url.toLocalFile() : url.toString()
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

                    // Summary Chips
                    Row {
                        spacing: Theme.spacingMd
                        Text {
                            text: qsTr("Total de Blocos: %1").arg(CustomProject.totalScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: Theme.panelForeground
                        }
                        Text {
                            text: qsTr("Preenchidos: %1").arg(CustomProject.filledScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.success
                        }
                        Text {
                            text: qsTr("Gaps / Em Branco: %1").arg(CustomProject.gapScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
                        }
                        Text {
                            text: qsTr("Conflitos: %1").arg(CustomProject.conflictScenesCount)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: CustomProject.conflictScenesCount > 0 ? Theme.warning : Theme.panelMuted
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

                            delegate: Rectangle {
                                id: sceneRow
                                width: scenesList.width
                                height: 44
                                radius: Theme.radiusSm
                                color: modelData.isConflict ? Qt.rgba(1, 0.7, 0, 0.15) : (modelData.isEmpty ? Qt.rgba(1, 1, 1, 0.03) : Theme.panelBackground)
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
                                        color: Theme.panelForeground
                                        Layout.preferredWidth: 40
                                    }

                                    Text {
                                        text: modelData.cueText || qsTr("(Sem texto SRT)")
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeXs
                                        color: Theme.panelMuted
                                        elide: Text.ElideRight
                                        Layout.preferredWidth: 260
                                    }

                                    Text {
                                        text: modelData.isEmpty ? qsTr("[ESPAÇO VAZIO / GAP PRESERVADO]") : (modelData.fileName + (modelData.isVideo ? " (Vídeo)" : " (Imagem)"))
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.weight: modelData.isEmpty ? Font.Normal : Font.DemiBold
                                        color: modelData.isEmpty ? Theme.panelMuted : Theme.panelForeground
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
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
                                            color: Theme.panelForeground
                                        }
                                    }

                                    // Conflict Warning
                                    IconGlyph {
                                        visible: modelData.isConflict
                                        glyph: Theme.icons.warning
                                        size: Theme.iconSizeMd
                                        color: Theme.warning
                                    }

                                    // Action buttons
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
                                            const url = FileDialogs.openFile(qsTr("Selecionar Mídia para Cena #%1").arg(modelData.sceneNumber))
                                            if (url && url.toString().length > 0) {
                                                const p = url.toLocalFile ? url.toLocalFile() : url.toString()
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
                        color: Theme.panelForeground
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Corte de Vídeos Longos:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
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
                            color: Theme.panelMuted
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
                            color: Theme.panelForeground
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
                            color: Theme.panelForeground
                        }
                    }

                    ThemedCheckBox {
                        text: qsTr("Silenciar áudio original dos vídeos das cenas (manter apenas narração e trilhas)")
                        checked: root.muteSceneAudio
                        onCheckedChanged: root.muteSceneAudio = checked
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
                        color: Theme.panelForeground
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
                            color: Theme.panelMuted
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
                            color: Theme.panelForeground
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 3: AUDIO & MUSIC
            Item {
                anchors.fill: parent
                visible: root.activeTab === "audio"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Text {
                        text: qsTr("Narração Principal:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Theme.panelForeground
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
                                    root.narrationPath = url.toLocalFile ? url.toLocalFile() : url.toString()
                                    CustomProject.analyzeSilence(root.narrationPath, 2.0)
                                }
                            }
                        }
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Atraso inicial da narração:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
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
                            color: Theme.panelForeground
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
                            text: qsTr("Músicas de Fundo (Background Music - até 10 faixas):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMd
                            font.weight: Font.DemiBold
                            color: Theme.panelForeground
                        }
                        Item { Layout.fillWidth: true }
                        ThemedButton {
                            text: qsTr("Adicionar Música")
                            glyph: Theme.icons.fileText
                            onClicked: {
                                const url = FileDialogs.openFile(qsTr("Adicionar Música de Fundo"), qsTr("Arquivos de Áudio (*.mp3 *.wav *.aac *.ogg)"))
                                if (url && url.toString().length > 0) {
                                    const path = url.toLocalFile ? url.toLocalFile() : url.toString()
                                    const list = root.musicList.slice()
                                    list.push({
                                        path: path,
                                        label: "Música " + (list.length + 1),
                                        volumeDb: -17.0,
                                        silenceBoost: true,
                                        boostTargetDb: -3.0,
                                        minSilenceSeconds: 2.0,
                                        rampSeconds: 0.5,
                                        fadeInSeconds: 0.5,
                                        fadeOutSeconds: 0.5
                                    })
                                    root.musicList = list
                                }
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.musicList
                        spacing: Theme.spacingSm
                        clip: true

                        delegate: Rectangle {
                            width: parent.width
                            height: 60
                            color: Theme.panelBackground
                            border.color: Theme.panelBorder
                            border.width: 1
                            radius: Theme.radiusSm

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMd
                                spacing: Theme.spacingMd

                                Text {
                                    text: modelData.label || "Música"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.weight: Font.DemiBold
                                    color: Theme.panelForeground
                                }
                                Text {
                                    text: modelData.path
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.panelMuted
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: "Vol: " + modelData.volumeDb + " dB"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    color: Theme.panelForeground
                                }
                                ThemedCheckBox {
                                    text: qsTr("Silence Boost")
                                    checked: modelData.silenceBoost
                                    onCheckedChanged: {
                                        const list = root.musicList.slice()
                                        list[index].silenceBoost = checked
                                        root.musicList = list
                                    }
                                }
                                ThemedButton {
                                    text: qsTr("Remover")
                                    variant: "ghost"
                                    onClicked: {
                                        const list = root.musicList.slice()
                                        list.splice(index, 1)
                                        root.musicList = list
                                    }
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

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

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
                            text: qsTr("Arquivo Visual do CTA (Vídeo transparente ou imagem):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField {
                                Layout.fillWidth: true
                                text: root.ctaVisualPath
                                onTextChanged: root.ctaVisualPath = text
                            }
                            ThemedButton {
                                text: qsTr("Selecionar...")
                                onClicked: {
                                    const url = FileDialogs.openFile(qsTr("Selecionar Visual CTA"), qsTr("Arquivos de Vídeo ou Imagem (*.mov *.mp4 *.webm *.png)"))
                                    if (url && url.toString().length > 0) {
                                        root.ctaVisualPath = url.toLocalFile ? url.toLocalFile() : url.toString()
                                    }
                                }
                            }
                        }

                        Text {
                            text: qsTr("Efeito Sonoro do CTA (Sino / Chime):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField {
                                Layout.fillWidth: true
                                text: root.ctaBellAudioPath
                                onTextChanged: root.ctaBellAudioPath = text
                            }
                            ThemedButton {
                                text: qsTr("Selecionar...")
                                onClicked: {
                                    const url = FileDialogs.openFile(qsTr("Selecionar Efeito Sonoro CTA"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.ogg)"))
                                    if (url && url.toString().length > 0) {
                                        root.ctaBellAudioPath = url.toLocalFile ? url.toLocalFile() : url.toString()
                                    }
                                }
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Primeira exibição aos:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.panelMuted
                            }
                            ThemedSlider {
                                width: 200
                                from: 60
                                to: 1200
                                value: root.ctaFirstAtSeconds
                                onValueChanged: root.ctaFirstAtSeconds = value
                            }
                            Text {
                                text: Math.round(root.ctaFirstAtSeconds / 60) + " min (" + Math.round(root.ctaFirstAtSeconds) + "s)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.panelForeground
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Intervalo de repetição:")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.panelMuted
                            }
                            ThemedSlider {
                                width: 200
                                from: 120
                                to: 1200
                                value: root.ctaIntervalSeconds
                                onValueChanged: root.ctaIntervalSeconds = value
                            }
                            Text {
                                text: Math.round(root.ctaIntervalSeconds / 60) + " min (" + Math.round(root.ctaIntervalSeconds) + "s)"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.panelForeground
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 5: B-ROLL TEXTUAL
            Item {
                anchors.fill: parent
                visible: root.activeTab === "broll"

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
                                color: Theme.panelMuted
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
                                color: Theme.panelForeground
                            }
                        }

                        RowLayout {
                            spacing: Theme.spacingLg
                            Text {
                                text: qsTr("Intensidade do Escurecimento (Darken):")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                color: Theme.panelMuted
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
                                color: Theme.panelForeground
                            }
                        }

                        Text {
                            text: qsTr("Efeito Sonoro de Teclado Mecânico (Keyboard Typing SFX):")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField {
                                Layout.fillWidth: true
                                text: root.brollKeyboardAudioPath
                                onTextChanged: root.brollKeyboardAudioPath = text
                            }
                            ThemedButton {
                                text: qsTr("Selecionar...")
                                onClicked: {
                                    const url = FileDialogs.openFile(qsTr("Selecionar Som de Teclado"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.ogg)"))
                                    if (url && url.toString().length > 0) {
                                        root.brollKeyboardAudioPath = url.toLocalFile ? url.toLocalFile() : url.toString()
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
                anchors.fill: parent
                visible: root.activeTab === "transitions"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Text {
                        text: qsTr("Transições de Cena:")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMd
                        font.weight: Font.DemiBold
                        color: Theme.panelForeground
                    }

                    RowLayout {
                        spacing: Theme.spacingLg
                        Text {
                            text: qsTr("Modo de Transição:")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            color: Theme.panelMuted
                        }
                        ThemedComboBox {
                            width: 200
                            model: [qsTr("Nenhuma (Corte Seco)"), qsTr("Fixa (Crossfade)"), qsTr("Aleatória (Random)")]
                            currentIndex: root.transitionKind === "fixed" ? 1 : (root.transitionKind === "random" ? 2 : 0)
                            onActivated: (idx) => {
                                root.transitionKind = idx === 1 ? "fixed" : (idx === 2 ? "random" : "none")
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
                            color: Theme.panelMuted
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
                            color: Theme.panelForeground
                        }
                    }

                    Text {
                        text: qsTr("Efeito Sonoro Whoosh (sincronizado nos cortes com transição):")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        color: Theme.panelMuted
                        visible: root.transitionKind !== "none"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.transitionKind !== "none"
                        ThemedTextField {
                            Layout.fillWidth: true
                            text: root.transitionWhooshAudioPath
                            onTextChanged: root.transitionWhooshAudioPath = text
                        }
                        ThemedButton {
                            text: qsTr("Selecionar...")
                            onClicked: {
                                const url = FileDialogs.openFile(qsTr("Selecionar Som Whoosh"), qsTr("Arquivos de Áudio (*.wav *.mp3 *.aac *.ogg)"))
                                if (url && url.toString().length > 0) {
                                    root.transitionWhooshAudioPath = url.toLocalFile ? url.toLocalFile() : url.toString()
                                }
                            }
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
                        color: Theme.panelForeground
                    }

                    ThemedCheckBox {
                        text: qsTr("Adicionar faixa de legendas visíveis na timeline geradas a partir do SRT")
                        checked: root.subtitlesVisible
                        onCheckedChanged: root.subtitlesVisible = checked
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // TAB 7: REVIEW & ASSEMBLE
            Item {
                anchors.fill: parent
                visible: root.activeTab === "review"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLg
                    spacing: Theme.spacingLg

                    Text {
                        text: qsTr("Revisão e Montagem Final do Projeto")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                        font.weight: Font.Bold
                        color: Theme.panelForeground
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMd

                        ThemedButton {
                            text: qsTr("Validar Projeto")
                            glyph: Theme.icons.check
                            variant: "secondary"
                            onClicked: CustomProject.buildPlanSummary(root.syncToProfile())
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: CustomProject.planValid ? qsTr("Plano Válido! Duração Estimada: %1s").arg(Math.round(CustomProject.planDurationSeconds)) : qsTr("Plano Não Validado")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.weight: Font.DemiBold
                            color: CustomProject.planValid ? Theme.success : Theme.warning
                        }
                    }

                    // Validation Messages List
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.appBackground
                        radius: Theme.radiusSm
                        border.color: Theme.panelBorder
                        border.width: 1

                        ListView {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSm
                            clip: true
                            model: CustomProject.validationMessages

                            delegate: Rectangle {
                                width: parent.width
                                height: 36
                                radius: Theme.radiusXs
                                color: modelData.severity === "error" ? Qt.rgba(1, 0.2, 0.2, 0.15) : Qt.rgba(1, 0.7, 0, 0.1)
                                border.color: modelData.severity === "error" ? Theme.destructive : Theme.warning

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingSm
                                    spacing: Theme.spacingMd

                                    IconGlyph {
                                        glyph: modelData.severity === "error" ? Theme.icons.error : Theme.icons.warning
                                        size: Theme.iconSizeMd
                                        color: modelData.severity === "error" ? Theme.destructive : Theme.warning
                                    }

                                    Text {
                                        text: (modelData.sceneNumber > 0 ? ("Cena #" + modelData.sceneNumber + ": ") : "") + modelData.message
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        color: Theme.panelForeground
                                        Layout.fillWidth: true
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
                                    root.saveProjectPath = url.toLocalFile ? url.toLocalFile() : url.toString()
                                }
                            }
                        }
                    }

                    // Big Execute Button
                    ThemedButton {
                        Layout.fillWidth: true
                        height: 52
                        text: qsTr("MONTAR PROJETO PERSONALIZADO NA TIMELINE")
                        variant: "primary"
                        glyph: Theme.icons.wand
                        onClicked: {
                            CustomProject.executeAssembly(AppController, root.saveProjectPath)
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
