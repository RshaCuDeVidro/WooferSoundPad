<div align="center">

<img src="../assets/logo-mark-128.png" width="88" alt="WooferSoundPad">

# O tutorial do WooferSoundPad

Do zero até soltar sons com efeito na call do Discord em uns dez minutos.

[English](TUTORIAL.md) &nbsp;·&nbsp; [Voltar pro README](../README.pt-BR.md)

</div>

<br>

## Conteúdo

1. [Primeira vez](#1-primeira-vez)
2. [Conhecendo a tela](#2-conhecendo-a-tela)
3. [Workspaces](#3-workspaces)
4. [Trazendo sons](#4-trazendo-sons)
5. [Tocando sons](#5-tocando-sons)
6. [A fila](#6-a-fila)
7. [Editando um som](#7-editando-um-som)
8. [Efeitos, presets e automação](#8-efeitos-presets-e-automação)
9. [Variantes: um arquivo, vários pads](#9-variantes-um-arquivo-vários-pads)
10. [O mixer](#10-o-mixer)
11. [Stage Mode](#11-stage-mode)
12. [Gravando o som do PC](#12-gravando-o-som-do-pc)
13. [Tocando no Discord (microfone virtual)](#13-tocando-no-discord-microfone-virtual)
14. [Atalhos](#14-atalhos)
15. [OBS, Stream Deck e celular](#15-obs-stream-deck-e-celular)
16. [Volume igual e estatísticas](#16-volume-igual-e-estatísticas)
17. [Configurações, temas e modo portátil](#17-configurações-temas-e-modo-portátil)
18. [Dicas](#18-dicas)

<br>

## 1. Primeira vez

1. Baixe o arquivo na [página de Releases](https://github.com/RshaCuDeVidro/WooferSoundPad/releases/latest):
   - **Windows:** `WooferSoundPad-<versão>-windows-x86_64.exe`. Dois cliques. Se o SmartScreen reclamar, *Mais informações → Executar assim mesmo* (o app não é assinado). Prefere tudo numa pasta só? Pegue o `-portable.zip`.
   - **Linux:** `WooferSoundPad-<versão>-linux-x86_64.tar.gz`, extraia e rode `./install.sh` pra ele aparecer no menu de apps. Ou pegue o binário `-linux-x86_64`, dê `chmod +x` e rode.
2. Um tour de cinco passos aparece. Avance ou clique em *Pular*; **F1** abre de novo.
3. O app fala português e inglês e escolhe o idioma do sistema. Troque em *Configurações → Aparência*.

Você começa com um workspace, **My Sounds**, em `~/Music/WooferSoundPad` (Linux) ou `C:\Users\<você>\Music\WooferSoundPad` (Windows).

<br>

## 2. Conhecendo a tela

<p align="center"><img src="screenshots/soundboard.png" alt="O soundboard" width="92%"></p>

- **Barra lateral, em cima:** as páginas. *Soundboard*, *Explorar*, *YouTube e mais*, *Downloads*, *Estatísticas*, *Configurações*: **Ctrl+1** a **Ctrl+6**.
- **Barra lateral, no meio:** seus workspaces, com quantos sons cada um tem.
- **Barra lateral, embaixo:** o transporte. LED de status e o que está tocando, medidor de nível, o **fader master** (volume dos sons nos fones e no mic virtual; nunca mexe no seu mic de verdade), *Pausar* e *Parar*, e o status do mic virtual.
- **Cabeçalho:** o nome do workspace (passe o mouse pra ver o lápis de renomear), quantos pads e atalhos ele tem, e dois botões: **REC** (gravador) e **STAGE** (Stage Mode).
- **Barra de ferramentas:** busca na esquerda; na direita um grupo de quatro botões (só favoritos, som aleatório, painel da fila, mixer), a ordenação e **Importar**.
- **Pads:** cada um mostra o número ou atalho, um LED, a forma de onda, o nome e o tempo. Etiquetas pequenas dizem o que muda o som: **FX2** (dois efeitos ligados), **LOOP**, **CUT** (corte), **1.25x** (velocidade), **VAR** (variante), **Q3** (terceiro na fila).

<br>

## 3. Workspaces

Workspaces são coleções: *Memes*, *Jogos*, *Live*, *Sexta à noite*.

| Pra | Faça |
|---|---|
| Criar | **+** ao lado de *WORKSPACES*, digite o nome, *Criar* |
| Trocar | Clique nele |
| Renomear | Dois cliques, botão direito → *Renomear*, ou o lápis ao lado do nome no cabeçalho |
| Abrir a pasta | Botão direito → *Abrir pasta* |
| Excluir | Botão direito → *Excluir* (apaga os sons também, depois de confirmar) |
| Mover um som | Botão direito no pad → em *MOVER PARA*, escolha o workspace |

Cada workspace é uma **pasta** comum com os áudios e um `workspace.json` (nomes, cores, volumes, atalhos, cortes, efeitos, contagem de plays). Faça backup, sincronize ou compartilhe copiando a pasta.

<br>

## 4. Trazendo sons

- **Arraste e solte** arquivos na janela. Vão pro workspace que está aberto.
- **Importar** (ou **Ctrl+O**) e escolha os arquivos.
- **Explorar** (**Ctrl+2**): MyInstants e SoundButtonsWorld dentro do app. Escolha a fonte, veja os *Em alta*, uma categoria ou busque. **▶** dá a prévia (só você ouve), escolha o destino em *ADICIONANDO EM*, clique em **Adicionar**.
- **YouTube e mais** (**Ctrl+3**): busque no YouTube ou SoundCloud, ou cole um link do YouTube, TikTok, X, Instagram e mais de 1000 sites. Na primeira vez, instale o **yt-dlp** com um clique (e o **ffmpeg** e o **Deno**, recomendados). Clique em *Baixar*, escolha nome, workspace, início e fim opcionais (`12.5` ou `1:05`) e a normalização. O progresso aparece na página *Downloads*.
- **REC** grava o que o PC está tocando. Veja o [capítulo 12](#12-gravando-o-som-do-pc).
- **Na mão:** copie arquivos pra pasta do workspace; aparecem no próximo início.

Formatos: MP3, WAV, OGG, FLAC.

<br>

## 5. Tocando sons

- **Clique num pad.** O LED acende, uma linha de progresso corre embaixo e a forma de onda acende conforme toca.
- **1 … 9, 0** tocam os dez primeiros pads (dá pra desligar nas Configurações).
- **Espaço** pausa tudo; Espaço de novo continua de onde parou. O LED de um pad pausado pisca; clicar nele continua.
- **Esc** para tudo, inclusive a fila.
- O botão **aleatório** toca um pad aleatório do que está na tela (vale a busca e o filtro de favoritos), nunca o mesmo duas vezes seguidas.
- **Ctrl+F** busca; a **estrela** mostra só favoritos; a lista ordena por ordem manual, nome, recém-adicionados ou mais tocados.

Se você disparar um som que já está tocando, *Configurações → Áudio* decide: **Reiniciar** (padrão), **Sobrepor** (outra cópia por cima) ou **Parar** (liga/desliga).

Botão direito num pad abre o menu completo: tocar, pausar, pôr na fila, editar e cortar, efeitos, criar variante, definir atalho, favorito, duplicar, mostrar na pasta, mover, excluir.

<br>

## 6. A fila

Quer sons um depois do outro em vez de todos juntos? **Shift+clique** nos pads, ou botão direito → *Adicionar à fila*. Abra o painel pelo botão da fila na barra de ferramentas. Ligue *Clique no pad = pôr na fila* e cliques normais e atalhos também enfileiram.

<p align="center"><img src="screenshots/queue.png" alt="O painel da fila" width="92%"></p>

| Pra | Faça |
|---|---|
| Voltar / tocar-pausar / pular | Os três botões de transporte |
| Embaralhar o que não tocou | *Embaralhar* |
| Repetir a fila toda | *Repetir a fila* |
| Reordenar | Arraste uma linha |
| Pular pra um som | Clique na linha |
| Tirar um | Passe o mouse e clique no **x** |
| Recomeçar | *Limpar fila* |

O pé do painel mostra o tempo que falta.

<br>

## 7. Editando um som

Botão direito num pad → **Editar e cortar**.

<p align="center"><img src="screenshots/editor.png" alt="O editor" width="92%"></p>

**A forma de onda**

- **Arraste em cima dela** pra escolher o que toca. O resto fica apagado.
- **Arraste as alças brancas** pra ajustar o começo e o fim.
- **Clique em qualquer ponto** pra tocar dali.
- As **alças redondas no topo** são os fades: puxe pra dentro pra fazer fade in e fade out direto na onda.
- **Roda do mouse** dá zoom onde está o ponteiro; **Shift + roda** rola pro lado; os botões em cima aproximam, afastam, mostram tudo ou dão zoom no corte. A faixa embaixo da régua mostra onde você está; arraste pra mover.
- A **varinha** corta o silêncio das pontas. A **seta de desfazer** zera o corte.

**Embaixo da onda**

- **Tocar** (ou **Espaço**) e **Repetir prévia**, que deixa o corte tocando enquanto você mexe.
- **Início** e **Fim**: digite tempos exatos, ajuste de 10 em 10 ms com as setas (100 ms com Shift), ou marque no ponto que está tocando agora.

**As abas**

- **Som:** volume (até 200%), velocidade (0,5x a 2x, muda o tom junto), fade in, fade out, repetir até parar.
- **Efeitos:** a cadeia de efeitos, no próximo capítulo.
- **Pad:** cor, atalho, e informações: o arquivo, plays, tempo tocado, quantos pads usam o arquivo, volume medido.

**Desfaça tudo.** Cada mudança terminada vira um passo. **Ctrl+Z** desfaz, **Ctrl+Shift+Z** ou **Ctrl+Y** refaz, ou use as setas no cabeçalho do editor.

**Nada mexe no seu arquivo.** Corte, velocidade, fades, repetir e efeitos são aplicados enquanto o som toca. Quando quiser o corte no áudio de vez, **Gravar no arquivo** grava com o ffmpeg (e normaliza o volume se isso estiver ligado pros downloads). Se outras variantes usam o mesmo arquivo, esse pad ganha um arquivo próprio e as outras ficam com o original.

<br>

## 8. Efeitos, presets e automação

Botão direito num pad → **Efeitos** (ou a aba *Efeitos* do editor). Tudo toca ao vivo: mexeu com o som tocando, ouviu na hora.

<p align="center"><img src="screenshots/effects.png" alt="A cadeia de efeitos" width="92%"></p>

**Presets.** Os botões no topo são pontos de partida com um clique: Demoníaco, Esquilo, Robô, Rádio, Caverna, Debaixo d'água, Estourado, Fantasma, Lo-fi, Eco, Desligando, Subindo. Clicar troca a cadeia e toca o som pra você ouvir.

**Montando uma cadeia.** *Adicionar efeito* abre a lista dos doze efeitos (cada um entra uma vez na cadeia). A cadeia roda em ordem, até oito efeitos. Em cada cartão:

- a chave liga e desliga sem perder os ajustes,
- as setas movem pra antes ou depois na cadeia,
- **x** remove,
- cada parâmetro tem um slider e um botão de resetar.

| Efeito | O que faz |
|---|---|
| Tom | Mais agudo ou grave, mesma velocidade |
| Passa-baixa / Passa-alta | Abafado / fino |
| Rádio / telefone | Rádio velho, ligação |
| Distorção | Rasgado, estourado |
| Bitcrusher | 8-bit, jogo retrô |
| Eco / Reverb | Repetições / sala, salão, caverna |
| Chorus / Tremolo | Largo e ondulado / volume pulsando |
| Robô | Modulação metálica |
| Ganho | Mais alto ou mais baixo |

**Automação.** Do lado de cada parâmetro tem um botãozinho de gráfico. Ligue e aparece um segundo slider, *No fim*. O parâmetro desliza do primeiro valor pro segundo ao longo do som. Experimente: tom de 0 até −12 mais um passa-baixa de 18 kHz até 300 Hz, o som de máquina desligando. É exatamente o preset *Desligando*.

**Comparar** desliga a cadeia enquanto você escuta, pra ouvir a diferença. **Limpar** esvazia a cadeia.

**Seus presets.** Digite um nome em *Nome do novo preset* e **Salvar**. Ele aparece junto dos prontos em qualquer pad. O **x** no botão do preset apaga.

**Salvar** aplica a cadeia no pad; *Cancelar* (ou fechar o editor) volta como estava.

<br>

## 9. Variantes: um arquivo, vários pads

Uma variante é um segundo pad que toca **o mesmo arquivo** com nome, corte, ajustes e efeitos próprios. Perfeito pra "BRUH" e "BRUH (Demoníaco)" lado a lado, sem duplicar o áudio.

- Botão direito num pad → **Criar variante**, ou **Criar variante** no rodapé do editor.
- A variante aparece do lado da original e abre na aba *Efeitos*.
- Variantes ganham a etiqueta **VAR**. Excluir uma mantém o arquivo enquanto outro pad usar; mover uma pra outro workspace copia o arquivo.

*Duplicar* é diferente: faz uma cópia independente do arquivo.

<br>

## 10. O mixer

O botão do mixer na barra de ferramentas encaixa uma mesinha de som embaixo dos pads.

- **Canal master** (esquerda): fader e medidor geral, **FADE** (abaixa tudo até parar), **STOP**, e a duração do fade (clique pra alternar 0,5 / 1 / 1,5 / 3 / 5 segundos).
- **Um canal por som tocando:** nome, **M** (mudo), **F** (fade-out), **■** (parar), um medidor de LED da saída depois dos efeitos, e um **fader** de 0 a 200% com marca nos 100%. Embaixo, o tempo que falta, ou LOOP / PAUSE.

O fader muda só este play. O volume do pad fica no editor.

Com o mixer fechado, uma bolinha verde no botão dele avisa que tem som tocando.

<br>

## 11. Stage Mode

Aperte **F11**, ou **STAGE** no cabeçalho.

<p align="center"><img src="screenshots/stage.png" alt="Stage Mode" width="92%"></p>

- A janela inteira vira o soundboard: pads gigantes, atalhos legíveis do outro lado do quarto, um LED por pad.
- A faixa **ON AIR** mostra o que está tocando; clique num pra parar só ele. Botão direito num pad também para.
- O mixer fica embaixo (liga e desliga pelo botão de sliders).
- **PARAR TUDO** é o botão vermelho grande. Esc faz o mesmo.
- Os botões de workspace no topo trocam de workspace (quando você tem mais de um).
- Números e atalhos funcionam normal. **F11** ou o botão de minimizar sai.

*Configurações → Aparência → Stage Mode em tela cheia* decide se ele ocupa o monitor inteiro.

<br>

## 12. Gravando o som do PC

Passou algo engraçado num vídeo ou jogo? Pega. Clique em **REC** no cabeçalho.

<p align="center"><img src="screenshots/recorder.png" alt="O gravador" width="80%"></p>

1. **Fonte:** *Áudio do PC (o que você ouve)*, o microfone padrão, ou qualquer dispositivo de entrada.
2. Clique no botão vermelho redondo. O tempo corre, o medidor mexe e a forma de onda vai se desenhando. Toque o que quer pegar.
3. Clique de novo pra parar. *Cortar o silêncio do começo e do fim automaticamente* já tirou o vazio; arraste as alças vermelhas pra ajustar.
4. Dê um nome, escolha o workspace, **Adicionar ao soundboard**. Vira um WAV e abre no editor.

Fechar o diálogo não perde a gravação: ela espera até você adicionar ou descartar. *Gravar de novo* recomeça. Gravações vão até 10 minutos.

No Linux, "áudio do PC" é o monitor da sua saída padrão (PipeWire ou PulseAudio). No Windows, é um loopback WASAPI da saída padrão.

<br>

## 13. Tocando no Discord (microfone virtual)

Cada som toca duas vezes ao mesmo tempo: nos **seus fones** e num **microfone virtual** que o Discord, jogos e apps de call usam como entrada.

**Linux**

1. *Configurações → Microfone virtual*.
2. Deixe *Mixar meu microfone de verdade* ligado, pra continuarem ouvindo sua voz.
3. **Criar mic virtual**. O status fica verde.
4. Discord → *Configurações de usuário → Voz e vídeo → Dispositivo de entrada* → **WooferSoundPad Mic**.
5. Toque um pad. A barra lateral mostra *Mic virtual ligado*.

Com seu mic mixado, *Configurações → Microfone virtual* também tem **Volume da minha voz** (0–150%) e **Mutar minha voz**; o botão de mic na barra lateral muta com um clique, e tem atalho pra isso. Depois de reiniciar o PC, clique em *Criar mic virtual* de novo. Precisa do `pactl` (`pipewire-pulse` ou PulseAudio).

**Windows**

1. Instale o **VB-Cable** (*Baixar VB-Cable* em *Configurações → Microfone virtual*) como administrador e reinicie.
2. *Configurações → Microfone virtual* mostra *VB-Cable detectado*: clique em **Usar**.
3. Entrada do Discord: **CABLE Output (VB-Audio Virtual Cable)**.
4. Pra manter sua voz: *Configurações de som do Windows → Gravação* → seu mic → *Propriedades → Escutar* → *Escutar este dispositivo* pelo **CABLE Input**.

**Volumes:** *Configurações → Áudio* tem volumes separados pros fones, pro mic virtual e pras prévias. Se os efeitos chegarem picotados, abaixe a supressão de ruído do Discord.

<br>

## 14. Atalhos

**Por som:** botão direito → *Definir atalho*, aperte uma combinação como `F5`, `Ctrl+Shift+1` ou `Alt+Num3`. Conflitos são avisados. Atalhos pertencem ao workspace ativo.

**Do app**, em *Configurações → Atalhos*: parar tudo (`Pause` por padrão), pausar / continuar, próximo da fila, som aleatório, mutar minha voz.

**Jogando:** com *Atalhos globais* ligado, funcionam com outro app em foco, no Windows e no Linux com X11.

**Linux com Wayland:** apps não podem ouvir teclas globalmente, então crie um atalho do desktop que roda um comando:

```sh
WooferSoundPad --play "bruh"     # toca um som do workspace ativo
WooferSoundPad --queue "bruh"    # põe na fila
WooferSoundPad --stop            # para tudo
WooferSoundPad --pause           # pausa / continua
WooferSoundPad --next            # próximo da fila
WooferSoundPad --random          # um som aleatório
WooferSoundPad --mute-voice      # muta / desmuta sua voz
```

KDE: *Configurações do Sistema → Teclado → Atalhos → Adicionar novo → Comando ou script*. GNOME: *Configurações → Teclado → Atalhos personalizados*. Hyprland: `bind = SUPER, F1, exec, WooferSoundPad --play "bruh"`. Sway: `bindsym $mod+F1 exec WooferSoundPad --play "bruh"`.

<br>

## 15. OBS, Stream Deck e celular

*Configurações → OBS e Stream Deck* → ligue o **Servidor de controle local**. A seção mostra três links, cada um com botão de copiar.

<p align="center"><img src="screenshots/integrations.png" alt="Configurações de OBS e Stream Deck" width="92%"></p>

- **Overlay do OBS.** No OBS: *Fontes → + → Navegador*, cole o link do overlay, tamanho tipo 600×400. Ele é transparente e mostra cada som enquanto toca, com a cor e uma barra de progresso. Ponha `&align=right` pra alinhar à direita e `&scale=1.5` pra aumentar.
- **Botoneira web.** Abra no navegador e você tem seus pads, troca de workspace, FADE e STOP. Pra usar no celular, ligue *Permitir outros aparelhos da rede* e troque `127.0.0.1` pelo IP do PC.
- **Stream Deck e afins.** Qualquer botão que abre uma URL toca um som. Use o link de comando e mude o final: `name=bruh` toca o BRUH, `/api/stop` para tudo, `/api/fade` dá fade em tudo, `/api/random`, `/api/next`, `/api/stage`. No Stream Deck use uma ação *Website* com *Acessar em segundo plano*, ou um plugin de requisição web.

<p align="center"><img src="screenshots/web-deck.png" alt="A botoneira web" width="80%"></p>

A chave nos links impede que uma página qualquer dispare seus sons. *Nova chave* invalida os links antigos se algum vazar.

<br>

## 16. Volume igual e estatísticas

**Volume igual.** Som da internet vem em todo volume. *Configurações → Áudio → Igualar o volume da biblioteca* mede cada arquivo uma vez e toca todos com a mesma altura (o slider *Volume alvo*, −16 dB por padrão). Nunca faz um som estourar, nunca mexe nos arquivos, e desligar devolve tudo como era. A linha de status mostra quantos sons do workspace já foram medidos; a aba *Pad* do editor mostra o volume de cada um e o ganho aplicado.

**Estatísticas** (**Ctrl+5**): total de plays, tempo tocado, plays hoje e sua sequência de dias, quantos dos seus sons você realmente usa, o ranking dos memes, os últimos 14 dias num gráfico e o histórico de cada play. Alterne entre todos os workspaces e o atual; *Limpar histórico* apaga o histórico e o gráfico.

<p align="center"><img src="screenshots/stats.png" alt="Estatísticas" width="92%"></p>

<br>

## 17. Configurações, temas e modo portátil

| Seção | O que tem |
|---|---|
| Aparência | 14 temas com prévia ao vivo, idioma, tamanho da interface (75–200%), animações, tamanho dos pads, atalhos nos pads, forma de onda nos pads, Stage Mode em tela cheia |
| Áudio | Saída dos fones, saída do mic virtual, os volumes, volume das prévias, o que acontece ao redisparar, normalização da biblioteca |
| Microfone virtual | Criar / remover (Linux) com volume e mute da voz, ou VB-Cable (Windows) |
| Atalhos | Atalhos globais ligados / desligados, os atalhos do app, teclas numéricas, o comando pro Wayland |
| OBS e Stream Deck | O servidor de controle local, porta, acesso pela rede, links, nova chave |
| Biblioteca | Pasta da biblioteca, tamanho do cache e *Limpar cache* |
| Downloads e ferramentas | yt-dlp, ffmpeg, Deno; formato de download, normalização, duração máxima |
| Sobre | Versão, página do projeto, o tour |

**Modo portátil:** ponha um `portable.txt` vazio do lado do executável (o zip portátil do Windows já vem com ele). Configurações, ferramentas, cache, estatísticas e sua biblioteca ficam numa pasta `data` ao lado. Apague o `portable.txt` pra voltar ao normal.

<br>

## 18. Dicas

- **Pânico:** Esc dentro do app, seu atalho de parar tudo em qualquer lugar, o botão vermelho no Stage Mode.
- **Os mesmos sons em todo PC:** aponte *Configurações → Biblioteca* pra uma pasta sincronizada (Syncthing, Dropbox, Nextcloud).
- **Alto demais pra você, certo pra eles:** os volumes dos fones e do mic virtual são separados.
- **Um som quase certo:** faça uma variante e teste à vontade; a original fica intacta.
- **Liberar espaço:** *Configurações → Biblioteca → Limpar cache* apaga prévias e miniaturas.
- **Algo estranho?** As [perguntas frequentes](../README.pt-BR.md#perguntas-frequentes), ou [abra uma issue](https://github.com/RshaCuDeVidro/WooferSoundPad/issues).

Divirta-se, e pega leve com os ouvidos dos seus amigos.
