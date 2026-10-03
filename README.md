# 🎵 MyMusic

> Cifras, acordes e letras para uso ao vivo na igreja — pensado para **tablet** (também roda em celular).

App nativo Android feito em **Flutter**, focado em ser **bonito, rápido e fácil de usar no palco**: marcar músicas, transpor na hora, montar repertórios e virar páginas com um pedal Bluetooth.

![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)
![Plataforma](https://img.shields.io/badge/Android-tablet%20%26%20phone-3DDC84?logo=android&logoColor=white)
![Offline](https://img.shields.io/badge/Offline-first-success)
![Licença](https://img.shields.io/badge/uso-pessoal-lightgrey)

---

## ✨ Recursos

### No palco
- **Modo apresentação** com acorde sobre a letra, alinhamento exato (fonte monoespaçada embutida)
- **Transpor** o tom (+/–) e **capotraste** com um toque
- **Tela cheia** (immersive) — esconde tudo, só a cifra
- **Auto-scroll** com velocidade ajustável + **tela sempre ligada** (wakelock)
- **Pedal Bluetooth** (page-turner): avançar/voltar/rolar — teclas configuráveis
- **Trocar de música** arrastando para o lado (com animação) ou pelo pedal no fim da cifra
- **A– / A+** para ajustar a fonte na hora, sem abrir menus
- **Refrão destacado** e **diagramas de acorde** (toque no acorde para ver a pegada)

### Ao vivo (vários aparelhos)
- **Sessão pela rede Wi-Fi** (pode ser o roteador do celular): um aparelho cria, os outros acham na lista ou digitam o IP
- Quem **conduz** troca de música, muda o tom e rola a tela → quem **segue** acompanha na hora (a música vai junto, mesmo que o outro não tenha)
- **Um condutor por vez** — assumir rebaixa o anterior, com aviso
- Editar música/repertório em qualquer aparelho atualiza os outros; exclusão não se propaga
- Reconecta sozinho se o Wi-Fi cair; tela não apaga durante a sessão

### Organização
- **Biblioteca** com busca **sem acento** e **por trecho da letra**, **tags/categorias** e filtro
- **Repertórios** (setlists) reordenáveis, com **tom salvo por música** e **duplicar**
- Editor **simples**: arraste acordes para a posição certa, ou edite como texto
- **Importar cifra** colada no formato "acorde acima da letra" (Cifra Club, inclusive o bug de copiar/colar do site), ChordPro (`{title}`, `{c:}`, `{soc}`) ou com `Tom:`/`Capo` no texto
- Entende `D7/9`, `Bø`, `B7(4/9)`, marcações `(2x)`, `|`, `N.C.` e seções por extenso (`Refrão:`, `1ª Parte`, `Intro: C G`)
- **Histórico** de tudo o que mudou (o quê, quando, de qual aparelho)
- **Desfazer** (undo) na edição

### Backup & sync
- **Google Drive** (pasta privada `appDataFolder`) com sync automático (baixa, mescla e sobe; mais recente vence; **exclusão se propaga**)
- **Exportar / importar JSON** (backup completo)
- **PDF** (1 ou 2 colunas, encaixa na página), **Word (.docx)**, **imagem** e **TXT só letras** — da música ou do repertório inteiro no tom do repertório

### Grupo compartilhado (nuvem — Firebase)
- Um grupo (banda, coral, ministério...) com a mesma biblioteca para todos, sincronizada na hora e offline
- **Quem cria é o dono**; os outros **sugerem** (o editor vira "Sugerir mudança") e o dono aceita ou recusa vendo a diferença linha a linha
- **Histórico de versões** de cada música (quem, quando, o que mudou) e **voltar a qualquer versão**
- Dono **libera** pessoas por música/repertório ou para tudo dele; repertório dos outros fica só leitura
- Regras de segurança no servidor: [`firebase/firestore.rules`](firebase/firestore.rules) (testes: `cd firebase && npm test`)
- Configurar: [`docs/FIREBASE.md`](docs/FIREBASE.md). Sem configurar, o app segue só com o Drive
- Teste local sem tocar no Google: `cd firebase && npm run emu` e `flutter run --dart-define=MYMUSIC_EMU=10.0.2.2`

### Aparência
- Tema claro/escuro, **8 cores** à escolha, tamanho de fonte ajustável

---

## 🚀 Build & instalação

Pré-requisitos: Flutter (canal stable), JDK 17, Android SDK.

```bash
flutter pub get
flutter build apk --release
```

APK gerado em:
```
build/app/outputs/flutter-apk/app-release.apk
```

Instalar no tablet via USB (depuração ativada):
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
…ou copie o `.apk` para o aparelho e abra (permitir "fontes desconhecidas").

Rodar em modo dev (hot reload):
```bash
flutter run
```

Testes do motor de cifras:
```bash
flutter test
```

---

## ☁️ Configurar o sync com Google Drive (opcional)

1. No [Google Cloud Console](https://console.cloud.google.com): crie um **OAuth Client tipo Android**
   - Pacote: `com.mvini.mymusic`
   - SHA-1 da sua keystore (`keytool -list -v -keystore <keystore>`)
2. Ative a **Google Drive API**
3. Na **tela de consentimento OAuth**: adicione o escopo `.../auth/drive.appdata` e seu e-mail como **usuário de teste**

> O client id **não** vai no código — o Google associa o app por pacote + SHA-1.

---

## 🧱 Arquitetura

```
lib/
├── core/
│   ├── chord_engine.dart   # parser ChordPro + acorde-sobre-letra, transpose, modelo (Dart puro, testado)
│   ├── chord_shapes.dart   # geração de diagramas de acorde (formas móveis E/A)
│   ├── pedal.dart          # mapeamento de teclas do pedal
│   ├── chart_layout.dart   # encaixe em colunas/fonte (compartilhado PDF e DOCX)
│   ├── pdf_export.dart     # PDF / impressão
│   ├── docx_export.dart    # Word
│   └── search.dart         # busca sem acento + trecho da letra
├── live/                   # sessão ao vivo: hub WebSocket + descoberta UDP + tela
├── data/store.dart         # estado global (ChangeNotifier) + persistência JSON
├── models/song.dart        # Song · Section · Line · Chord · Setlist · Settings
├── sync/drive_sync.dart    # login Google + sync Drive (appDataFolder)
└── ui/                     # biblioteca, apresentação, editor, repertórios, configurações
```

O **núcleo de cifras** (`core/`) é Dart puro, sem dependência de UI — fácil de testar e portar.

---

## 🗺️ Roadmap

- [ ] Velocidade de auto-scroll salva por música
- [ ] Opção de seguir sem pegar o tom de quem conduz (ex.: teclado sem capo)

---

<p align="center"><i>Feito com 🎶 para servir.</i></p>
