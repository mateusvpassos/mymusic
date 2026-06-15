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

### Organização
- **Biblioteca** com busca, **tags/categorias** e filtro
- **Repertórios** (setlists) reordenáveis, com **tom salvo por música** e **duplicar**
- Editor **simples**: arraste acordes para a posição certa, ou edite como texto
- **Importar cifra** colada no formato "acorde acima da letra" (Cifra Club) ou ChordPro
- **Desfazer** (undo) na edição

### Backup & sync
- **Google Drive** (pasta privada `appDataFolder`) com sync automático e merge inteligente (mais recente vence)
- **Exportar / importar JSON** (backup completo)
- **Exportar PDF / imprimir** a cifra

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
│   └── pdf_export.dart     # geração de PDF / impressão
├── data/store.dart         # estado global (ChangeNotifier) + persistência JSON
├── models/song.dart        # Song · Section · Line · Chord · Setlist · Settings
├── sync/drive_sync.dart    # login Google + sync Drive (appDataFolder)
└── ui/                     # biblioteca, apresentação, editor, repertórios, configurações
```

O **núcleo de cifras** (`core/`) é Dart puro, sem dependência de UI — fácil de testar e portar.

---

## 🗺️ Roadmap

- [ ] Capo aplicado de verdade na exibição dos acordes
- [ ] Velocidade de auto-scroll salva por música
- [ ] Realce da linha atual durante o auto-scroll
- [ ] Barra com todos os acordes da música + diagramas no topo
- [ ] BPM + metrônomo (tap tempo) → auto-scroll por BPM

---

<p align="center"><i>Feito com 🎶 para servir.</i></p>
