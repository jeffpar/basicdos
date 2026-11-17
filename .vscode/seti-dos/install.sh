#!/bin/bash
#
# Builds and installs the "Seti DOS" file icon theme (selected by
# workbench.iconTheme in .vscode/settings.json): a copy of VS Code's built-in
# Seti theme that shows batch files with a CRT icon instead of a Windows logo.
# Rerun it after a VS Code update to pick up Seti's latest icons.
#
# Set VSCODE_APP if VS Code isn't in /Applications (eg, /usr/share/code).
#
set -e
APP=${VSCODE_APP:-"/Applications/Visual Studio Code.app/Contents/Resources/app"}
SETI="$APP/extensions/theme-seti"
CODE="$APP/bin/code"
SRC=$(cd "$(dirname "$0")" && pwd)
if [ ! -f "$SETI/icons/vs-seti-icon-theme.json" ]; then
	echo "Unable to find $SETI (set VSCODE_APP)"
	exit 1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
EXT="$TMP/extension"
mkdir -p "$EXT/icons"
cp "$SETI/icons/seti.woff" "$SETI/ThirdPartyNotices.txt" "$SRC"/crt*.svg "$EXT/icons/"

python3 - "$SETI/icons/vs-seti-icon-theme.json" "$EXT/icons/seti-dos-icon-theme.json" <<'EOF'
import json, sys
t = json.load(open(sys.argv[1]))
t['iconDefinitions']['_crt'] = {'iconPath': './crt.svg'}
t['iconDefinitions']['_crt_light'] = {'iconPath': './crt_light.svg'}
t['languageIds']['bat'] = '_crt'
t['light']['languageIds']['bat'] = '_crt_light'
json.dump(t, open(sys.argv[2], 'w'), indent=1)
EOF

DESC="VS Code's Seti file icons, with a CRT icon for batch files"
cat > "$EXT/package.json" <<EOF
{
  "name": "seti-dos",
  "displayName": "Seti DOS File Icons",
  "description": "$DESC",
  "publisher": "local",
  "version": "1.0.0",
  "license": "MIT",
  "engines": { "vscode": "^1.60.0" },
  "categories": ["Themes"],
  "contributes": {
    "iconThemes": [{
      "id": "vs-seti-dos",
      "label": "Seti DOS",
      "path": "./icons/seti-dos-icon-theme.json"
    }]
  }
}
EOF
cat > "$TMP/extension.vsixmanifest" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0"
 xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="seti-dos" Version="1.0.0" Publisher="local"/>
    <DisplayName>Seti DOS File Icons</DisplayName>
    <Description xml:space="preserve">$DESC</Description>
    <Categories>Themes</Categories>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.60.0"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest"
     Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
EOF
cat > "$TMP/[Content_Types].xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension=".json" ContentType="application/json"/>
<Default Extension=".vsixmanifest" ContentType="text/xml"/>
<Default Extension=".svg" ContentType="image/svg+xml"/>
<Default Extension=".woff" ContentType="application/font-woff"/>
<Default Extension=".txt" ContentType="text/plain"/>
</Types>
EOF

(cd "$TMP" && zip -qr seti-dos.vsix "[Content_Types].xml" \
	extension.vsixmanifest extension)
"$CODE" --install-extension "$TMP/seti-dos.vsix" --force
