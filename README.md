# Kanji — local AI dictation for Mac

English · [Português (Brasil)](README.pt-BR.md)

AI dictation for the Mac, in **Portuguese and English at the same time**. Press a shortcut, speak, and the polished text shows up in whatever app you're in: Notes, Slack, Chrome, the Claude chat, a terminal.

Native (Swift, no Electron), free and open source. Transcription happens on your Mac.

> The interface follows your Mac's language: English or Brazilian Portuguese. The labels below are the English ones.

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

Kanji is free. It isn't part of Apple's paid developer program (US$ 99/year) yet, so it can't be notarized by Apple. Notarization is the check that lets an app open without warnings. Until then there are two free ways to install it: building it yourself (no warnings at all), or downloading the ready-made app and approving it once.

> **Requirements:** Apple Silicon Mac, **macOS 27** or later. Turn on Apple Intelligence for the free local correction; without it, dictation still works, uncorrected.

### Option A: build it yourself (recommended)

**Goal:** compile Kanji on your own Mac. macOS trusts what you built yourself, so there is no security warning, and updating is one command.

1. **Install Apple's command-line tools.** They include the Swift compiler (about 1 GB; the full Xcode isn't needed).
   ```bash
   xcode-select --install
   ```
2. **Download the code.**
   ```bash
   git clone https://github.com/henriquebap/kanji-local-dictation.git && cd kanji-local-dictation
   ```
3. **Create a local signing certificate.** This step is optional but recommended. macOS ties the Microphone and Accessibility permissions to the app's signature. With this certificate, every update keeps your permissions; without it, macOS asks again after each update. The script asks for your Mac password once.
   ```bash
   ./scripts/dev-certificate.sh
   ```
4. **Build and install.** This compiles the app, copies it to Applications and opens it.
   ```bash
   make install
   ```

**To update later:** `git pull && make install`.

### Option B: download the ready-made app

**Goal:** skip compiling. Because the app isn't notarized, macOS blocks the first launch and you approve it once.

1. **Download** `Kanji-X.Y.Z.zip` from [Releases](https://github.com/henriquebap/kanji-local-dictation/releases), unzip it and drag `Kanji.app` to Applications.
2. **Open Kanji.** macOS says it can't verify the developer. Click **Done**, not *Move to Trash*. This is Gatekeeper, which blocks every downloaded app that Apple hasn't notarized.
3. **Approve it.** Open *System Settings › Privacy & Security*, scroll to **Security**, and click **Open Anyway** next to "Kanji was blocked". Confirm with your password. This tells macOS you trust this specific app, and you only do it once per downloaded version.

   The button only shows up for a while after a blocked launch. If you don't see it, open Kanji again and go straight back to Settings.

> **Homebrew:** since Homebrew 5, casks must be notarized by Apple, so `brew install` will only be available once Kanji joins Apple's program.

## Getting started

On first launch, Kanji opens the *Getting Started* window. It lists what macOS needs to allow and why; a green ✓ shows each step that's done:

1. **Microphone.** *Goal:* let Kanji hear you, only while the shortcut is active. Click *Allow*. Audio is transcribed on your Mac and never leaves it.
2. **Accessibility.** *Goal:* let Kanji put the text into the app you're using. Click *Open System Settings* and turn Kanji on in the list.
3. **Apple Intelligence.** *Goal:* free, offline correction of what you dictate. Turn it on in *System Settings › Apple Intelligence & Siri*.
4. **Cloud correction (optional).** *Goal:* a better correction of the whole text (lists in the order you asked, names, jargon) using your own API key. In *Settings › Correction*:
   - pick the provider;
   - paste your key (it's stored in the macOS Keychain);
   - click *Test*.
5. **Try it.** *Goal:* check that everything works. Click any text field, press **⌃⌥D**, speak, and press **⌃⌥D** again; the text appears where your cursor is.

You can reopen this window anytime from the Kanji menu › *Getting Started…*.

| Shortcut | What it does | Where to change it |
|---|---|---|
| **⌃⌥D** (global) | Starts recording; press again to stop and type the text | *Settings › General* |
| **esc** (while recording) | Cancels | fixed |
| **⌃⌥T** (global) | Opens the Kanji window | *Settings › General* |
| **⌘Y** | *Show History* | fixed |
| **⌘,** | *Settings* | fixed |

*Settings › General* also holds the "Hold while you talk" mode and the "Type while you talk" option. In the latter, text appears in the field as you speak, corrected chunk by chunk by the on-Mac model. It's the default mode when no cloud provider is set.

## Privacy

- **Audio never leaves your Mac.** Transcription is done by Apple's on-device `SpeechAnalyzer`.
- **With the on-Mac model,** nothing leaves your computer.
- **With a cloud provider,** only the dictation **text** goes to it, using **your** key and under its terms. Kanji has no server.
- **API keys** are stored in the Keychain.
- **History** lives in `~/Library/Application Support/Kanji`; **settings and glossary** (including learned terms) live in the app's preferences.
- **Clipboard history:** on by default, it keeps what you copy so you can find it later. A password that doesn't come from a password manager also ends up in it. If you copy passwords from other places, turn it off in *Settings › History*.

## Languages

Today: **Brazilian Portuguese mixed with English**. Speech recognition already accepts other major languages (*Settings › General*), but the list rules and the correction were designed and tested only for Portuguese with English. Opening up to other languages is on the roadmap.

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
- Publishing a free release (and the paid Apple path for later): [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).
- Next steps: [docs/ROADMAP.md](docs/ROADMAP.md).

PRs are welcome. For a big change, open an issue first.

## License

[Apache 2.0](LICENSE). You can use, modify and distribute the code, including commercially, as long as you keep the copyright notice and the [NOTICE](NOTICE). The **Kanji** name and icon are not covered by the license: a published fork needs a different name and icon.
