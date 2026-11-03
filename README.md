# Kanji

Ditado com IA para o Mac, em **português e inglês ao mesmo tempo**. Aperte um atalho, fale, e o texto aparece revisado no app em que você estiver: Notes, Slack, Chrome, o chat do Claude, um terminal.

Nativo (Swift, sem Electron), gratuito e de código aberto. A transcrição acontece no próprio Mac.

## O que ele faz

- **Escreve onde está o cursor.** Ao parar, o texto revisado entra no campo selecionado. Sem campo, ele fica no clipboard e no histórico.
- **Português e inglês juntos.** Dois reconhecedores ouvem o mesmo áudio, e uma fusão palavra por palavra pega "deploy", "pull request" e "LLM" do inglês sem estragar o português. Frases inteiras em inglês ficam em inglês: nada é traduzido.
- **Listas ditadas viram listas.** "Primeiro banana, segundo café… o quarto e o quinto vão ser Ferrari e McLaren" vira uma lista numerada, na ordem pedida.
- **Revisão em duas camadas:**
  - **Modelo do Mac** (Apple Intelligence): grátis e sem internet. É pequeno, então corrige palavra e pontuação trecho a trecho.
  - **Modelo da nuvem, com a sua chave** (opcional): Claude, OpenAI, Gemini, Groq, OpenRouter ou qualquer API compatível com a da OpenAI. Ele revisa o ditado inteiro ao parar, em ~1,5 s, e entende o contexto.
- **Glossário que aprende.** Cada termo que a revisão da nuvem corrige duas vezes ("Cláudio" → Claude) passa a valer também no modelo do Mac, sem internet.
- **Ignora o silêncio.** Um detector de voz da Apple impede que ruído e silêncio virem palavras que você não disse.
- **Histórico pesquisável** de tudo que você ditou e copiou. Ficam de fora as senhas marcadas pelos gerenciadores (1Password, Bitwarden, Chaves) e os textos com cara de chave de API ou token. Dá para desligar o histórico do clipboard.

## Instalar

> Requisitos: Mac com Apple Silicon, **macOS 27** ou mais recente e Apple Intelligence ativado. Sem a Apple Intelligence, o ditado funciona, mas sem a revisão local.

**Homebrew** (quando a primeira versão notarizada sair):
```bash
brew install --cask henriquebap/tap/kanji
```

**Download direto:** baixe o `.zip` em [Releases](https://github.com/henriquebap/kanji/releases), descompacte e arraste o `Kanji.app` para Aplicativos.

**Compilando** (só precisa das Command Line Tools: `xcode-select --install`):
```bash
git clone https://github.com/henriquebap/kanji.git && cd kanji
make install
```

## Primeiros passos

Na primeira vez, o Kanji abre a janela **Primeiros passos**. Ela mostra, com ✓ verde, o que já está liberado:

1. **Microfone:** clique em *Permitir*. O áudio é transcrito no próprio Mac.
2. **Acessibilidade:** clique em *Abrir Ajustes do Sistema* e ative o Kanji na lista. É isso que deixa ele escrever no app em que você está.
3. **Apple Intelligence:** ative em *Ajustes do Sistema › Apple Intelligence e Siri* para ter a revisão grátis.
4. **Opcional, revisão na nuvem:** em *Ajustes › Correção*:
   - escolha o provedor;
   - cole a sua chave (ela fica no Keychain do macOS);
   - clique em *Testar*.

Depois, é só usar: clique num campo de texto, aperte **⌃⌥D**, fale e aperte de novo. A janela volta pelo menu do Kanji › *Primeiros passos…*.

| Atalho | O que faz | Onde muda |
|---|---|---|
| **⌃⌥D** (global) | Começa a gravar; de novo, para e escreve o texto | Ajustes › Geral |
| **esc** (gravando) | Cancela | fixo |
| **⌃⌥T** (global) | Abre a janela do Kanji | Ajustes › Geral |
| **⌘Y** | Histórico | fixo |
| **⌘,** | Ajustes | fixo |

Em Ajustes › Geral também ficam o modo "segurar enquanto fala" e o "escrever enquanto você fala". Neste último, o texto aparece no campo durante a fala, revisado trecho a trecho pelo modelo do Mac. É o modo padrão quando não há provedor da nuvem.

## Privacidade

- **O áudio nunca sai do Mac.** A transcrição é do `SpeechAnalyzer` da Apple, on-device.
- **Com o modelo do Mac,** nada sai do computador.
- **Com um provedor da nuvem,** só o **texto** do ditado vai para ele, usando a **sua** chave e conforme os termos dele. O Kanji não tem servidor.
- **Chaves de API** ficam no Keychain.
- **Histórico** fica em `~/Library/Application Support/Kanji`; **ajustes e glossário** (inclusive os termos aprendidos), nas preferências do app.
- **Histórico do clipboard:** vem ligado e guarda o que você copia, para achar depois. Uma senha que não venha de um gerenciador também entra nele. Se você copia senhas de outros lugares, desligue em Ajustes › Histórico.

## Idiomas

Hoje: **português do Brasil com inglês misturado**. O reconhecimento de fala já aceita outros idiomas principais (Ajustes › Geral), mas as regras de lista e a revisão foram pensadas e testadas só para o português com inglês. Abrir para outros idiomas está no roadmap.

## Como funciona

[docs/ARQUITETURA.md](docs/ARQUITETURA.md) tem o desenho completo: as camadas, o caminho do áudio até o texto, o que vai para cada modelo e por quê.

## Desenvolvimento

```bash
make run       # compila build/Kanji.app e abre
make install   # copia para /Applications
make teste     # testes das regras (listas, junção de frases, fidelidade, glossário que aprende)
```

- O build usa `swiftc` direto e funciona sem o Xcode. Por isso o estado das telas fica em classes `@Observable`, sem as macros `@State` e `@Generable`.
- As permissões do macOS ficam presas à assinatura do app. Para não pedir de novo a cada build, crie um certificado local uma vez com `./scripts/certificado-dev.sh`.
- Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.henriquebap.kanji"' --info`
- Release assinado e notarizado: [docs/DISTRIBUICAO.md](docs/DISTRIBUICAO.md).
- Próximos passos: [docs/ROADMAP.md](docs/ROADMAP.md).

PRs são bem-vindos. Para mudança grande, abra uma issue antes.

## Licença

[Apache 2.0](LICENSE). Você pode usar, modificar e distribuir o código, inclusive comercialmente, mantendo o aviso de copyright e o [NOTICE](NOTICE). O nome **Kanji** e o ícone não fazem parte da licença: um fork publicado precisa de outro nome e outro ícone.
