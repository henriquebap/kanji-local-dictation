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
- **Distribution:** free for now (build from source and GitHub Releases); Developer ID, Homebrew, Mac App Store and iPhone once the paid Apple membership makes sense ([DISTRIBUTION.md](DISTRIBUTION.md)).

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
**Status (2026-11-14):** capture, long sessions saved as JSON + Markdown, optional speaker separation and Me × Others work; tested on a pt-BR podcast (two speakers, both turn changes caught) and on a simulated call. Since 2026-11-16 the state shows on the Kizami island when it is running (only state and counts, never the text), and the first session shows a consent notice. Since 2026-11-16 the Transcripts section reads, renames and summarizes sessions in the transcript's own language, and recovers English sentences said right after Portuguese. Since 2026-11-17 it also gives interview feedback (strengths, what to improve, each interviewer question rated). Still missing: a test in a real meeting.
- **Me × Others (built):** the microphone joins the session by itself while another app has it open (`AudioHardwareProcess.isRunningInput`; macOS speech services don't count) and leaves 10 s after the call releases it; voice processing cancels the speaker echo. AirPods drop from 48 to 24 kHz while a call holds the microphone: the capture follows the rate change and resamples to the initial format, otherwise the recognizer got nothing during the call.
- **Speakers (built):** there's no native diarization, so each segment is split into ~3 s word windows; each window becomes a WeSpeaker ResNet34 embedding (CoreML, optional ~15 MB download, CC BY 4.0) taken inside 10 s of real audio context, and an online clustering (cosine ≥ 0.5) names "Speaker 1, 2…". Feeding the window padded with zeros instead of real context made different voices look alike (0.65–0.80 vs 0.01–0.20).
- **Capture:** Core Audio process taps (`AudioHardwareCreateProcessTap`, Swift API `AudioHardwareSystem.shared.makeProcessTap`). Only asks for the "System Audio Recording" permission, narrower than Screen Recording, and can filter by app (`bundleIDs`). Avoid ScreenCaptureKit (requires screen permission) and virtual drivers.
- **Live:** `SpeechAnalyzer.start(inputSequence:)` with `AsyncStream<AnalyzerInput>` and the `.progressiveTranscription` preset. Volatile text shows in gray and final text in black. On macOS 27, `AnalyzerInputConverter` removes the need for a manual `AVAudioConverter`.
- **Me × Others:** two transcribers, one on the microphone and one on the tap, interleaved by `audioTimeRange`. There's no native diarization.
- **Requirements:** `NSAudioCaptureUsageDescription` (without it the tap records silence, with no error), a stable signature (Developer ID) so TCC doesn't forget the permission, and a consent notice: recording a meeting has LGPD implications when it's work.
- **Limit:** the local context is 8k tokens, so summarizing a 1 h meeting requires Claude (v0.4).

### Interview mode (planned 2026-11-17, before agent mode)
While a job interview runs in a call, Kanji notices each question from the interviewer and shows, within seconds, a few bullet points to answer it: which story to tell, the facts and numbers behind it, and a structure (situation, action, result). The bullets come from the user's own notes, never from the model's imagination. Interviews happen in Portuguese and in English, so detection and suggestions follow the language of the question.

**Already in place:** the Mac-audio session separates the interviewer (Mac audio) from the candidate ("Você", microphone during a call), the cloud client with the user's key, and the post-interview feedback, which is step 0 below.

**Pipeline:**
1. **Hear.** Reuse `SessaoDoMac`. Each segment the interviewer finishes (canal `.mac`, followed by a pause from `SpeechDetector`) is a candidate.
2. **Detect the question.** Only one decision is needed, whether the interviewer's turn asks for an answer: the cloud picks the story in step 4, so classifying the type of question was dropped. A pure PT/EN cue rule (`Pergunta`) answers first; when it says no, the Mac's model (`PerguntaNoModelo`) gets the turn, because yes/no questions spoken as statements ("você teria disponibilidade pra semana que vem.") are only recognizable by meaning. A question mark isn't reliable because the recognizer punctuates poorly.
   - **Measured on 2026-11-17** with two labeled sets of 120 turns (PT and EN), written by a separate agent that never saw the code. The rule was tuned on the first; the numbers below are from the second:

     | Path | Precision | Recall | Time per turn |
     |---|---|---|---|
     | Rule only | 0.90 | 0.75 | ~0 ms |
     | Mac model only | 0.98 | 0.68 | ~430 ms |
     | Rule, then model (used) | 0.90 | 0.90 | ~250 ms |
   - The sets are written, not recorded. Real interviews replace them as they come: the interview feedback already lists each interviewer question.
3. **Retrieve.** The knowledge is the user's career notes, read-only from a folder they pick in Settings (an Obsidian vault). Kanji reads the files at run time and never copies them into the repository or the app. A curated set of notes for interviews is small enough to send whole.
   - ponytail: the whole pack goes in the prompt with prompt caching, so each question pays only for the question. Retrieval with `NLEmbedding` comes in only if the pack outgrows the context.
4. **Suggest.** A fast cloud model (Claude Haiku via `Nuvem`) streams 3 to 5 bullets in the question's language.
   - Each fact names its note.
   - Anything that isn't in the notes is said to be missing, never made up.
   - The question goes in as data inside `<pergunta>`, like the transcript today.
5. **Show.** A small transparent panel (`NSPanel`, non-activating) that never takes focus. `sharingType = .none` keeps it out of screen sharing and recording. The Kizami island gets only the state ("pergunta detectada").
6. **Remember.** After the interview, the feedback adds each question and how well it was answered to a note in the vault, with the user's confirmation, so the next interview's pack knows the weak spots.

**Milestones:**
| Step | Delivers | Can be tested without an interview |
|---|---|---|
| 0 | Post-interview feedback (done) | yes, on saved transcripts |
| 1 | Notes folder in Settings plus an "ask my notes" field: type a question, see the bullets (built 2026-11-17) | yes |
| 2 | Question detection, with the labeled sets and their numbers (built 2026-11-17: 0.90 precision, 0.90 recall) | yes |
| 3 | Live: detection during the session, the panel, latency logged (goal: bullets within 3 s of the end of the question). Built 2026-11-17: 4.3 to 7.0 s measured with `say` (Portuguese firms ~2.3 s after the end of speech, the cloud takes ~3 s with the notes cached). Next: streaming the answer, and the volatile Portuguese text at the pause | mock interview |
| 4 | Memory loop: question bank back into the vault | yes |

**Rules carried over:** audio never leaves the Mac; only the question and the notes go to the provider the user chose; logs carry counts and timings, never the question or the notes. Without a key, credits or network, the panel says so and the transcription goes on.

**Honest risks:**
- Latency: recognizer finalization, plus classification, plus the first cloud token, has to fit in a few seconds or the bullets arrive after the answer.
- False positives while the interviewer is still talking.
- The interviewer's speech is a third party's data. The consent notice already covers it.
- Some companies forbid aids during interviews. The tool shows the user's own facts, and when to use it is the user's call.

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
