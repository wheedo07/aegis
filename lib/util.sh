#!/usr/bin/env bash

# 공통 유틸리티: 로그 출력, OS 감지, 패키지 설치
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }
die()     { error "$*"; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "root 권한이 필요합니다. sudo 를 사용하세요."
}

# 반환값: "debian" | "rhel" | "unknown"
detect_os() {
    if command -v apt-get &>/dev/null; then
        echo "debian"
    elif command -v dnf &>/dev/null; then
        echo "rhel"
    elif command -v yum &>/dev/null; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

pkg_install() {
    local os; os=$(detect_os)
    case "$os" in
        debian) apt-get install -y "$@" ;;
        rhel)   yum install -y "$@" ;;
        *)      die "지원하지 않는 패키지 매니저입니다." ;;
    esac
}