# Roadmap

Resumo das pesquisas de 03/11/2026: mercado, captura de áudio do sistema e modo agente.

## Posicionamento

**O mercado:**
- **Assinaturas na nuvem** a US$ 12–15/mês: Wispr Flow, Willow, Monologue.
- **Apps locais com Whisper** em compra única de US$ 25–80: VoiceInk, MacWhisper, BetterDictation.
- **Open-source que baixa modelo:** Handy (37k★, Tauri), FluidVoice (12,7k★), OpenWhispr (10,6k★, Electron), VoiceInk (7k★, mas não aceita PRs).

**Mesma stack que a nossa (SpeechAnalyzer + Foundation Models):**
- Yap (465★)
- Megaphone (180★, parado desde jul/2026)

Ninguém domina, mas o espaço não está vazio. **O diferencial tem de vir da execução:**
1. **pt-BR de primeira classe, misturado com inglês.** Todos os concorrentes são pensados para o inglês. A fusão PT+EN, com dois `SpeechTranscriber` no mesmo áudio, resolve o jargão técnico sem nuvem.
2. **Ditado e clipboard num app só.** Hoje é preciso combinar VoiceInk com Maccy.
3. **Open-source de verdade**, aceitando PRs.
4. **Zero download, zero custo, nativo e leve.**

**Riscos honestos:**
- Não existe benchmark público do SpeechAnalyzer em pt-BR.
- O modelo local (~3B, contexto de 8k tokens) às vezes responde ao texto em vez de corrigi-lo.
- Exige Apple Intelligence.

## Dores reais que a v1 precisa resolver

| Dor | Como resolver |
|---|---|
| Colagem falha em terminal e campo seguro, e o clipboard fica sujo | Salvar e restaurar o clipboard; atalho de colagem próprio para terminais; detectar Secure Input e avisar |
| Jargão sai errado ("cloud code") | Dicionário pessoal de substituições aplicado depois da transcrição |
| O LLM "conversa" em vez de corrigir | Timeout, validação (descartar a saída se se afastar demais do original) e fallback para o bruto |
| Permissão negada sem explicação | Onboarding de permissões com diagnóstico |
| Senha vazando no histórico | Já ignora os tipos Concealed/Transient; falta lista de apps excluídos e detectar tokens |

## Modelo de produto (decidido em 03/11/2026)

- **Código aberto (Apache 2.0) e app gratuito.** O nome e o ícone ficam com o autor (ver `NOTICE`).
- **Grátis para sempre:**
  - transcrição no Mac;
  - revisão com o modelo do Mac;
  - revisão na nuvem com a chave da própria pessoa;
  - glossário que aprende;
  - histórico.
- **Assinatura barata no futuro (R$ 5–10/mês):** revisão na nuvem sem precisar de chave e features novas.
  - Exige um servidor próprio (proxy com conta, limite por usuário e cobrança), porque a chave do autor nunca vai dentro do app.
  - Os créditos da API que vêm com o plano Max podem alimentar um produto vendido, mas o serviço não pode depender só deles: quando acabam, a API para. Precisa de crédito comprado ou auto-reload por trás.
- **Distribuição:** download notarizado + Homebrew primeiro, Mac App Store e iPhone depois ([DISTRIBUICAO.md](DISTRIBUICAO.md)).

## Fases

### v0.1: ditado usável (construída, falta validar no uso real)
Escrita ao vivo no campo em foco (Acessibilidade) com painel compacto, ou texto no painel quando não há campo; português + inglês com fusão palavra por palavra e glossário pessoal; correção em streaming com validação, colagem com restauração do clipboard, atalhos globais configuráveis (ditar e abrir), esc para cancelar, app com janela principal e ícone, sons de estado, histórico de ditados e clipboard com busca.

### Feito em 03/11/2026
- Revisão na nuvem com vários provedores: Claude, OpenAI, Gemini, Groq, OpenRouter e qualquer API compatível com a da OpenAI.
- Modo "só no fim", com colagem por ⌘V que funciona em todos os apps.
- Glossário que aprende com a revisão da nuvem.
- Detector de voz contra palavras inventadas no silêncio.
- Janela de primeiros passos com as permissões.
- Filtro de chaves e tokens no histórico do clipboard.

### v0.2: polimento (o que separa um brinquedo de um produto)
- Timeout da correção
- Apps excluídos do histórico
- Benchmark: 30–50 áudios reais em pt-BR, medindo o WER contra Whisper large-v3 e Parakeet. Seria um número que nenhum concorrente publica.

### v0.3: transcrever o que o Mac está tocando (reuniões, vídeos)
- **Captura:** Core Audio process taps (`AudioHardwareCreateProcessTap`, API Swift `AudioHardwareSystem.shared.makeProcessTap`). Pede só a permissão "Gravação de áudio do sistema", menor que a de Gravação de Tela, e pode filtrar por app (`bundleIDs`). Evitar ScreenCaptureKit (exige permissão de tela) e drivers virtuais.
- **Ao vivo:** `SpeechAnalyzer.start(inputSequence:)` com `AsyncStream<AnalyzerInput>` e preset `.progressiveTranscription`. O texto volátil aparece em cinza e o final em preto. No macOS 27, o `AnalyzerInputConverter` dispensa o `AVAudioConverter` manual.
- **Eu × Outros:** dois transcritores, um no microfone e outro no tap, intercalados por `audioTimeRange`. Não existe diarização nativa.
- **Requisitos:** `NSAudioCaptureUsageDescription` (sem ela o tap grava silêncio, sem erro), assinatura estável (Developer ID) para o TCC não esquecer a permissão, e aviso de consentimento: gravar reunião tem implicações de LGPD quando é trabalho.
- **Limite:** o contexto local é de 8k tokens, então resumir uma reunião de 1 h exige o Claude (v0.4).

### v0.4: modo agente (opt-in)
- **Integração:** o pacote oficial [`anthropics/ClaudeForFoundationModels`](https://github.com/anthropics/ClaudeForFoundationModels) implementa o protocolo `LanguageModel`. A mesma `LanguageModelSession` troca entre o modelo local e o Claude via Dynamic Profiles. Está em beta e pede Xcode 27.
- **Roteamento:** o modelo local só **classifica** a intenção num enum fechado, e uma tabela no código decide a rota:

  | Rota | Quando |
  |---|---|
  | Local | Corrigir, extrair, uma tool simples |
  | Claude Haiku 5.5 | Uma etapa com tools |
  | Claude Sonnet 5.5 | Várias etapas, ata de reunião |

  Sem chave ou sem crédito, o pedido degrada para o local ou para uma fila de pendentes. **O ditado normal nunca passa pelo agente.**
- **Tools v1:**
  - Leitura, sem confirmação: buscar no histórico, traduzir (framework Translation).
  - Com efeito, sempre confirmadas: criar evento ou lembrete (EventKit), criar nota.
  - Rodar um atalho do usuário que esteja numa allowlist: dá extensibilidade de graça.
- **Segurança:**
  - Transcrição e clipboard são **dados**, nunca instrução.
  - A confirmação acontece dentro do `call()` da tool, onde o modelo não tem como pulá-la.
  - A chave fica no Keychain. Áudio e histórico completo nunca saem do Mac.
- **Gimmick a evitar:** "traduz o que copiei" é mais rápido com um atalho fixo do que com um agente.

## Decisão pendente: instalar o Xcode

As Command Line Tools deste Mac (Swift 6.4-dev) têm três limitações:
- o SwiftPM não linka nem um pacote vazio;
- faltam as macros do SwiftUI (`@State`) e do Foundation Models (`@Generable`);
- o pacote do Claude pede Xcode 27.

Com o Xcode 27 (~40 GB) tudo isso se resolve e o código volta ao SwiftUI idiomático. Contribuidores de um app de Mac open-source vão esperar abrir o projeto no Xcode.
