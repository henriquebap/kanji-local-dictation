#!/bin/bash
# Cria o certificado "Kanji Dev" no seu Keychain para assinar as builds sempre com a mesma identidade.
# Sem isso, cada build tem assinatura ad-hoc diferente e o macOS pede Microfone/Acessibilidade de novo.
# Rodar uma vez só. Pede a senha do Mac para confiar no certificado para assinatura de código.
set -euo pipefail
NOME="Kanji Dev"
if security find-certificate -c "$NOME" >/dev/null 2>&1; then
  echo "Certificado \"$NOME\" já existe."; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NOME" \
  -keyout "$TMP/chave.pem" -out "$TMP/cert.pem" \
  -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/chave.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:kanji
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P kanji -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$TMP/cert.pem"
echo "Pronto. As próximas builds (make app) saem assinadas com \"$NOME\"."
