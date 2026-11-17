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
- **Transcribes what the Mac plays.** A video, a podcast or a meeting, in the background, into a Markdown and a JSON file. On a call your own voice joins as "Você" ("You"); with the optional voice model, the other voices become "Locutor 1, 2…" ("Speaker 1, 2…"). See [Transcribing the Mac's audio](#transcribing-the-macs-audio).

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
| **⌃⌥K** (global) | Opens the Kanji window | *Settings › General* |
| **⌃⌥M** (global) | Starts transcribing the Mac's audio; press again to stop and save | *Settings › General* |
| **⌘Y** | *Show History* | fixed |
| **⌘,** | *Settings* | fixed |

Every global shortcut is **⌃⌥ + a letter**: **D** for dictate, **M** for Mac audio, **K** for Kanji. macOS doesn't use ⌃⌥ + letter, so they don't take a shortcut away from another app. When you record a new one, Settings only accepts combinations with ⌃⌥.

*Settings › General* also holds the "Hold while you talk" mode and the "Type while you talk" option. In the latter, text appears in the field as you speak, corrected chunk by chunk by the on-Mac model. It's the default mode when no cloud provider is set.

## Transcribing the Mac's audio

Press **⌃⌥M** (or *Transcribe Mac Audio* in the menu) and Kanji transcribes everything the Mac plays, minus its own sounds, whether you use headphones or speakers. Press it again to stop.

- **First time:** a notice reminds you to tell people before transcribing a meeting, and macOS asks for *System Audio Recording* (*System Settings › Privacy & Security*). It's narrower than Screen Recording: Kanji never sees the screen.
- **Reading and using it:** *Open Transcripts* in the menu opens the Kanji window on **Transcripts**: every session with its date, length and speakers. In a session you can *Copy* it (Markdown, ready to paste into a doc or a chat), *Rename* a speaker ("Locutor 1" → a name, in every paragraph and file), *Show in Finder* or move it to the Trash. The search field searches the transcripts too.
- **Summarize:** sends the transcript **text** to the cloud provider set in *Settings › Correction* (your key) and returns a summary, key points with their times, decisions and tasks, in the transcript's main language (an English podcast gets an English summary; nothing is translated). It's saved next to the transcript as `… resumo.md`. The on-Mac model can't do it: its context is too small for an hour of conversation.
- **Feedback:** for a job interview recorded during a call. You are "Você" (the microphone), the interviewers are the Mac's audio. It returns a summary, your strengths, what to improve (your introduction, how you explained each project, answers without a concrete example or a result) with a better phrasing to try, and each interviewer question rated good, partial or weak. Suggested phrasings never invent facts: what you didn't say stays as a gap in brackets, like `[how much time it saved]`. Same language rule as the summary, so an interview in English gets feedback in English. Saved as `… entrevista.md`.
- **Files:** one `.md` and one `.json` per session in `~/Library/Application Support/Kanji/Transcricoes`. They're saved segment by segment, so a crash keeps what was already transcribed. Each paragraph has the time and who spoke.
- **Calls:** when another app (Zoom, Meet, Teams, FaceTime) opens the microphone, Kanji adds the microphone to the session by itself, with echo cancellation, and labels it "Você". It turns it off 10 s after the call releases the microphone. A video doesn't open the microphone, so the room's sound stays out.
- **Who spoke (optional):** *Settings › General › Mac Audio Transcription › Tell speakers apart* downloads a ~15 MB voice model once (WeSpeaker ResNet34 converted to Core ML, CC BY 4.0, from Hugging Face), checked by SHA-256. Without it, everything the Mac plays is labeled "Outros" ("Others").
- **Notch:** if Kizami (a sibling app that draws an island around the notch) is running, its island shows that Kanji is transcribing, when a call adds your microphone, and when the transcript is saved. Only the state and counts go there, never the text.
- **Resources:** on a 5-minute podcast, Kanji used ~8.5% of one core and ~70 MB; Apple's speech service, another ~11% and up to ~200 MB.

## Privacy

- **Audio never leaves your Mac.** Transcription is done by Apple's on-device `SpeechAnalyzer`.
- **With the on-Mac model,** nothing leaves your computer.
- **With a cloud provider,** only the dictation **text** goes to it, using **your** key and under its terms. Kanji has no server.
- **API keys** are stored in the Keychain.
- **Mac audio transcripts** stay in `~/Library/Application Support/Kanji/Transcricoes`. The audio is never saved or sent; the voice model is downloaded only if you turn on *Tell speakers apart*.
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
