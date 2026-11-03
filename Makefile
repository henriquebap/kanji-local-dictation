# Build sem SwiftPM: só precisa das Command Line Tools (xcode-select --install).
APP := build/Kanji.app
# Identidade estável mantém as permissões entre builds (scripts/certificado-dev.sh); sem ela, ad-hoc.
IDENTIDADE := $(shell security find-certificate -c "Kanji Dev" >/dev/null 2>&1 && echo "Kanji Dev" || echo -)
SRC := $(wildcard Sources/Kanji/*.swift)

app: $(APP)

$(APP): $(SRC) Resources/Info.plist Resources/AppIcon.icns
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	swiftc -O -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 $(SRC) -o "$(APP)/Contents/MacOS/Kanji"
	codesign --force --sign "$(IDENTIDADE)" "$(APP)"

run: app
	-pkill -x Kanji
	open "$(APP)"

install: app
	-pkill -x Kanji
	rm -rf /Applications/Kanji.app
	cp -R "$(APP)" /Applications/
	open /Applications/Kanji.app

teste:
	mkdir -p build
	swiftc -parse-as-library -swift-version 6 -target arm64-apple-macosx27.0 Tests/*.swift Sources/Kanji/Correcao.swift Sources/Kanji/Revisao.swift Sources/Kanji/Fusao.swift Sources/Kanji/Historico.swift Sources/Kanji/Aprendizado.swift -o build/teste
	./build/teste

# Release para distribuir fora da App Store: Developer ID + Hardened Runtime + notarização (docs/DISTRIBUICAO.md).
DEV_ID ?= Developer ID Application
VERSAO := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP := build/Kanji-$(VERSAO).zip

dist: $(APP)
	codesign --force --options runtime --timestamp --entitlements Resources/Kanji.entitlements --sign "$(DEV_ID)" "$(APP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	xcrun notarytool submit "$(ZIP)" --keychain-profile kanji --wait
	xcrun stapler staple "$(APP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"  # de novo, agora com o ticket grampeado
	shasum -a 256 "$(ZIP)"

clean:
	rm -rf build

.PHONY: app run install teste dist clean
