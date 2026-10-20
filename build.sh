#!/bin/bash
# CiyuanWallpaper 一键构建脚本（Linux）
# 产出: entry/build/default/outputs/default/entry-default-signed.hap
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGNING_DIR="${SIGNING_DIR:-/workspace/signing}"
SDK_HOME="${DEVECO_SDK_HOME:-/opt/harmony-cli/x/command-line-tools}"
HST_JAR="$SDK_HOME/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar"

echo "==> [1/4] 检查 HarmonyOS Command Line Tools"
if [ ! -x "$SDK_HOME/bin/hvigorw" ]; then
  echo "未找到 CLI Tools: $SDK_HOME"
  echo "请从 https://developer.huawei.com/consumer/cn/download/ 下载 command-line-tools 并解压，"
  echo "然后设置 DEVECO_SDK_HOME 环境变量指向解压目录。"
  exit 1
fi

echo "==> [2/4] 生成/复用签名密钥链与 Provision Profile"
mkdir -p "$SIGNING_DIR"
cd "$SIGNING_DIR"

if [ ! -f app.jks ] || [ ! -f profile.jks ] || [ ! -f ciyuan-debug.p7b ]; then
  bash gen_keys.sh
  # 把应用 leaf 证书写入 Provision Profile 的 development-certificate（debug 类型必需）
  python3 - <<'PYEOF'
import json, re
chain = open('app-debug-cert.cer', encoding='utf-8').read()
leaf = re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', chain, re.S).group(0)
p = json.load(open('ciyuan-debug-profile.json', encoding='utf-8'))
p['bundle-info']['development-certificate'] = leaf + "\n"
json.dump(p, open('ciyuan-debug-profile.json', 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
PYEOF
  java -jar "$HST_JAR" sign-profile -mode localSign \
    -keyAlias "oh-profile-key-v1" -keyPwd CiyuanWallpaperDebug2026KeyPwd0001 \
    -profileCertFile profile-debug-cert.cer \
    -inFile ciyuan-debug-profile.json -signAlg SHA256withECDSA \
    -keystoreFile profile.jks -keystorePwd CiyuanWallpaperDebug2026KeyPwd0001 \
    -outFile ciyuan-debug.p7b

  # 生成 DevEco 加密格式的密码材料（hvigor 需要 material/ 目录 + 加密密码）
  if [ ! -d material ]; then
    ENC=$(node gen_material.js "$SIGNING_DIR" 'CiyuanWallpaperDebug2026KeyPwd0001')
    python3 - "$ENC" <<'PYEOF'
import re, sys
enc = sys.argv[1].strip()
p = '/workspace/CiyuanWallpaper/build-profile.json5'
s = open(p, encoding='utf-8').read()
s = re.sub(r'"keyPassword": "[0-9a-f]+"', '"keyPassword": "%s"' % enc, s)
s = re.sub(r'"storePassword": "[0-9a-f]+"', '"storePassword": "%s"' % enc, s)
open(p, 'w', encoding='utf-8').write(s)
PYEOF
  fi
  echo "签名材料已就绪: $SIGNING_DIR"
else
  echo "签名材料已存在，跳过生成"
fi

echo "==> [3/4] 同步签名材料路径到 build-profile.json5"
python3 - "$SIGNING_DIR" <<'PYEOF'
import re, sys
sd = sys.argv[1]
p = '/workspace/CiyuanWallpaper/build-profile.json5'
s = open(p, encoding='utf-8').read()
s = re.sub(r'"certpath": "[^"]*"', '"certpath": "%s/app-debug-cert.cer"' % sd, s)
s = re.sub(r'"profile": "[^"]*"', '"profile": "%s/ciyuan-debug.p7b"' % sd, s)
s = re.sub(r'"storeFile": "[^"]*"', '"storeFile": "%s/app.jks"' % sd, s)
open(p, 'w', encoding='utf-8').write(s)
PYEOF

echo "==> [4/4] 构建 HAP"
cd "$PROJECT_DIR"
export NODE_HOME="${NODE_HOME:-/root/.nvm/versions/node/v22.13.1}"
export DEVECO_SDK_HOME="$SDK_HOME"
./hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon

HAP="$PROJECT_DIR/entry/build/default/outputs/default/entry-default-signed.hap"
echo ""
echo "=========================================="
echo "构建成功: $HAP"
ls -la "$HAP"
echo ""
echo "安装到设备:"
echo "  hdc app install $HAP"
echo "=========================================="
