# Kanji — ditado com IA local para Mac

[English](README.md) · Português (Brasil)

Ditado com IA para o Mac, em **português e inglês ao mesmo tempo**. Aperte um atalho, fale, e o texto aparece revisado no app em que você estiver: Notes, Slack, Chrome, o chat do Claude, um terminal.

Nativo (Swift, sem Electron), gratuito e de código aberto. A transcrição acontece no próprio Mac.

> A interface segue o idioma do Mac: inglês ou português do Brasil. Os nomes abaixo são os da interface em português.

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

O Kanji é gratuito. Ele ainda não faz parte do programa pago de desenvolvedor da Apple (US$ 99/ano), então não pode ser notarizado pela Apple. A notarização é a checagem que deixa um app abrir sem avisos. Até lá, há dois jeitos grátis de instalar: compilar você mesmo (sem aviso nenhum) ou baixar o app pronto e liberar uma vez.

> **Requisitos:** Mac com Apple Silicon e **macOS 27** ou mais recente. Ative a Apple Intelligence para ter a revisão local grátis; sem ela, o ditado funciona, só que sem revisão.

### Opção A: compilar você mesmo (recomendado)

**Objetivo:** gerar o Kanji no seu próprio Mac. O macOS confia no que você mesmo compilou, então não aparece aviso de segurança, e atualizar é um comando só.

1. **Instale as ferramentas de linha de comando da Apple.** Elas trazem o compilador Swift (cerca de 1 GB; não precisa do Xcode completo).
   ```bash
   xcode-select --install
   ```
2. **Baixe o código.**
   ```bash
   git clone https://github.com/henriquebap/kanji-local-dictation.git && cd kanji-local-dictation
   ```
3. **Crie um certificado local de assinatura.** É opcional, mas recomendado. O macOS prende as permissões de Microfone e Acessibilidade à assinatura do app. Com o certificado, cada atualização mantém as permissões; sem ele, o macOS pede de novo a cada atualização. O script pede a senha do Mac uma vez.
   ```bash
   ./scripts/dev-certificate.sh
   ```
4. **Compile e instale.** Isso compila o app, copia para Aplicativos e abre.
   ```bash
   make install
   ```

**Para atualizar depois:** `git pull && make install`.

### Opção B: baixar o app pronto

**Objetivo:** pular a compilação. Como o app não é notarizado, o macOS bloqueia a primeira abertura e você libera uma vez.

1. **Baixe** o `Kanji-X.Y.Z.zip` em [Releases](https://github.com/henriquebap/kanji-local-dictation/releases), descompacte e arraste o `Kanji.app` para Aplicativos.
2. **Abra o Kanji.** O macOS diz que não consegue verificar o desenvolvedor. Clique em **OK**, não em *Mover para o Lixo*. Isso é o Gatekeeper, que bloqueia todo app baixado que a Apple não notarizou.
3. **Libere.** Abra *Ajustes do Sistema › Privacidade e Segurança*, desça até **Segurança** e clique em **Abrir Mesmo Assim** ao lado de "O Kanji foi bloqueado". Confirme com a sua senha. Isso diz ao macOS que você confia neste app específico, e só precisa ser feito uma vez por versão baixada.

   O botão só aparece por um tempo depois da abertura bloqueada. Se não estiver lá, abra o Kanji de novo e volte direto para os Ajustes.

> **Homebrew:** desde o Homebrew 5, os casks precisam ser notarizados pela Apple. Por isso o `brew install` só vai existir quando o Kanji entrar no programa da Apple.

## Primeiros passos

Na primeira vez, o Kanji abre a janela **Primeiros passos**. Ela lista o que o macOS precisa liberar e por quê; o ✓ verde marca cada passo concluído:

1. **Microfone.** *Objetivo:* deixar o Kanji ouvir você, só enquanto o atalho está ativo. Clique em *Permitir*. O áudio é transcrito no próprio Mac e nunca sai dele.
2. **Acessibilidade.** *Objetivo:* deixar o Kanji pôr o texto no app que você está usando. Clique em *Abrir Ajustes do Sistema* e ative o Kanji na lista.
3. **Apple Intelligence.** *Objetivo:* revisão grátis e sem internet do que você dita. Ative em *Ajustes do Sistema › Apple Intelligence e Siri*.
4. **Revisão na nuvem (opcional).** *Objetivo:* uma revisão melhor do texto inteiro (listas na ordem pedida, nomes, jargão) com a sua própria chave de API. Em *Ajustes › Correção*:
   - escolha o provedor;
   - cole a sua chave (ela fica no Keychain do macOS);
   - clique em *Testar*.
5. **Teste.** *Objetivo:* conferir que tudo funciona. Clique em qualquer campo de texto, aperte **⌃⌥D**, fale e aperte **⌃⌥D** de novo; o texto aparece onde está o cursor.

A janela volta quando quiser pelo menu do Kanji › *Primeiros passos…*.

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

[docs/ARCHITECTURE.pt-BR.md](docs/ARCHITECTURE.pt-BR.md) tem o desenho completo: as camadas, o caminho do áudio até o texto, o que vai para cada modelo e por quê.

## Desenvolvimento

```bash
make run       # compila build/Kanji.app e abre
make install   # copia para /Applications
make teste     # testes das regras (listas, junção de frases, fidelidade, glossário que aprende)
```

- O build usa `swiftc` direto e funciona sem o Xcode. Por isso o estado das telas fica em classes `@Observable`, sem as macros `@State` e `@Generable`.
- As permissões do macOS ficam presas à assinatura do app. Para não pedir de novo a cada build, crie um certificado local uma vez com `./scripts/dev-certificate.sh`.
- Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "io.github.henriquebap.kanji"' --info`
- Como publicar uma versão gratuita (e o caminho pago da Apple, para depois): [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) (em inglês).
- Próximos passos: [docs/ROADMAP.md](docs/ROADMAP.md) (em inglês).

PRs são bem-vindos. Para mudança grande, abra uma issue antes.

## Licença

[Apache 2.0](LICENSE). Você pode usar, modificar e distribuir o código, inclusive comercialmente, mantendo o aviso de copyright e o [NOTICE](NOTICE). O nome **Kanji** e o ícone não fazem parte da licença: um fork publicado precisa de outro nome e outro ícone.
