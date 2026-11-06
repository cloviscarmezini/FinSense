#!/bin/zsh
set -e

echo "🚀 Iniciando build de produção e distribuição do Controle Financeiro..."

# 1. Compilar em modo release
echo "📦 Compilando binário otimizado de release..."
swift build -c release

# 2. Empacotar o bundle nativo .app
echo "🎨 Empacotando FinancialControl.app com ícones e metadados..."
zsh scripts/package_app.sh

# 3. Assinatura de código (Ad-hoc ou Developer ID se fornecido)
echo "🔏 Assinando o aplicativo..."
if [ -n "$DEVELOPER_ID" ]; then
    echo "Assinando com certificado: $DEVELOPER_ID"
    codesign --force --deep --options runtime --sign "$DEVELOPER_ID" FinancialControl.app
else
    echo "Assinando com ad-hoc signature (adequado para distribuição direta)..."
    codesign --force --deep --sign - FinancialControl.app
fi

# 4. Criar pasta de saída
mkdir -p dist
rm -rf dist/*

# 5. Gerar arquivo ZIP preservando permissões e atributos macOS
echo "🗜️ Gerando dist/FinancialControl.zip..."
ditto -c -k --keepParent FinancialControl.app dist/FinancialControl.zip

# 6. Gerar instalador DMG (imagem de disco amigável com atalho para /Applications)
echo "💿 Gerando dist/FinancialControl.dmg..."
STAGING_DIR=$(mktemp -d)
cp -R FinancialControl.app "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "Controle Financeiro" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    dist/FinancialControl.dmg

rm -rf "$STAGING_DIR"

echo ""
echo "✅ Build de distribuição concluído com sucesso!"
echo "Arquivos gerados na pasta 'dist/':"
ls -lh dist/
