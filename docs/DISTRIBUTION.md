# Distribution

The chosen path: **notarized direct download + Homebrew** now, **Mac App Store and iPhone** as the next phases. Since the license is Apache 2.0 and the code belongs to the author, both stores remain open.

## 1. Prerequisite: Apple Developer Program

- Enroll at developer.apple.com/programs (US$ 99/year) as an individual.
- Create the **Developer ID Application** certificate in Xcode (Settings › Accounts › Manage Certificates) or on the portal. It goes into the Keychain.
- Create an app-specific password at account.apple.com and store the notarization credentials in the Keychain:

  ```bash
  xcrun notarytool store-credentials kanji --apple-id SEU_EMAIL --team-id SEU_TEAM_ID
  ```

  The command asks for the app-specific password interactively, so it doesn't end up in the shell history.

Why it's required:
- **Gatekeeper:** without a Developer ID signature and notarization, macOS blocks the app on any other Mac.
- **Permissions:** without a stable signature, macOS forgets the permissions (Microphone, Accessibility) on every version.

## 2. Build a release

1. Bump the version in `Resources/Info.plist`: `CFBundleShortVersionString` and `CFBundleVersion`.
2. Run:

   ```bash
   make dist
   ```

   `make dist` signs with the Hardened Runtime and `Resources/Kanji.entitlements` (the microphone exception), submits for notarization, staples the ticket and produces `build/Kanji-X.Y.Z.zip`. At the end it prints the SHA-256.
3. Create the GitHub release with the zip:

   ```bash
   gh release create vX.Y.Z build/Kanji-X.Y.Z.zip --title "Kanji X.Y.Z" --notes "…"
   ```

## 3. Homebrew

Create the public repository `henriquebap/homebrew-tap` once, with the file `Casks/kanji.rb`:

```ruby
cask "kanji" do
  version "0.1.0"
  sha256 "SHA-256 impresso pelo make dist"

  url "https://github.com/henriquebap/kanji-local-dictation/releases/download/v#{version}/Kanji-#{version}.zip"
  name "Kanji"
  desc "Local AI dictation for Mac in Portuguese and English"
  homepage "https://github.com/henriquebap/kanji-local-dictation"

  depends_on arch: :arm64

  app "Kanji.app"

  zap trash: [
    "~/Library/Application Support/Kanji",
    "~/Library/Preferences/io.github.henriquebap.kanji.plist",
  ]
end
```

On every release, update `version` and `sha256`. Users install it with `brew install --cask henriquebap/tap/kanji`.

Once the app has enough users, the cask can be submitted to the official `homebrew/cask` and the `henriquebap/tap/` prefix dropped.

## 4. Next phases, without touching the ones above

### Mac App Store
- **Sandbox is mandatory.** We need to test whether Accessibility and the simulated ⌘V pass review (apps like Paste do this in the store).
- **Entitlements:** microphone and network (client).
- **Privacy policy:** the text goes to the provider the user chooses.
- **In-app subscription:** the store requires purchase through Apple (StoreKit), with a 15% fee under the Small Business Program.

  Outside the store, the subscription can go through another payment method.
- The store build can coexist with the direct download: same code, different signing configuration.

### iPhone
- **What carries over:** the core (`SpeechAnalyzer`, Foundation Models, `Nuvem`, `Aprendizado`, rules) runs on iOS.
- **Typing into other apps:** only through a **custom keyboard**. Third-party keyboards can't access the microphone, so the keyboard opens the app, the app records in the background and the keyboard inserts the text, like Wispr Flow does.
- **Prerequisite:**
  - split the core into a Swift package, with macOS and iOS targets;
  - install Xcode, which iOS requires.
