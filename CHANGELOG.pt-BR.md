# Changelog

Cada versão é compilada e publicada pelo GitHub Actions a partir de uma tag `v*`.
A versão em inglês, CHANGELOG.md, vira as notas do release.

## [1.1.0] - 2026-10-24

### Novidades

- Atualização dentro do app: o WooferSoundPad procura uma versão nova ao abrir e pergunta antes de instalar qualquer coisa. Um clique baixa, confere o SHA-256, testa se ela abre no seu computador e reinicia na versão nova. Seus sons e configurações continuam do jeito que estão. Dá para desligar nas Configurações.
- Instalação no Linux: um clique (ou `WooferSoundPad --install`) coloca o app no menu de aplicativos com o ícone em todos os tamanhos, ações rápidas (som aleatório, pausar, parar tudo) e o ícone certo no dock. Não precisa de root, e dá para remover nas Configurações ou com `--uninstall`.
- Aba de changelog nas Configurações, em inglês e português.
- Master: equalizador de 3 bandas, compressor e limitador em tudo que os pads tocam. O limitador vem ligado, então pads tocando juntos nunca estouram.
- Efeito global: segure uma tecla e um preset (Rádio, por padrão) cobre tudo que está tocando; um botão deixa ele ligado.
- Saída por pad: os dois, só você (fone) ou só o mic virtual, para deixas que a call nunca ouve.
- Pads que tocam sozinhos, a cada N minutos ou todo dia num horário.
- Vários pads de uma vez: Ctrl+clique (ou Ctrl+A) e mude volume, saída ou efeitos, favorite, mova ou apague todos juntos.
- Desfazer ao apagar: o pad apagado vai para uma lixeira com um botão Desfazer (e Ctrl+Z), no lugar da caixa de confirmação.
- Fatiar nos silêncios: uma gravação longa vira um pad por pedaço, com os cortes mostrados na forma de onda antes de gravar qualquer coisa.
- Pastas monitoradas: arquivos colocados na pasta de um workspace viram pads na hora, e pads cujo arquivo foi apagado somem.
- Busca pela fala (opcional, offline): o whisper.cpp transcreve cada som uma vez, e a busca acha o som pelo que é dito nele.
- QR code do web deck nas Configurações: é só apontar a câmera do celular.
- Instalador para Windows com atalhos no menu Iniciar e na área de trabalho e desinstalador em Configurações > Aplicativos, e um `.deb` para Debian, Ubuntu e Mint.

### Corrigido

- Abrir um menu suspenso (ordem dos pads, escolha de workspace) podia fechar o app, e escolher idioma, ordem ou dispositivo de áudio num menu suspenso podia não ter efeito.
- As Configurações, e mais ainda a aba de changelog, estavam lentas: desenhar e quebrar o texto dava muito mais trabalho que o necessário.

### Mudou

- O `install.sh` do tarball do Linux agora usa o instalador do próprio app, então os dois instalam do mesmo jeito.

## [1.0.1] - 2026-10-24

### Corrigido

- Os binários de Linux da 1.0.0 foram compilados para o processador do servidor de build e fechavam com "Illegal instruction" em muitas CPUs. Agora eles rodam em qualquer processador x86_64, e todo release é testado numa CPU genérica antes de ser publicado. O Windows não foi afetado.

## [1.0.0] - 2026-10-24

A primeira versão pública.

### Tocar

- Soundboard com pads coloridos, forma de onda, LEDs de status, atalhos, etiquetas que mostram o que muda no jeito de tocar, busca, favoritos e quatro ordens.
- Reiniciar, sobrepor ou alternar quando um som que já está tocando é acionado de novo; pausar e continuar tudo com Espaço.
- Fila: Shift+clique, arrastar para reordenar, embaralhar, repetir, tempo restante.
- Atalhos globais no Windows e no X11, comandos para atalhos do desktop no Wayland, teclas 1 a 0.

### Moldar

- Cadeia de efeitos ao vivo por pad, até oito em qualquer ordem: pitch, passa-baixa, passa-alta, rádio, distorção, bitcrusher, eco, reverb, chorus, tremolo, robô e ganho.
- Automação: qualquer parâmetro pode deslizar até um valor final ao longo do som.
- Doze presets prontos (Demoníaco, Esquilo, Robô, Rádio, Caverna, Debaixo d'água, Estourado, Fantasma, Lo-fi, Eco, Desligando, Subindo) e os seus próprios.
- Variantes: vários pads tocando o mesmo arquivo, cada um com seu corte, ajustes e efeitos.
- Editor de forma de onda com zoom, seleção arrastando, clique para ouvir, alças de fade, início e fim exatos, corte automático de silêncio, prévia em loop, desfazer e refazer.
- Nada é destrutivo por padrão; *Salvar corte no arquivo* grava o corte com ffmpeg quando você quiser.

### Apresentar

- Mixer: canal master e um canal por som tocando, com medidor, fader, mudo, fade-out e parar.
- Stage mode (F11): tela cheia, pads enormes, faixa ON AIR e botão de pânico.
- Microfone virtual: um clique no Linux (PipeWire / PulseAudio) com volume e mudo da sua voz, VB-Cable no Windows.
- Servidor de controle local para OBS e Stream Deck: overlay transparente como fonte de navegador, deck web para qualquer navegador ou celular, e uma API HTTP protegida por chave.

### Colecionar

- Explore o MyInstants e o SoundButtonsWorld dentro do app, com prévia e adição em um clique.
- YouTube, SoundCloud e mais de 1000 sites pelo yt-dlp, com corte e normalização de volume opcionais; yt-dlp, ffmpeg e Deno instalam com um clique.
- Gravador: capture o que o computador toca (monitor / loopback WASAPI) ou um microfone, corte o silêncio e transforme em pad.

### Guardar

- Workspaces são pastas comuns com um `workspace.json`.
- Normalização de volume da biblioteca inteira, que liga e desliga; os arquivos nunca mudam.
- Estatísticas: total de toques, tempo tocado, toques de hoje e sequência de dias, ranking de memes, gráfico de 14 dias, histórico.
- 14 temas, inglês e português do Brasil, escala da interface, modo portátil.
