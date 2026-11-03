# Kanji — local AI dictation for Mac

English · [Português (Brasil)](README.pt-BR.md)

AI dictation for the Mac, in **Portuguese and English at the same time**. Press a shortcut, speak, and the polished text shows up in whatever app you're in: Notes, Slack, Chrome, the Claude chat, a terminal.

Native (Swift, no Electron), free and open source. Transcription happens on your Mac.

> The app's interface is in Brazilian Portuguese for now. This README keeps the exact Portuguese labels and gives the English meaning in parentheses.

## What it does

- **Types where your cursor is.** When you stop, the polished text goes into the focused field. With no field, it lands in the clipboard and in the history.
- **Portuguese and English together.** Two recognizers listen to the same audio, and a word-by-word merge picks up "deploy", "pull request" and "LLM" from English without breaking the Portuguese. Whole sentences in English stay in English: nothing gets translated.
- **Dictated lists become lists.** "Primeiro banana, segundo café… o quarto e o quinto vão ser Ferrari e McLaren" ("First banana, second coffee… the fourth and fifth will be Ferrari and McLaren") becomes a numbered list, in the order you asked for.
- **Two-tier correction:**
  - **On-Mac model** (Apple Intelligence): free and offline. It's small, so it fixes words and punctuation chunk by chunk.
  - **Cloud model, with your own key** (optional): Claude, OpenAI, Gemini, Groq, OpenRouter or any OpenAI-compatible API. It revises the whole dictation when you stop, in ~1.5 s, and understands the context.
- **A glossary that learns.** Every term the cloud correction fixes twice ("Cláudio" → Claude) also starts applying to the on-Mac model, offline.
- **Ignores silence.** An Apple voice detector keeps noise and silence from turning into words you never said.
- **Searchable history** of everything you dictated and copied. Passwords flagged by password managers (1Password, Bitwarden, Keychain) and text that looks like an API key or token are left out. Clipboard history can be turned off.

## Install

> Requirements: Apple Silicon Mac, **macOS 27** or later, and Apple Intelligence turned on. Without Apple Intelligence, dictation works, but without local correction.

**Homebrew** (once the first notarized release is out):
```bash
brew install --cask henriquebap/tap/kanji
```

**Direct download:** get the `.zip` from [Releases](https://github.com/henriquebap/kanji-local-dictation/releases), unzip it and drag `Kanji.app` to Applications.

**Build from source** (only needs the Command Line Tools: `xcode-select --install`):
```bash
git clone https://github.com/henriquebap/kanji-local-dictation.git && cd kanji-local-dictation
make install
```

## Getting started

On first launch, Kanji opens the *Primeiros passos* (Getting started) window. A green ✓ shows what's already allowed:

1. **Microphone:** click *Permitir* (Allow). Audio is transcribed on your Mac.
2. **Accessibility:** click *Abrir Ajustes do Sistema* (Open System Settings) and turn Kanji on in the list. That's what lets it type into the app you're in.
3. **Apple Intelligence:** turn it on in *System Settings › Apple Intelligence & Siri* to get free correction.
4. **Optional, cloud correction:** in *Ajustes › Correção* (Settings › Correction):
   - pick the provider;
   - paste your key (it's stored in the macOS Keychain);
   - click *Testar* (Test).

Then just use it: click a text field, press **⌃⌥D**, speak and press it again. You can reopen the window from the Kanji menu › *Primeiros passos…*.

| Shortcut | What it does | Where to change it |
|---|---|---|
| **⌃⌥D** (global) | Starts recording; press again to stop and type the text | *Ajustes › Geral* (Settings › General) |
| **esc** (while recording) | Cancels | fixed |
| **⌃⌥T** (global) | Opens the Kanji window | *Ajustes › Geral* |
| **⌘Y** | *Histórico* (History) | fixed |
| **⌘,** | *Ajustes* (Settings) | fixed |

*Ajustes › Geral* also holds the "segurar enquanto fala" (hold while you talk) mode and the "escrever enquanto você fala" (type while you talk) mode. In the latter, text appears in the field as you speak, corrected chunk by chunk by the on-Mac model. It's the default mode when no cloud provider is set.

## Privacy

- **Audio never leaves your Mac.** Transcription is done by Apple's on-device `SpeechAnalyzer`.
- **With the on-Mac model,** nothing leaves your computer.
- **With a cloud provider,** only the dictation **text** goes to it, using **your** key and under its terms. Kanji has no server.
- **API keys** are stored in the Keychain.
- **History** lives in `~/Library/Application Support/Kanji`; **settings and glossary** (including learned terms) live in the app's preferences.
- **Clipboard history:** on by default, it keeps what you copy so you can find it later. A password that doesn't come from a password manager also ends up in it. If you copy passwords from other places, turn it off in *Ajustes › Histórico* (Settings › History).

## Languages

Today: **Brazilian Portuguese mixed with English**. Speech recognition already accepts other major languages (*Ajustes › Geral*), but the list rules and the correction were designed and tested only for Portuguese with English. Opening up to other languages is on the roadmap.

## How it works

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) has the full design: the layers, the path from audio to text, what goes to each model and why.

Docs in Portuguese: [README.pt-BR.md](README.pt-BR.md) and [docs/ARCHITECTURE.pt-BR.md](docs/ARCHITECTURE.pt-BR.md).

## Development

```bash
make run       # builds build/Kanji.app and opens it
make install   # copies it to /Applications
make teste     # rule tests (lists, sentence joining, faithfulness, learning glossary)
```

- The build calls `swiftc` directly and works without Xcode. That's why screen state lives in `@Observable` classes, without the `@State` and `@Generable` macros.
- macOS permissions are tied to the app's signature. To avoid being asked again on every build, create a local certificate once with `./scripts/dev-certificate.sh`.
- Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.henriquebap.kanji"' --info`
- Signed and notarized release: [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
- Next steps: [docs/ROADMAP.md](docs/ROADMAP.md).

PRs are welcome. For a big change, open an issue first.

## License

[Apache 2.0](LICENSE). You can use, modify and distribute the code, including commercially, as long as you keep the copyright notice and the [NOTICE](NOTICE). The **Kanji** name and icon are not covered by the license: a published fork needs a different name and icon.
