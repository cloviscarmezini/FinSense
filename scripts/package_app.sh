#!/bin/zsh
set -e

mkdir -p FinSense.app/Contents/MacOS
mkdir -p FinSense.app/Contents/Resources

if [ -f .build/release/FinSense ]; then
    cp .build/release/FinSense FinSense.app/Contents/MacOS/FinSense
elif [ -f .build/debug/FinSense ]; then
    cp .build/debug/FinSense FinSense.app/Contents/MacOS/FinSense
fi

chmod +x FinSense.app/Contents/MacOS/FinSense

# Gerar ou copiar o arquivo de ícone AppIcon.icns
if [ -d "Sources/FinSense/Resources/AppIcon.iconset" ]; then
    iconutil -c icns Sources/FinSense/Resources/AppIcon.iconset -o FinSense.app/Contents/Resources/AppIcon.icns
elif [ -f "Sources/FinSense/Resources/AppIcon.icns" ]; then
    cp Sources/FinSense/Resources/AppIcon.icns FinSense.app/Contents/Resources/AppIcon.icns
fi

if [ -f "Sources/FinSense/Resources/AppIcon.png" ]; then
    cp Sources/FinSense/Resources/AppIcon.png FinSense.app/Contents/Resources/AppIcon.png
fi

# Copiar bundle de recursos do SPM se existir
for bundle in .build/**/FinSense_FinSense.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" FinSense.app/Contents/Resources/
        break
    fi
done

cat > FinSense.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FinSense</string>
    <key>CFBundleIdentifier</key>
    <string>br.com.clovis.FinSense</string>
    <key>CFBundleName</key>
    <string>FinSense</string>
    <key>CFBundleDisplayName</key>
    <string>FinSense</string>
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

touch FinSense.app

echo "App nativo empacotado com sucesso em FinSense.app"
