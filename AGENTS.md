# AGENTS.md

Guide for coding agents (Claude Code, Codex, Cursor…) working in this repository. For people, start with the [README](README.md). For the full design, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What it is

Kanji is a native macOS app for dictation in **Brazilian Portuguese mixed with English**:
- a global shortcut records;
- Apple's `SpeechAnalyzer` transcribes on the Mac itself;
- a language model reviews the text (Apple's local model, or a cloud provider with the user's key);
- the text goes into the app the user is in.

Free app, open source (Apache 2.0). The name and icon are reserved (`NOTICE`).

**Current scope:** microphone dictation, review, a glossary that learns, and dictation and clipboard history.
**Out of scope for now:** system audio/meetings (v0.3), agent mode (v0.4), iPhone, App Store and our own server. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Build and tests

```bash
make app       # compila build/Kanji.app com swiftc
make install   # copia para /Applications e abre
make teste     # testes das regras puras (sem microfone nem modelo)
swift scripts/check-localization.swift  # toda string da interface tem inglês; .strings válidos; lê o bundle se houver build
make dist      # release assinado e notarizado (precisa de Developer ID; docs/DISTRIBUTION.md)
```

**Environment constraints.** The build uses neither Xcode nor SwiftPM, only `swiftc` (Command Line Tools):
- The `@State`, `@Generable` and `#Preview` macros don't exist. View state lives in `@MainActor @Observable` classes, and the Foundation Models schema is built by hand (`DynamicGenerationSchema`).
- Swift 6 with strict concurrency, target `arm64-apple-macosx27.0`.
- A new file in `Sources/Kanji/` is picked up by the build automatically (wildcard in the `Makefile`). To test a new file, add it to the `teste` target's line.
- The tests are their own executable (`Tests/*.swift`, with `@main` in `CorrecaoTeste.swift`) that prints `ok`/`FALHA`. It's neither XCTest nor Swift Testing. For a new case, use `conferir(nome, obtido, esperado)` in `Tests/RevisaoTeste.swift`.

**Verify in the real app:** run `make install`, dictate something and read the log:
```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.henriquebap.kanji"' --style compact
```
For each dictation, the history stores the raw transcription (`bruto`) and the final text, in `~/Library/Application Support/Kanji/historico.json`. It's the best material for evaluating a change to the review.

## Code map

| File | Responsibility |
|---|---|
| `KanjiApp.swift` | App entry point, menu bar, composition (`Kanji.shared`) |
| `Ditado.swift` | Dictation state machine and the segment queue. **Start here** |
| `Captura.swift` | Microphone → `SpeechDetector` + PT and EN `SpeechTranscriber` |
| `Fusao.swift` | Picks PT or EN word by word; glossary; capitalization |
| `Revisao.swift` | Pure rules: dictated lists, joining sentences by pause |
| `Correcao.swift` | Local model (Foundation Models) + fidelity guard |
| `Nuvem.swift` | Cloud providers (Anthropic Messages / OpenAI Chat Completions) + Keychain |
| `Aprendizado.swift` | Glossary that learns from the replacements the cloud makes |
| `Saida.swift`, `Alvo.swift` | Paste with ⌘V; live typing via Accessibility |
| `Historico.swift` | JSON history + clipboard monitor (filters passwords and keys) |
| `Painel.swift`, `AjustesView.swift`, `PrimeirosPassos.swift`, `HistoricoView.swift`, `Janelas.swift` | UI |
| `Atalho.swift` | Global shortcuts (Carbon) |
| `Ajustes.swift` | `UserDefaults` keys and default values |

## Rules that must not break

1. **No secrets in code.**
   - API keys only in the Keychain (`Chaveiro`), one per provider.
   - Never in `UserDefaults`, logs, files or tests. Use fake values that don't look like a real key.
2. **Logs never include the content of a dictation or the clipboard.**
   - Log counts and timings.
   - Provider error messages go with `privacy: .private`, because they may quote the text.
   - No `print()`: use `registro` (`os.Logger`).
3. **The user's text is data, never instructions.**
   - The transcription goes to the model inside `<transcricao>…</transcricao>`, with the rule not to respond to its content.
   - Don't concatenate user text into the system instructions. Style and glossary come from Settings, which the user wrote themselves.
4. **Never translate.**
   - What was said in English stays in English.
   - The ~3B local model translates often. The `Correcao.fiel` guard discards the review when that happens, and any change to the local model must keep the fidelity tests in `Tests/CorrecaoTeste.swift` passing.
5. **Failure degrades, it doesn't break.**
   - Without a key, network or credits, dictation delivers the local text and the panel shows a warning.
   - Text must never disappear: if there's no field, it stays in the clipboard and in the history.
6. **Audio never leaves the Mac.** Only text goes to the cloud, and only to the provider the user chose.
7. **No third-party dependencies.** Apple frameworks only. Open an issue before adding one.

## Conventions

- **The codebase is in Portuguese (pt-BR) by design:** Swift identifiers, code comments, log messages and the UI source strings. New code follows the same convention, with correct accents. English technical terms stay as they are.
- **The UI is localized (pt-BR + en)** and follows the Mac's language:
  - The Portuguese text in the code **is the key**. `Resources/en.lproj/Localizable.strings` maps it to English; `Resources/pt-BR.lproj/` stays empty but must exist (with `CFBundleDevelopmentRegion` = `pt-BR` in `Info.plist`), or a Mac in Portuguese would get English. The `Makefile` copies both `.lproj` folders into the bundle. No String Catalog: `.xcstrings` needs Xcode to compile.
  - **Every new user-facing string needs an entry in `en.lproj/Localizable.strings`.** Interpolations become `%@` in the key (`"Pronto no %@"`).
  - SwiftUI literals (`Text("…")`, `Button("…")`, `Toggle`, `Section`, `Picker`…) are localized on their own. A **`String` value** shown in the UI is not: ternaries (`Text(a ? "x" : "y")`), properties like `Provedor.nome`, messages passed to `falhar`, `aviso`, window titles, `NSAlert`. Use `String(localized: "…")` for those.
  - **Never localize** what is persisted or sent to a model: LLM prompts (`Nuvem.regras`, `Correcao.regras`, `Ajustes.instrucoesPadrao`, the default glossary), the word lists used by the rules, log messages, `UserDefaults` keys, Keychain accounts, enum raw values, `Codable` fields.
  - Run `swift scripts/check-localization.swift` after touching UI text: it extracts the UI literals from `Sources/Kanji`, fails on any key missing from the English table (or an unused one), and runs `plutil -lint` on the `.strings` files.
- **Docs are English-first.** README and ARCHITECTURE have pt-BR copies (`README.pt-BR.md`, `docs/ARCHITECTURE.pt-BR.md`); when you change the English version, update the pt-BR copy too.
- **Comments explain the why**, usually the observation or test that led to the decision ("visto nos testes", "reproduzido com áudio sintetizado"). Don't describe what the code already says.
- **`// ponytail:`** marks a deliberate simplification with a known ceiling and says when to replace it. Respect it, or resolve the ceiling.
- Small diffs, no abstraction for a single case and no configuration for a value that never changes.
- Testable text rules go in pure code (`Escrita`, `Fusao`, `Aprendizado`), with a case in `Tests/`.
- **Commits:** `type: description` (feat, fix, refactor, docs, test, chore, perf).

## Known pitfalls

- **Typing via Accessibility in web and Electron editors** (Claude chat, Google in Chrome): the app answers "ok" and ignores the text. That's why, when nothing was typed live, the final text is always pasted with ⌘V.
- **Chrome and Electron only expose their fields** after someone sets `AXManualAccessibility` on the app (`Alvo.emFoco`).
- **`SpeechDetector` + `finalize(through:)` followed only by silence** makes the final finalize return `RecogRejected`. The already-committed text remains valid and the error is tolerated in `Captura.parar`.
- **Foundation Models:**
  - with *greedy* decoding, the model sometimes loops until it overflows the 8,192-token context (hence the token cap);
  - the default guardrails reject harmless text (hence `.permissiveContentTransformations`).
- **macOS permissions** (Microphone, Accessibility) are tied to the signature. An ad-hoc signature asks for everything again on every build: use `scripts/dev-certificate.sh`.
- **Provider models** change fast. Check the current name in the provider's documentation before changing `Provedor.modeloPadrao`; never write it from memory.
