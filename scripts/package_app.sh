#!/bin/zsh
set -e

mkdir -p FinancialControl.app/Contents/MacOS
mkdir -p FinancialControl.app/Contents/Resources

if [ -f .build/release/FinancialControl ]; then
    cp .build/release/FinancialControl FinancialControl.app/Contents/MacOS/FinancialControl
elif [ -f .build/debug/FinancialControl ]; then
    cp .build/debug/FinancialControl FinancialControl.app/Contents/MacOS/FinancialControl
fi

chmod +x FinancialControl.app/Contents/MacOS/FinancialControl

# Gerar ou copiar o arquivo de ícone AppIcon.icns
if [ -d "Sources/FinancialControl/Resources/AppIcon.iconset" ]; then
    iconutil -c icns Sources/FinancialControl/Resources/AppIcon.iconset -o FinancialControl.app/Contents/Resources/AppIcon.icns
elif [ -f "Sources/FinancialControl/Resources/AppIcon.icns" ]; then
    cp Sources/FinancialControl/Resources/AppIcon.icns FinancialControl.app/Contents/Resources/AppIcon.icns
fi

if [ -f "Sources/FinancialControl/Resources/AppIcon.png" ]; then
    cp Sources/FinancialControl/Resources/AppIcon.png FinancialControl.app/Contents/Resources/AppIcon.png
fi

# Copiar bundle de recursos do SPM se existir
for bundle in .build/**/FinancialControl_FinancialControl.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" FinancialControl.app/Contents/Resources/
        break
    fi
done

cat > FinancialControl.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FinancialControl</string>
    <key>CFBundleIdentifier</key>
    <string>br.com.clovis.FinancialControl</string>
    <key>CFBundleName</key>
    <string>Controle Financeiro</string>
    <key>CFBundleDisplayName</key>
    <string>Controle Financeiro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

touch FinancialControl.app

echo "App nativo empacotado com sucesso em FinancialControl.app"
