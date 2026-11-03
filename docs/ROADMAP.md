# Roadmap

Summary of the research from 2026-11-03: market, system audio capture and agent mode.

## Positioning

**The market:**
- **Cloud subscriptions** at US$ 12–15/month: Wispr Flow, Willow, Monologue.
- **Local Whisper apps** as one-time purchases of US$ 25–80: VoiceInk, MacWhisper, BetterDictation.
- **Open source that downloads a model:** Handy (37k★, Tauri), FluidVoice (12.7k★), OpenWhispr (10.6k★, Electron), VoiceInk (7k★, but doesn't accept PRs).

**Same stack as ours (SpeechAnalyzer + Foundation Models):**
- Yap (465★)
- Megaphone (180★, inactive since Jul/2026)

Nobody dominates, but the space isn't empty. **The differentiator has to come from execution:**
1. **First-class pt-BR, mixed with English.** Every competitor is designed for English. The PT+EN fusion, with two `SpeechTranscriber`s on the same audio, handles technical jargon without the cloud.
2. **Dictation and clipboard in one app.** Today you have to combine VoiceInk with Maccy.
3. **Truly open source**, accepting PRs.
4. **Zero download, zero cost, native and lightweight.**

**Honest risks:**
- There's no public SpeechAnalyzer benchmark for pt-BR.
- The local model (~3B, 8k-token context) sometimes replies to the text instead of correcting it.
- Requires Apple Intelligence.

## Real pain points v1 needs to solve

| Pain point | How to solve it |
|---|---|
| Pasting fails in terminals and secure fields, and the clipboard gets clobbered | Save and restore the clipboard; a dedicated paste shortcut for terminals; detect Secure Input and warn |
| Jargon comes out wrong ("cloud code") | Personal substitution dictionary applied after transcription |
| The LLM "chats" instead of correcting | Timeout, validation (discard the output if it drifts too far from the original) and fallback to the raw text |
| Permission denied with no explanation | Permission onboarding with diagnostics |
| Passwords leaking into history | Already ignores the Concealed/Transient types; still missing an excluded-apps list and token detection |

## Product model (decided on 2026-11-03)

- **Open source (Apache 2.0) and a free app.** The name and icon stay with the author (see `NOTICE`).
- **Free forever:**
  - transcription on the Mac;
  - review with the Mac's model;
  - cloud review with the user's own key;
  - a glossary that learns;
  - history.
- **Cheap subscription in the future (R$ 5–10/month):** cloud review without needing a key, plus new features.
  - Requires our own server (proxy with accounts, per-user limits and billing), because the author's key never ships inside the app.
  - The API credits that come with the Max plan can power a product that is sold, but the service can't depend on them alone: when they run out, the API stops. It needs purchased credits or auto-reload behind it.
- **Distribution:** notarized download + Homebrew first, Mac App Store and iPhone later ([DISTRIBUTION.md](DISTRIBUTION.md)).

## Phases

### v0.1: usable dictation (built, still needs validation in real use)
Live typing into the focused field (Accessibility) with a compact panel, or text in the panel when there's no field; Portuguese + English with word-by-word fusion and a personal glossary; streaming correction with validation, pasting with clipboard restore, configurable global shortcuts (dictate and open), esc to cancel, an app with a main window and icon, status sounds, searchable dictation and clipboard history.

### Done on 2026-11-03
- Cloud review with multiple providers: Claude, OpenAI, Gemini, Groq, OpenRouter and any OpenAI-compatible API.
- "Only at the end" mode, pasting with ⌘V, which works in every app.
- A glossary that learns from the cloud review.
- Voice detector against words invented during silence.
- Getting-started window with the permissions.
- Filter for keys and tokens in the clipboard history.
- UI localization: English and Brazilian Portuguese, following the Mac's language (`.lproj` tables; prompts and rule word lists stay in Portuguese).

### v0.2: polish (what separates a toy from a product)
- Correction timeout
- Apps excluded from history
- Benchmark: 30–50 real pt-BR recordings, measuring WER against Whisper large-v3 and Parakeet. It would be a number no competitor publishes.

### v0.3: transcribe what the Mac is playing (meetings, videos)
- **Capture:** Core Audio process taps (`AudioHardwareCreateProcessTap`, Swift API `AudioHardwareSystem.shared.makeProcessTap`). Only asks for the "System Audio Recording" permission, narrower than Screen Recording, and can filter by app (`bundleIDs`). Avoid ScreenCaptureKit (requires screen permission) and virtual drivers.
- **Live:** `SpeechAnalyzer.start(inputSequence:)` with `AsyncStream<AnalyzerInput>` and the `.progressiveTranscription` preset. Volatile text shows in gray and final text in black. On macOS 27, `AnalyzerInputConverter` removes the need for a manual `AVAudioConverter`.
- **Me × Others:** two transcribers, one on the microphone and one on the tap, interleaved by `audioTimeRange`. There's no native diarization.
- **Requirements:** `NSAudioCaptureUsageDescription` (without it the tap records silence, with no error), a stable signature (Developer ID) so TCC doesn't forget the permission, and a consent notice: recording a meeting has LGPD implications when it's work.
- **Limit:** the local context is 8k tokens, so summarizing a 1 h meeting requires Claude (v0.4).

### v0.4: agent mode (opt-in)
- **Integration:** the official package [`anthropics/ClaudeForFoundationModels`](https://github.com/anthropics/ClaudeForFoundationModels) implements the `LanguageModel` protocol. The same `LanguageModelSession` switches between the local model and Claude via Dynamic Profiles. It's in beta and requires Xcode 27.
- **Routing:** the local model only **classifies** the intent into a closed enum, and a table in code decides the route:

  | Route | When |
  |---|---|
  | Local | Correct, extract, a simple tool |
  | Claude Haiku 5.5 | One step with tools |
  | Claude Sonnet 5.5 | Multiple steps, meeting minutes |

  Without a key or credits, the request degrades to the local model or to a pending queue. **Regular dictation never goes through the agent.**
- **Tools v1:**
  - Read-only, no confirmation: search history, translate (Translation framework).
  - With side effects, always confirmed: create an event or reminder (EventKit), create a note.
  - Run a user shortcut that is on an allowlist: extensibility for free.
- **Security:**
  - Transcription and clipboard are **data**, never instructions.
  - Confirmation happens inside the tool's `call()`, where the model has no way to skip it.
  - The key stays in the Keychain. Audio and the full history never leave the Mac.
- **Gimmick to avoid:** "translate what I copied" is faster with a fixed shortcut than with an agent.

## Pending decision: install Xcode

The Command Line Tools on this Mac (Swift 6.4-dev) have three limitations:
- SwiftPM can't link even an empty package;
- the SwiftUI (`@State`) and Foundation Models (`@Generable`) macros are missing;
- the Claude package requires Xcode 27.

With Xcode 27 (~40 GB) all of this is solved and the code goes back to idiomatic SwiftUI. Contributors to an open-source Mac app will expect to open the project in Xcode.
