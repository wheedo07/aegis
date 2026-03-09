#!/usr/bin/env bash
# aegis CLI 설치 스크립트
set -euo pipefail

AEGIS_VERSION=0.0.1
AEGIS_ZIP_URL="https://raw.githubusercontent.com/wheedo07/aegis/refs/heads/master/build/aegis.zip"
INSTALL_DIR="/usr/local/lib/aegis"
BIN_PATH="/usr/local/bin/aegis"

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERR]${NC}   $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root 권한이 필요합니다. sudo 를 사용하세요."

# curl 확인
command -v curl &>/dev/null || die "curl 이 필요합니다. 먼저 curl 을 설치하세요."
command -v unzip &>/dev/null || {
    info "unzip 설치 중..."
    if command -v apt-get &>/dev/null; then
        apt-get install -y unzip
    elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
        yum install -y unzip 2>/dev/null || dnf install -y unzip
    else
        die "unzip 이 필요합니다. 설치해주세요."
    fi
}

info "aegis v$AEGIS_VERSION 설치 중..."

if [[ -x "$BIN_PATH" ]]; then
    current=$("$BIN_PATH" version 2>/dev/null || echo "unknown")
    warn "이미 설치되어 있습니다: $current → 재설치합니다."
fi

tmpdir=$(mktemp -d)
trap "rm -rf '$tmpdir'" EXIT

info "aegis.zip 다운로드 중..."
if ! curl -fsSL "$AEGIS_ZIP_URL" -o "$tmpdir/aegis.zip"; then
    die "다운로드 실패: $AEGIS_ZIP_URL"
fi

unzip -t "$tmpdir/aegis.zip" &>/dev/null || die "다운로드된 파일이 올바른 zip 형식이 아닙니다."

unzip -q "$tmpdir/aegis.zip" -d "$tmpdir/pkg"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/systemd"

cp "$tmpdir/pkg/aegis"              "$INSTALL_DIR/aegis"
cp "$tmpdir/pkg/lib/"*.sh           "$INSTALL_DIR/lib/"
[[ -d "$tmpdir/pkg/systemd" ]] && \
    cp "$tmpdir/pkg/systemd/"*  "$INSTALL_DIR/systemd/" 2>/dev/null || true

chmod +x "$INSTALL_DIR/aegis"
chmod +x "$INSTALL_DIR/lib/"*.sh

# /usr/local/bin 에 심볼릭 링크
ln -sf "$INSTALL_DIR/aegis" "$BIN_PATH"

success "aegis v$AEGIS_VERSION 설치 완료!"
info "설치 경로: $INSTALL_DIR"
info "실행 경로: $BIN_PATH"
echo ""
info "사용법:"
info "  sudo aegis install agent    # Apache 모듈 설치"
info "  aegis help                  # 전체 도움말"