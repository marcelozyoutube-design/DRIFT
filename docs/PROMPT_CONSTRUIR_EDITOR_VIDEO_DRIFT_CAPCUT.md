# Prompt mestre — construir do zero um editor de vídeo profissional no estilo Drift/CapCut

> Copie todo o conteúdo deste documento e use-o como prompt inicial para uma equipe de desenvolvimento ou agente de programação. O objetivo é criar um produto original, sem copiar código, marca, recursos visuais ou ativos proprietários de terceiros, mas com profundidade funcional, fluidez e confiabilidade equivalentes às de um editor moderno da categoria do CapCut.

## 1. Papel e missão

Você é o arquiteto de software, líder técnico, designer de produto, engenheiro multimídia e responsável por qualidade de um editor de vídeo desktop profissional chamado provisoriamente **Drift Studio**.

Construa o produto do zero, de forma incremental e sempre executável. Não entregue apenas telas estáticas ou protótipos. Todo botão visível deve executar uma ação real, apresentar estado de carregamento, concluir com retorno de sucesso ou explicar claramente por que falhou.

O editor deve combinar:

- edição tradicional não linear em timeline, semelhante aos principais editores modernos;
- experiência simples e rápida para criadores de YouTube, documentários e vídeos narrados;
- automação orientada por roteiro/SRT;
- montagem automática de cenas, narração, músicas, CTAs, B-Rolls textuais, transições e legendas;
- preview fiel ao resultado final;
- renderização confiável e reproduzível;
- projeto salvo em formato nativo, legível, versionado e recuperável.

O produto deve funcionar muito bem antes de ganhar novas funções. Priorize integridade de dados, previsibilidade, desempenho, mensagens de erro úteis e testes automatizados.

## 2. Princípios inegociáveis

1. **Nenhum controle decorativo:** todo botão, slider, checkbox, seletor ou atalho deve estar conectado ao modelo e ao motor real.
2. **Preview fiel:** posição, corte, velocidade, escala, opacidade, áudio, texto, efeitos e transições exibidos no preview devem corresponder ao render final.
3. **Estado explícito:** operações longas têm estados `idle`, `validating`, `processing`, `ready`, `running`, `success`, `warning` e `error`.
4. **Retorno visível:** nunca falhar silenciosamente. Exiba mensagem acionável, etapa, arquivo/cena afetada e opção de tentar novamente.
5. **Não destruir trabalho:** autosave, undo/redo, backups rotativos e recuperação após falha são obrigatórios.
6. **Interface responsiva:** nenhuma leitura de arquivo, probe, geração de waveform, thumbnail, proxy ou render pode bloquear a interface.
7. **Operações determinísticas:** a mesma configuração e o mesmo conjunto de mídias devem produzir o mesmo plano e a mesma timeline.
8. **Separação de responsabilidades:** UI não contém regras de montagem; o domínio não depende de elementos visuais; o renderizador consome o mesmo modelo usado pelo preview.
9. **Compatibilidade:** caminhos Unicode, espaços, arquivos longos, diferentes FPS, VFR, áudio mono/estéreo e mídias ausentes devem ser tratados.
10. **Qualidade verificável:** cada módulo só é considerado pronto com testes, logs, critérios de aceite e um fluxo real reproduzível.

## 3. Plataforma e stack recomendada

Crie primeiro a versão Windows x64, mantendo a arquitetura portátil para macOS e Linux.

Stack recomendada:

- C++20 para domínio, timeline, planejamento, cache e integração multimídia;
- Qt 6/QML para a interface desktop acelerada por GPU;
- FFmpeg/FFprobe com versão fixada para demux, decode, encode, filtros e análise;
- OpenGL, Vulkan ou QRhi por meio do Qt para composição do preview;
- SQLite para catálogo, cache e metadados; JSON versionado para o projeto nativo;
- CMake, Ninja e vcpkg/Conan com versões travadas;
- Catch2 ou Qt Test para testes C++; testes QML para interação e Playwright/automação equivalente para fluxos de interface quando aplicável;
- GitHub Actions para Windows, testes, empacotamento e publicação de artefatos.

Não dependa de ferramentas instaladas globalmente. O build deve ser reproduzível em máquina limpa.

## 4. Arquitetura obrigatória

Organize o sistema nestas camadas:

### 4.1. Domínio

Entidades imutáveis ou com mutação controlada:

- `Project`, `Sequence`, `Track`, `Clip`, `MediaAsset`, `AudioClip`, `TextClip`;
- `Transition`, `Effect`, `Keyframe`, `Marker`, `SubtitleCue`;
- `AutomationProfile`, `SceneSlot`, `SceneAction`, `CTAPlan`, `BRollPlan`, `MusicPlan`;
- tempo interno inteiro em microssegundos ou ticks racionais, nunca `float` acumulado;
- IDs UUID estáveis, independentes da posição na lista.

Todas as alterações do projeto devem ser comandos reversíveis: adicionar, remover, mover, cortar, dividir, alterar velocidade, trocar mídia, modificar efeito e atualizar estilo.

### 4.2. Serviços

- importação e identificação de mídia;
- FFprobe e normalização de metadados;
- thumbnails, filmstrips, waveform e proxies;
- decode agendado e cache de frames;
- reprodução de áudio com relógio mestre;
- composição de vídeo/texto/efeitos;
- planejamento automático por SRT;
- validação do plano;
- montagem na timeline;
- exportação e fila de renders;
- autosave, migração e recuperação de projeto;
- telemetria local de desempenho e log técnico, sem coletar conteúdo privado.

### 4.3. View-models/controladores

Exponha modelos observáveis para QML. Nunca altere silenciosamente um objeto dentro de uma lista sem emitir notificação. Para listas editáveis, use `QAbstractListModel` com roles explícitos ou substitua a entrada e emita o sinal correto.

Cada operação assíncrona deve publicar:

- `running`;
- `progress` de 0 a 1;
- `stageLabel`;
- `result` estruturado;
- `errorCode` e `errorMessage`;
- sinal de conclusão emitido tanto em sucesso quanto em falha.

### 4.4. UI

Use componentes reutilizáveis para botões, campos, combos, sliders, cartões, diálogos, toasts, barras de progresso e mensagens vazias. Garanta contraste WCAG AA, foco por teclado, tooltips e áreas de clique adequadas.

## 5. Modelo de projeto nativo

Defina um esquema JSON versionado contendo:

- metadados do projeto, resolução, FPS, sample rate e color space;
- assets com caminho original, hash leve, duração, streams e status;
- sequences, tracks e clips;
- source in/out, início na timeline, duração, velocidade e transformação;
- volume, fades, pan, mute, ducking e efeitos;
- textos, legendas, fontes, cores, contornos, sombras, caixas e animações;
- transições, efeitos e keyframes;
- configurações do Projeto Personalizado;
- cache/proxy apenas por referência, nunca incorporado ao arquivo principal;
- versão do esquema e migrações testadas.

Faça gravação atômica: salvar em arquivo temporário, sincronizar e substituir o destino somente após sucesso. Mantenha backups rotativos.

## 6. Experiência principal do editor

### 6.1. Tela inicial

- novo projeto com presets 16:9, 9:16, 1:1 e personalizados;
- projetos recentes com thumbnail e recuperação;
- importar projeto;
- modelos opcionais;
- aviso claro quando mídia estiver offline.

### 6.2. Biblioteca de mídia

- importar arquivos e pastas em lote por botão, drag-and-drop e colar;
- suportar vídeos, imagens, GIFs, áudios e sequências de imagem;
- mostrar thumbnail, duração, resolução, FPS, codec e status de proxy;
- pesquisar, filtrar, ordenar, favoritar e organizar em pastas/coleções;
- detectar duplicados sem impedir o uso intencional;
- relink de arquivo individual ou pasta inteira;
- processamento em background com progresso e cancelamento.

### 6.3. Timeline multipista

- pistas de vídeo, áudio, texto, legendas, overlays e efeitos;
- drag-and-drop, seleção simples/múltipla, ripple edit e snapping;
- cortar extremidades, dividir no playhead, slip, slide, trim e ripple trim;
- zoom horizontal e vertical, minimapa e rolagem estável;
- playhead preciso, marcadores e range de trabalho;
- lock, mute, solo, visibilidade e reordenação de tracks;
- atalhos configuráveis e operações contextuais;
- thumbnails e waveform progressivos sem travar;
- undo/redo de todas as ações;
- clipes nunca podem ficar com duração negativa ou referências inválidas.

### 6.4. Monitor de preview

- play/pause, frame anterior/seguinte, seek, loop e ajuste à janela;
- timecode atual/total e qualidade de preview configurável;
- reprodução com áudio como relógio mestre;
- prefetch de frames, cache LRU e descarte controlado;
- proxy automático para mídias pesadas;
- overlays interativos para mover, redimensionar, rotacionar e editar texto;
- indicação clara de buffering, mídia offline e erro de decode;
- se o áudio falhar, o preview visual deve continuar e explicar a falha;
- preview parado deve renderizar imediatamente o frame solicitado.

## 7. Ferramentas de edição

Implemente, com preview e render equivalentes:

- transformação, crop, fit/fill, rotação, flip e opacidade;
- blend modes;
- velocidade constante, reverse e curvas de velocidade;
- estabilização e redução de ruído como jobs cacheados;
- correção de cor básica e LUT;
- máscaras e keyframes;
- filtros e efeitos com parâmetros animáveis;
- transições com handles válidos e fallback explicado;
- congelar frame e remover fundo quando disponível;
- títulos, lower thirds, shapes, stickers e overlays;
- presets salváveis pelo usuário.

## 8. Áudio profissional

- waveform correta e sincronizada;
- ganho em dB, volume por clipe, pan, mute/solo e fades;
- medidor de pico/RMS e prevenção de clipping;
- normalização opcional por LUFS;
- ducking automático da música sob narração;
- redução de ruído, compressor, EQ e limiter;
- preview individual de narração, música e efeitos;
- importação de várias músicas de uma vez;
- distribuição automática de N músicas por todas as cenas, sem lacunas e sem sobreposição acidental;
- botão “Aplicar volume a todas”, atualizando o modelo, os controles e o plano;
- preservar a posição de rolagem ao editar uma música;
- mostrar confirmação: quantidade alterada, faixa de cenas e volume aplicado;
- validar arquivos ausentes e durações insuficientes antes da montagem.

Teste especificamente listas grandes: alterar volume no item 40 não pode mover a rolagem para o topo.

## 9. Texto e legendas

- importar SRT, VTT e texto transcrito;
- editar cues em lista e diretamente na timeline;
- estilos com lista de fontes instaladas e presets populares;
- tamanho, peso, itálico, alinhamento, cor, contorno, sombra e caixa;
- posição e safe areas;
- animações de entrada/saída: fade, slide, pop, rise, bounce, wave e typewriter;
- preview dedicado em canvas 16:9/9:16 com fundo de vídeo ou imagem de amostra;
- botão play/pause e scrubber da animação;
- avisar quando uma fonte não estiver instalada e oferecer substituição;
- opção de queimar legenda no vídeo ou criar pista editável.

O preview de legenda deve usar exatamente o mesmo style model e o mesmo compositor do render final.

## 10. Projeto Personalizado orientado por SRT

Crie um assistente de sete etapas. Ele não é apenas um formulário: cada etapa altera um plano estruturado que pode ser inspecionado antes da montagem.

### Etapa 1 — Cenas e mídias

- selecionar pasta primária, secundária e SRT;
- botão “Escanear pastas” funcional, recursivo e assíncrono;
- reconhecer número de cena pelo nome do arquivo;
- listar conflitos, ausências e duplicatas;
- permitir override manual;
- exibir tabela com cena, texto SRT, mídia, tempo original, tempo planejado e origem;
- botão “Processar e ajustar ao SRT” com progresso e resultado;
- nunca exibir texto escuro em fundo escuro nem cinza ilegível.

### Etapa 2 — Ajuste e Ken Burns

- para vídeo maior que a cena: cortar início, centro ou fim;
- para vídeo próximo da duração: ajustar velocidade dentro de limites configuráveis;
- para imagem: Ken Burns opcional;
- para falta de mídia: preservar gap ou aplicar política configurável;
- exibir antes/depois, velocidade e source in/out.

### Etapa 3 — Narração e músicas

- narração com preview, atraso e volume;
- múltiplas músicas adicionadas em lote;
- preview por música;
- volume, fades, loop e intervalo de cenas;
- distribuir todas as músicas proporcionalmente entre as cenas;
- aplicar o mesmo volume a todas;
- manter rolagem e foco ao alterar parâmetros;
- confirmar visualmente cada operação.

### Etapa 4 — CTA recorrente

- aceitar GIF, imagem e vídeo, inclusive alpha quando suportado;
- som separado com volume e offset;
- primeira ocorrência, intervalo, duração e opacidade;
- preview autocontido em canvas, sem depender da timeline principal;
- para imagem estática, animar entrada/escala/opacidade para deixar a execução evidente;
- para GIF/vídeo, reproduzir do primeiro frame;
- mostrar progresso, play/pause, status de carregamento e erro;
- tocar o som no offset real;
- listar ocorrências calculadas na duração do projeto.

### Etapa 5 — B-Rolls textuais

- quantidade e distribuição configuráveis;
- usar texto dos cues selecionados;
- escurecer a mídia de fundo e executar typewriter;
- som de teclado opcional;
- preview grande, com proporção correta e controles fora da imagem;
- mostrar cena, timecode, duração e índice da ocorrência;
- navegar anterior/próximo;
- texto deve aparecer em velocidade legível; permitir desacelerar ou repetir;
- usar o mesmo frame/corte/velocidade planejados para a cena;
- preview não pode ficar espremido por outros campos; use área rolável ou painel dedicado.

### Etapa 6 — Transições e legendas

- escolher transição fixa, aleatória ou nenhuma;
- duração e whoosh opcionais;
- configurações completas de legenda;
- lista de fontes populares instaladas;
- preview dedicado e animado da legenda;
- validar handles e reduzir transição com aviso quando necessário.

### Etapa 7 — Revisão e montagem

- botão “Executar etapas 1–6” que carrega SRT, escaneia mídia, resolve o plano, calcula áudio/CTA/B-Roll/transições/legendas e publica progresso por etapa;
- somente depois habilitar “Validar e analisar”;
- validação deve retornar erros e avisos estruturados, nunca “inválido com 0 erros”;
- cartões com total, cortadas, aceleradas, exatas, estendidas, gaps, CTAs e B-Rolls;
- tabela com ação por cena, tempo original, tempo final, velocidade e source in/out;
- monitor com play visível, largura mínima, scrubber e preview que avança mesmo sem narração;
- montagem na timeline deve ser transacional: preparar, validar, aplicar e confirmar;
- não fechar a janela em falha;
- em sucesso, informar quantidade de clips/tracks criados e oferecer “Fechar e ver timeline”;
- em falha, informar etapa, erro e contexto técnico copiável.

## 11. Planejador automático

Implemente o planejador como função pura sempre que possível:

`PlanResult buildPlan(ProjectInput input, AutomationProfile profile)`

O resultado deve conter:

- `isValid`, `errors[]`, `warnings[]`;
- duração total;
- `sceneActions[]`;
- `musicActions[]`;
- `ctaActions[]`;
- `brollActions[]`;
- `subtitleActions[]`;
- métricas agregadas;
- hash das entradas para detectar plano desatualizado.

Regras importantes:

- cada cue SRT define um slot de cena;
- calcule duração em tempo inteiro;
- escolha mídia determinística;
- respeite overrides e locks;
- corte ou retime dentro dos limites;
- não esconda gaps;
- músicas respeitam cenas e duração total;
- CTAs nunca ultrapassam o final;
- B-Rolls apontam para cenas válidas;
- transições respeitam handles;
- mensagens incluem severidade, código, cena e solução sugerida.

## 12. Montagem transacional na timeline

Antes de alterar a timeline:

1. capture snapshot/undo macro;
2. confirme que o plano exibido ainda corresponde às configurações atuais;
3. valide todos os caminhos;
4. crie tracks temporárias;
5. monte cenas e transformações;
6. adicione narração e músicas;
7. adicione CTAs e sons;
8. adicione B-Rolls;
9. adicione transições e legendas;
10. verifique invariantes;
11. faça commit atômico;
12. em qualquer falha, restaure o snapshot e reporte o erro.

O comando deve retornar um objeto como:

```json
{
  "success": true,
  "message": "Projeto montado com sucesso",
  "created": {
    "tracks": 8,
    "sceneClips": 120,
    "musicClips": 4,
    "ctas": 3,
    "brolls": 5,
    "subtitles": 120
  },
  "warnings": []
}
```

## 13. Exportação

- presets YouTube 1080p/1440p/4K, Shorts, Instagram e personalizados;
- H.264/H.265/AV1 conforme disponibilidade;
- bitrate/CRF, FPS, resolução, áudio e hardware encoding;
- range completo ou work area;
- fila, pausa/cancelamento e progresso com ETA;
- arquivo temporário seguido de rename atômico;
- validação pós-render com FFprobe;
- log de encode e opção de abrir pasta;
- testes comparando duração, streams, frames e sincronismo.

## 14. Desempenho

- jobs em thread pool com prioridades;
- preview prioriza frame atual; thumbnails nunca bloqueiam playback;
- cache em memória com orçamento e cache em disco versionado;
- proxies para 4K/HEVC/VFR;
- invalidação granular ao editar;
- evitar recriar modelos QML inteiros por alteração de campo;
- virtualizar listas longas;
- medir frame time, dropped frames, decode latency e consumo de memória;
- metas: UI abaixo de 16 ms na maior parte das interações e playback estável em proxy.

## 15. Logs e diagnóstico

Implemente log estruturado com timestamp, categoria, operação e contexto, removendo dados sensíveis quando exportado. Inclua uma tela “Diagnóstico” para:

- versões do app, Qt e FFmpeg;
- GPU e backend de render;
- codecs disponíveis;
- caminhos de cache;
- últimos erros;
- copiar relatório;
- testar decode, áudio e escrita em disco.

Mensagens ao usuário devem ser simples; detalhes técnicos ficam expansíveis.

## 16. Testes obrigatórios

### Unidade

- conversão de tempo e timecode;
- parsing SRT/VTT;
- escolha de cenas;
- corte e velocidade;
- distribuição de música;
- recorrência de CTA;
- seleção de B-Roll;
- validação e mensagens;
- serialização/migração;
- undo/redo.

### Integração

- importar mídia real de amostra;
- gerar plano com todos os recursos;
- montar timeline e verificar clips/tracks;
- salvar/reabrir sem perda;
- preview e render no mesmo timecode com tolerância definida;
- exportar arquivo e validar com FFprobe.

### Interface

- clicar cada botão e verificar mudança de estado;
- scroll de lista de músicas permanece estável;
- adicionar arquivos em lote;
- CTA toca e progride;
- B-Roll digita o texto de forma visível;
- legenda reflete fonte/cor/contorno/animação;
- review play avança sem e com narração;
- erros aparecem com texto útil;
- montagem bem-sucedida cria a timeline e montagem inválida não altera nada.

### Regressão visual

- temas claro e escuro;
- escalas de 100%, 125%, 150% e 200%;
- resoluções mínimas e 4K;
- contraste e clipping de textos;
- snapshots dos previews principais.

## 17. Pipeline e distribuição

Para cada commit:

1. formatar e analisar estaticamente;
2. compilar em modo Release com warnings relevantes tratados;
3. executar testes unitários e de integração;
4. executar smoke test do aplicativo;
5. empacotar runtime e codecs permitidos;
6. criar instalador Windows x64 e pacote portátil;
7. gerar SHA-256;
8. assinar digitalmente quando houver certificado;
9. publicar artefatos associados ao commit;
10. embutir versão e hash curto no título/diagnóstico.

O instalador deve permitir instalar, atualizar e desinstalar sem apagar projetos do usuário.

## 18. Plano de implementação incremental

### Marco 1 — Fundação executável

Shell, projeto nativo, importação, uma timeline, preview básico, save/load e export simples.

### Marco 2 — Edição confiável

Trim, split, múltiplas tracks, áudio, texto, undo/redo, cache, waveform e proxies.

### Marco 3 — Acabamento criativo

Efeitos, transições, keyframes, legendas, animações e presets.

### Marco 4 — Projeto Personalizado

Sete etapas completas, planejador, previews dedicados, validação e montagem transacional.

### Marco 5 — Qualidade de produto

Otimização, acessibilidade, recuperação, diagnóstico, testes de regressão, instalador e assinatura.

Não avance de marco se o anterior não tiver um fluxo real demonstrável e testes verdes.

## 19. Forma de trabalho exigida do agente/equipe

Antes de editar:

- examine o repositório e documente a arquitetura atual;
- identifique o caminho completo UI → view-model → domínio → timeline/render;
- reproduza o defeito com projeto mínimo;
- encontre a causa, não apenas o sintoma.

Ao implementar:

- faça mudanças pequenas e rastreáveis;
- preserve compatibilidade do projeto;
- não remova funções existentes para simplificar;
- conecte todos os sinais e resultados;
- adicione mensagens e testes;
- mantenha o aplicativo compilável.

Ao entregar cada tarefa, informe:

- causa raiz;
- arquivos alterados;
- comportamento antes/depois;
- testes executados;
- limitações restantes;
- link do instalador;
- versão/commit e SHA-256.

## 20. Definição global de pronto

O produto só está pronto quando um usuário consegue, em máquina limpa:

1. instalar o aplicativo;
2. criar um projeto;
3. importar centenas de mídias;
4. editar manualmente com timeline fluida;
5. configurar um Projeto Personalizado por SRT;
6. visualizar individualmente narração, músicas, CTA, B-Rolls e legendas;
7. executar etapas 1–6;
8. validar e entender todos os avisos;
9. reproduzir a montagem na revisão;
10. montar a timeline sem falha silenciosa;
11. ajustar o resultado manualmente;
12. salvar, fechar e reabrir sem perda;
13. exportar o vídeo final sincronizado;
14. obter mensagem clara e recuperação segura em qualquer erro.

Crie um produto original, sólido e agradável. Profundidade funcional e confiabilidade têm prioridade sobre quantidade de botões. Nenhuma etapa será aceita com interface simulada, dados fictícios, handlers vazios ou sucesso presumido.

