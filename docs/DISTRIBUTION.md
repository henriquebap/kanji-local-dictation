# Distribution

**Current decision (2026-11-03): free only.** Kanji is not enrolled in the Apple Developer Program (US$ 99/year) for now. Everything below the "Later" heading is kept for when that changes; the free path doesn't depend on it.

| Path | Cost | What the user sees | Status |
|---|---|---|---|
| Build from source (`make install`) | Free | No warning: macOS trusts apps built on the same Mac | ✅ Available |
| Download from GitHub Releases | Free | One-time "Open Anyway" in System Settings | ✅ Available |
| Homebrew | Needs Apple notarization | `brew install --cask …` | ⏸ Later (Homebrew 5 requires notarized casks) |
| Mac App Store / iPhone | US$ 99/year | Store install | ⏸ Later |

The user-facing install steps live in the [README](../README.md#install). This page is for the **maintainer**: how to publish a version.

## Publishing a free release

The goal of a release is a downloadable `Kanji-X.Y.Z.zip` on the GitHub Releases page that people can install with Option B of the README.

### 1. Create the signing certificate (once)
**Goal:** sign every release with the same identity. macOS ties Microphone and Accessibility permissions to the app's signature. When all versions share one signature, people who update keep their permissions; with ad-hoc signatures they'd have to allow everything again on each update.

```bash
./scripts/dev-certificate.sh
```

This creates the self-signed "Kanji Dev" certificate in your login keychain. It's free, it lasts 10 years, and it never leaves your Mac. Keep it: a new certificate means a new signature, and everyone has to re-allow the permissions once. To move it to another Mac, export it from Keychain Access as a `.p12`.

It doesn't remove the Gatekeeper warning. Only Apple's notarization does that.

### 2. Bump the version
**Goal:** the app, the zip name and the release tag say the same version, so users know what they have.

In `Resources/Info.plist`, increase `CFBundleShortVersionString` (e.g. `0.1.0` → `0.2.0`) and `CFBundleVersion` (e.g. `1` → `2`).

### 3. Check that the code is ready
**Goal:** never publish a build that fails the tests.

```bash
make teste
swift scripts/check-localization.swift
```

### 4. Build the zip
**Goal:** one file containing the signed app.

```bash
make clean && make zip
```

This builds `build/Kanji.app`, signs it with "Kanji Dev" and creates `build/Kanji-X.Y.Z.zip`. It also prints the zip's SHA-256: publish that value so people can check the download wasn't tampered with. If the certificate is missing, `make zip` warns that the app will be ad-hoc signed.

### 5. Test it like a user
**Goal:** see exactly what a new user sees before anyone else does.

1. Upload the zip somewhere (a draft release works: add `--draft` in step 6).
2. Download it with the browser. That adds the same "downloaded from the internet" mark a user's copy gets.
3. Follow Option B of the README: unzip, open, *Open Anyway*.

### 6. Publish on GitHub
**Goal:** put the zip where the README's download link points.

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z build/Kanji-X.Y.Z.zip --title "Kanji X.Y.Z" --notes-file notas.md
```

Suggested release notes (`notas.md`):

```markdown
## What's new
- …

## Install
1. Download `Kanji-X.Y.Z.zip`, unzip it and drag `Kanji.app` to Applications.
2. Open it. macOS will say it can't verify the developer: click **Done**.
3. Go to System Settings › Privacy & Security › Security and click **Open Anyway**.

Kanji isn't notarized by Apple yet (that requires a paid membership), which is why macOS asks once.
Prefer no warning at all? Build it from source: see the README.

SHA-256: `…`
```

## Later: Apple Developer Program (paid)

What US$ 99/year would unlock:
- **No Gatekeeper warning** on download (Developer ID + notarization).
- **Homebrew:** `brew install --cask`.
- **Mac App Store and iPhone.**

The tooling is already in place:
- `make dist` signs with the Hardened Runtime and `Resources/Kanji.entitlements`, notarizes and staples;
- the steps are below.

### Developer ID and notarization
1. Enroll at developer.apple.com/programs as an individual. Approval can take up to 48 h.
2. Create a **Developer ID Application** certificate:
   1. In Keychain Access › Certificate Assistant › *Request a Certificate From a Certificate Authority*, save a CSR to disk.
   2. Upload it at developer.apple.com/account/resources/certificates/add, then install the `.cer` you get back.
3. Create an app-specific password at account.apple.com, then store the credentials. The command asks for the password interactively.

   ```bash
   xcrun notarytool store-credentials kanji --apple-id SEU_EMAIL --team-id SEU_TEAM_ID
   ```
4. Run `make dist`, then check that `spctl -a -vvv -t install build/Kanji.app` reports `source=Notarized Developer ID`.
5. Publish the zip as in the free path.

Switching from "Kanji Dev" to Developer ID changes the signature, so users re-allow the permissions once.

### Homebrew
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

On every release, update `version` and `sha256`. Users install it with `brew install --cask henriquebap/tap/kanji`. Once the app has enough users, the cask can go to the official `homebrew/cask`.

### Mac App Store
- **Sandbox is mandatory.** We need to test whether Accessibility and the simulated ⌘V pass review (apps like Paste do this in the store).
- **Entitlements:** microphone and network (client).
- **Privacy policy:** the text goes to the provider the user chooses.
- **In-app subscription:** the store requires purchase through Apple (StoreKit), with a 15% fee under the Small Business Program. Outside the store, the subscription can go through another payment method.
- The store build can coexist with the direct download: same code, different signing configuration.

### iPhone
- **What carries over:** the core (`SpeechAnalyzer`, Foundation Models, `Nuvem`, `Aprendizado`, rules) runs on iOS.
- **Typing into other apps:** only through a **custom keyboard**. Third-party keyboards can't access the microphone, so the keyboard opens the app, the app records in the background and the keyboard inserts the text, like Wispr Flow does.
- **Prerequisite:**
  - split the core into a Swift package, with macOS and iOS targets;
  - install Xcode, which iOS requires.
