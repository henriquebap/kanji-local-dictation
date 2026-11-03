# Distribuição

O caminho escolhido: **download direto notarizado + Homebrew** agora, **Mac App Store e iPhone** como fases seguintes. Como a licença é Apache 2.0 e o código é do autor, as duas lojas continuam abertas.

## 1. Pré-requisito: Apple Developer Program

- Inscrição em developer.apple.com/programs (US$ 99/ano), como pessoa física.
- Crie o certificado **Developer ID Application** pelo Xcode (Settings › Accounts › Manage Certificates) ou pelo portal. Ele vai para o Keychain.
- Crie uma senha de app em account.apple.com e guarde as credenciais de notarização no Keychain:

  ```bash
  xcrun notarytool store-credentials kanji --apple-id SEU_EMAIL --team-id SEU_TEAM_ID
  ```

  O comando pede a senha de app de forma interativa: ela não fica no histórico do shell.

Por que é obrigatório:
- **Gatekeeper:** sem assinatura Developer ID e notarização, o macOS bloqueia o app em qualquer outro Mac.
- **Permissões:** sem uma assinatura estável, o macOS esquece as permissões (Microfone, Acessibilidade) a cada versão.

## 2. Gerar um release

1. Suba a versão em `Resources/Info.plist`: `CFBundleShortVersionString` e `CFBundleVersion`.
2. Rode:

   ```bash
   make dist
   ```

   O `make dist` assina com Hardened Runtime e com `Resources/Kanji.entitlements` (a exceção do microfone), envia para notarização, grampeia o ticket e gera `build/Kanji-X.Y.Z.zip`. No fim, imprime o SHA-256.
3. Crie o release no GitHub com o zip:

   ```bash
   gh release create vX.Y.Z build/Kanji-X.Y.Z.zip --title "Kanji X.Y.Z" --notes "…"
   ```

## 3. Homebrew

Crie uma vez o repositório público `henriquebap/homebrew-tap`, com o arquivo `Casks/kanji.rb`:

```ruby
cask "kanji" do
  version "0.1.0"
  sha256 "SHA-256 impresso pelo make dist"

  url "https://github.com/henriquebap/kanji-local-dictation/releases/download/v#{version}/Kanji-#{version}.zip"
  name "Kanji"
  desc "Ditado com IA em português e inglês"
  homepage "https://github.com/henriquebap/kanji-local-dictation"

  depends_on arch: :arm64

  app "Kanji.app"

  zap trash: [
    "~/Library/Application Support/Kanji",
    "~/Library/Preferences/io.github.henriquebap.kanji.plist",
  ]
end
```

A cada release, atualize `version` e `sha256`. Quem usa instala com `brew install --cask henriquebap/tap/kanji`.

Quando o app tiver usuários suficientes, dá para enviar o cask para o `homebrew/cask` oficial e cortar o `henriquebap/tap/`.

## 4. Fases seguintes, sem mexer nas de cima

### Mac App Store
- **Sandbox obrigatório.** É preciso testar se a Acessibilidade e o ⌘V simulado passam na revisão (apps como o Paste fazem isso pela loja).
- **Entitlements:** microfone e rede (cliente).
- **Política de privacidade:** o texto vai para o provedor que a pessoa escolher.
- **Assinatura dentro do app:** a loja exige a compra pela Apple (StoreKit), com 15% de taxa no Small Business Program.

  Fora da loja, a assinatura pode passar por outro meio de pagamento.
- O build da loja pode conviver com o download direto: mesmo código, outra configuração de assinatura.

### iPhone
- **O que vai junto:** o núcleo (`SpeechAnalyzer`, Foundation Models, `Nuvem`, `Aprendizado`, regras) roda no iOS.
- **Escrever em outros apps:** só por um **teclado personalizado**. Teclado de terceiro não acessa o microfone, então o teclado abre o app, o app grava em segundo plano e o teclado insere o texto, como faz o Wispr Flow.
- **Pré-requisito:**
  - separar o núcleo num pacote Swift, com alvos macOS e iOS;
  - instalar o Xcode, que o iOS exige.
