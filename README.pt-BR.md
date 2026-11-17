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
- **Transcreve o que o Mac toca.** Um vídeo, um podcast ou uma reunião, em segundo plano, num arquivo Markdown e num JSON. Numa chamada, a sua voz entra como "Você"; com o modelo de voz opcional, as outras vozes viram "Locutor 1, 2…". Veja [Transcrever o áudio do Mac](#transcrever-o-áudio-do-mac).

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
| **⌃⌥K** (global) | Abre a janela do Kanji | Ajustes › Geral |
| **⌃⌥M** (global) | Começa a transcrever o áudio do Mac; de novo para parar e salvar | Ajustes › Geral |
| **⌘Y** | Histórico | fixo |
| **⌘,** | Ajustes | fixo |

Todo atalho global é **⌃⌥ + uma letra**: **D** de ditar, **M** de Mac, **K** de Kanji. O macOS não usa ⌃⌥ + letra, então eles não tiram o atalho de outro app. Ao gravar um novo, os Ajustes só aceitam combinações com ⌃⌥.

Em Ajustes › Geral também ficam o modo "segurar enquanto fala" e o "escrever enquanto você fala". Neste último, o texto aparece no campo durante a fala, revisado trecho a trecho pelo modelo do Mac. É o modo padrão quando não há provedor da nuvem.

## Transcrever o áudio do Mac

Aperte **⌃⌥M** (ou *Transcrever o áudio do Mac* no menu) e o Kanji transcreve tudo o que o Mac tocar, menos os sons dele mesmo, com fone ou com caixa de som. Aperte de novo para parar.

- **Na primeira vez:** um aviso lembra de avisar as pessoas antes de transcrever uma reunião, e o macOS pede a *Gravação de Áudio do Sistema* (*Ajustes do Sistema › Privacidade e Segurança*). Ela é mais estreita que a Gravação de Tela: o Kanji nunca vê a tela.
- **Ler e usar:** *Abrir transcrições* no menu abre a janela do Kanji em **Transcrições**: cada sessão com data, duração e quem falou. Numa sessão dá para *Copiar* (Markdown, pronto para colar num documento ou num chat), *Renomear* quem fala ("Locutor 1" → um nome, em todos os parágrafos e arquivos), *Mostrar no Finder* ou mandar para o Lixo. A busca também procura nas transcrições.
- **Resumir:** manda o **texto** da transcrição para o provedor da nuvem dos *Ajustes › Correção* (a sua chave) e devolve resumo, pontos importantes com a hora, decisões e tarefas, no idioma principal da transcrição (um podcast em inglês tem resumo em inglês; nada é traduzido). Fica salvo ao lado, como `… resumo.md`. O modelo do Mac não dá conta: o contexto dele é pequeno para uma hora de conversa.
- **Feedback:** para uma entrevista de emprego gravada numa chamada. Você é o "Você" (o microfone) e os entrevistadores são o áudio do Mac. Devolve um resumo, os seus pontos fortes, o que melhorar (a apresentação pessoal, a explicação de cada projeto, respostas sem exemplo concreto ou sem resultado) com uma formulação melhor para tentar, e cada pergunta do entrevistador avaliada como boa, parcial ou fraca. As frases sugeridas nunca inventam fatos: o que você não disse fica como lacuna entre colchetes, como `[quanto tempo economizou]`. Mesma regra de idioma do resumo: entrevista em inglês tem feedback em inglês. Fica salvo como `… entrevista.md`.
- **Notas da entrevista (Ajustes › Entrevista):** escolha uma pasta de notas de carreira em Markdown (um cofre do Obsidian serve) e teste uma pergunta de entrevistador: o Kanji responde com 3 a 5 tópicos tirados só das suas notas, cada um com a nota de onde veio, no idioma da pergunta. Ficam de fora as pastas ocultas, as começadas por `_` e as chamadas `arquivo` ou `archive`. As notas são lidas na hora e nunca copiadas; o texto delas e a pergunta vão para o seu provedor da nuvem, com cache de prompt para perguntas seguidas saírem baratas. É o passo 1 do modo entrevista em tempo real do [ROADMAP](docs/ROADMAP.md).
- **Arquivos:** um `.md` e um `.json` por sessão em `~/Library/Application Support/Kanji/Transcricoes`. Salvos trecho a trecho: se o app cair, o que já foi transcrito fica. Cada parágrafo tem a hora e quem falou.
- **Chamadas:** quando outro app (Zoom, Meet, Teams, FaceTime) abre o microfone, o Kanji põe o microfone na sessão sozinho, com cancelamento de eco, como "Você". Desliga 10 s depois que a chamada solta o microfone. Um vídeo não abre o microfone, então o som da sala fica de fora.
- **Quem falou (opcional):** *Ajustes › Geral › Transcrição do áudio do Mac › Separar quem fala* baixa uma vez um modelo de voz de ~15 MB (WeSpeaker ResNet34 convertido para Core ML, CC BY 4.0, do Hugging Face), conferido por SHA-256. Sem ele, tudo o que o Mac toca sai como "Outros".
- **Notch:** com o Kizami (app irmão que desenha uma ilha em volta do notch) aberto, a ilha dele mostra que o Kanji está transcrevendo, quando uma chamada põe o seu microfone e quando a transcrição foi salva. Só vão o estado e contagens, nunca o texto.
- **Recursos:** num podcast de 5 minutos, o Kanji usou ~8,5% de um núcleo e ~70 MB; o serviço de fala da Apple, mais ~11% e até ~200 MB.

## Privacidade

- **O áudio nunca sai do Mac.** A transcrição é do `SpeechAnalyzer` da Apple, on-device.
- **Com o modelo do Mac,** nada sai do computador.
- **Com um provedor da nuvem,** só o **texto** do ditado vai para ele, usando a **sua** chave e conforme os termos dele. O Kanji não tem servidor.
- **Chaves de API** ficam no Keychain.
- **Transcrições do áudio do Mac** ficam em `~/Library/Application Support/Kanji/Transcricoes`. O áudio nunca é salvo nem enviado; o modelo de voz só é baixado se você ligar *Separar quem fala*.
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
