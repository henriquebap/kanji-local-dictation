# AGENTS.md

Guia para agentes de código (Claude Code, Codex, Cursor…) que forem trabalhar neste repositório. Para pessoas, comece pelo [README](README.md). Para o desenho completo, veja [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

## O que é

O Kanji é um app nativo de macOS para ditado em **português do Brasil com inglês misturado**:
- um atalho global grava;
- o `SpeechAnalyzer` da Apple transcreve no próprio Mac;
- um modelo de linguagem revisa (o modelo local da Apple, ou um provedor da nuvem com a chave do usuário);
- o texto entra no app em que a pessoa está.

App gratuito, código aberto (Apache 2.0). O nome e o ícone são reservados (`NOTICE`).

**Escopo atual:** ditado do microfone, revisão, glossário que aprende e histórico de ditados e clipboard.
**Fora do escopo por enquanto:** áudio do sistema/reuniões (v0.3), modo agente (v0.4), iPhone, App Store e servidor próprio. Veja [docs/ROADMAP.md](docs/ROADMAP.md).

## Build e testes

```bash
make app       # compila build/Kanji.app com swiftc
make install   # copia para /Applications e abre
make teste     # testes das regras puras (sem microfone nem modelo)
make dist      # release assinado e notarizado (precisa de Developer ID; docs/DISTRIBUICAO.md)
```

**Restrições do ambiente.** O build não usa Xcode nem SwiftPM, só `swiftc` (Command Line Tools):
- Não existem as macros `@State`, `@Generable` e `#Preview`. O estado das views fica em classes `@MainActor @Observable`, e o esquema do Foundation Models é montado à mão (`DynamicGenerationSchema`).
- Swift 6 com concorrência estrita, alvo `arm64-apple-macosx27.0`.
- Um arquivo novo em `Sources/Kanji/` entra no build sozinho (wildcard no `Makefile`). Para testar um arquivo novo, inclua-o na linha do alvo `teste`.
- Os testes são um executável próprio (`Tests/*.swift`, com `@main` em `CorrecaoTeste.swift`) que imprime `ok`/`FALHA`. Não é XCTest nem Swift Testing. Para um caso novo, use `conferir(nome, obtido, esperado)` em `Tests/RevisaoTeste.swift`.

**Verificar no app de verdade:** rode `make install`, faça um ditado e leia o log:
```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.henriquebap.kanji"' --style compact
```
O histórico guarda, para cada ditado, a transcrição crua (`bruto`) e o texto final, em `~/Library/Application Support/Kanji/historico.json`. É o melhor material para avaliar uma mudança na revisão.

## Mapa do código

| Arquivo | Responsabilidade |
|---|---|
| `KanjiApp.swift` | Entrada do app, barra de menu, composição (`Kanji.shared`) |
| `Ditado.swift` | Máquina de estados do ditado e a fila de trechos. **Comece por aqui** |
| `Captura.swift` | Microfone → `SpeechDetector` + `SpeechTranscriber` PT e EN |
| `Fusao.swift` | Escolhe PT ou EN palavra por palavra; glossário; maiúsculas |
| `Revisao.swift` | Regras puras: listas ditadas, junção de frases por pausa |
| `Correcao.swift` | Modelo local (Foundation Models) + trava de fidelidade |
| `Nuvem.swift` | Provedores da nuvem (Anthropic Messages / OpenAI Chat Completions) + Keychain |
| `Aprendizado.swift` | Glossário que aprende com as trocas feitas pela nuvem |
| `Saida.swift`, `Alvo.swift` | Colar com ⌘V; escrever ao vivo pela Acessibilidade |
| `Historico.swift` | Histórico em JSON + monitor do clipboard (filtra senhas e chaves) |
| `Painel.swift`, `AjustesView.swift`, `PrimeirosPassos.swift`, `HistoricoView.swift`, `Janelas.swift` | Interface |
| `Atalho.swift` | Atalhos globais (Carbon) |
| `Ajustes.swift` | Chaves e valores padrão do `UserDefaults` |

## Regras que não podem quebrar

1. **Nada de segredo no código.**
   - Chaves de API só no Keychain (`Chaveiro`), uma por provedor.
   - Nunca no `UserDefaults`, em log, em arquivo ou em teste. Use valores fictícios que não tenham o formato de uma chave real.
2. **Os logs nunca levam o conteúdo do ditado nem do clipboard.**
   - Registre contagens e tempos.
   - Mensagens de erro de provedor vão com `privacy: .private`, porque podem citar o texto.
   - Nada de `print()`: use `registro` (`os.Logger`).
3. **O texto da pessoa é dado, nunca instrução.**
   - A transcrição vai para o modelo dentro de `<transcricao>…</transcricao>`, com a regra de não responder ao conteúdo.
   - Não concatene texto do usuário nas instruções do sistema. O estilo e o glossário vêm dos Ajustes, que a própria pessoa escreveu.
4. **Nunca traduzir.**
   - O que foi dito em inglês fica em inglês.
   - O modelo local de ~3B traduz com frequência. A trava `Correcao.fiel` descarta a revisão quando isso acontece, e qualquer mudança no modelo local precisa manter os testes de fidelidade em `Tests/CorrecaoTeste.swift`.
5. **A falha degrada, não quebra.**
   - Sem chave, rede ou crédito, o ditado entrega o texto local e o painel avisa.
   - O texto nunca pode sumir: se não houver campo, ele fica no clipboard e no histórico.
6. **O áudio não sai do Mac.** Para a nuvem só vai texto, e só para o provedor que a pessoa escolheu.
7. **Nenhuma dependência de terceiros.** Só frameworks da Apple. Antes de adicionar uma, abra uma issue.

## Convenções

- **Português** em nomes, comentários, mensagens de log e textos da interface, com acentuação correta. Termos técnicos em inglês ficam como são.
- **Comentários explicam o porquê**, normalmente a observação ou o teste que levou à decisão ("visto nos testes", "reproduzido com áudio sintetizado"). Não descreva o que o código já diz.
- **`// ponytail:`** marca uma simplificação deliberada com teto conhecido e diz quando trocar. Respeite, ou resolva o teto.
- Diff pequeno, sem abstração para um caso só e sem configuração para valor que não muda.
- Regra de texto que dá para testar vai em código puro (`Escrita`, `Fusao`, `Aprendizado`), com um caso em `Tests/`.
- **Commits:** `tipo: descrição` (feat, fix, refactor, docs, test, chore, perf).

## Armadilhas conhecidas

- **Escrita pela Acessibilidade em editores web e Electron** (chat do Claude, Google no Chrome): o app responde "ok" e ignora o texto. Por isso, sem nada escrito ao vivo, o texto final é sempre colado com ⌘V.
- **Chrome e Electron só expõem os campos** depois que alguém define `AXManualAccessibility` no app (`Alvo.emFoco`).
- **`SpeechDetector` + `finalize(through:)` seguido só de silêncio** faz o finalizar do fim dar `RecogRejected`. O texto já firmado continua válido e o erro é tolerado em `Captura.parar`.
- **Foundation Models:**
  - com decodificação *greedy*, o modelo às vezes entra em loop até estourar o contexto de 8.192 tokens (daí o teto de tokens);
  - os guardrails padrão recusam textos inofensivos (daí o `.permissiveContentTransformations`).
- **Permissões do macOS** (Microfone, Acessibilidade) ficam presas à assinatura. Assinatura ad-hoc pede tudo de novo a cada build: use `scripts/certificado-dev.sh`.
- **Modelos de provedores** mudam rápido. Confira o nome atual na documentação do provedor antes de mudar `Provedor.modeloPadrao`; nunca escreva de memória.
