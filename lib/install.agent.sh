#!/usr/bin/env bash
# aegis install 서브커맨드 구현

MOD_ZIP_URL="https://raw.githubusercontent.com/wheedo07/aegis-agent/refs/heads/master/build/aegis-mod.zip"

AEGIS_CONF_DIR="/etc/aegis"
AEGIS_RUN_DIR="/var/run/aegis"

# ------------------------------------------------------------------ #

install_agent() {
    require_root

    info "aegis-agent 설치를 시작합니다..."

    _check_apache
    _install_build_deps
    _install_mod
    _create_dirs
    _write_apache_conf
    _write_agent_conf

    echo ""
    success "aegis-agent 설치 완료!"
    info "다음 단계:"
    info "  1. $AEGIS_CONF_DIR/agent.conf 에서 server_url 설정"
    info "  2. Apache 설정에 AegisEnabled On 추가 후 재시작"
    info "     (예시: /etc/apache2/conf-available/aegis.conf 참고)"
}

# ------------------------------------------------------------------ #
# 내부 함수

_check_apache() {
    info "Apache 설치 확인 중..."

    # apache2 (Debian) 또는 httpd (RHEL) 확인
    if ! command -v apache2 &>/dev/null && ! command -v httpd &>/dev/null; then
        die "Apache가 설치되어 있지 않습니다. 먼저 Apache를 설치하세요."
    fi

    # apxs 경로 탐색 (설치 전이라 없을 수 있음 - 여기선 존재 여부만 확인)
    if systemctl list-units --type=service 2>/dev/null | grep -qE 'apache2|httpd'; then
        success "Apache 확인됨"
    else
        warn "Apache 서비스를 찾지 못했습니다. 계속 진행합니다."
    fi
}

_install_build_deps() {
    info "빌드 의존성 설치 중..."

    # apxs 가 이미 있으면 스킵
    if command -v apxs &>/dev/null || command -v apxs2 &>/dev/null; then
        # curl, unzip 만 확인
        local os; os=$(detect_os)
        case "$os" in
            debian) pkg_install --no-upgrade curl unzip ;;
            rhel)   pkg_install curl unzip ;;
        esac
    else
        local os; os=$(detect_os)
        case "$os" in
            debian) pkg_install apache2-dev build-essential curl unzip ;;
            rhel)   pkg_install httpd-devel gcc make curl unzip ;;
            *)      die "apxs 를 찾을 수 없습니다. apache 개발 패키지를 수동으로 설치하세요." ;;
        esac
    fi

    # 최종 apxs 경로 결정
    if   command -v apxs2 &>/dev/null; then APXS="apxs2"
    elif command -v apxs  &>/dev/null; then APXS="apxs"
    else die "apxs 설치 후에도 찾을 수 없습니다."; fi

    success "빌드 의존성 준비 완료 (apxs: $APXS)"
}

_install_mod() {
    info "aegis-mod 소스 다운로드 중..."

    local tmpdir; tmpdir=$(mktemp -d)
    # 함수 종료 시(오류 포함) 임시 디렉토리 정리
    trap "rm -rf '$tmpdir'" RETURN

    # 다운로드
    if ! curl -fsSL "$MOD_ZIP_URL" -o "$tmpdir/aegis-mod.zip"; then
        die "다운로드 실패: $MOD_ZIP_URL"
    fi

    # zip 유효성 확인
    if ! unzip -t "$tmpdir/aegis-mod.zip" &>/dev/null; then
        die "다운로드된 파일이 올바른 zip 형식이 아닙니다."
    fi

    unzip -q "$tmpdir/aegis-mod.zip" -d "$tmpdir"

    local moddir="$tmpdir/module"
    if [[ ! -d "$moddir" ]]; then
        die "zip 파일 내에 'module/' 디렉토리가 없습니다."
    fi

    # 필수 소스 파일 확인
    for f in aegis_mod.c aegis_mod.config.c aegis_mod.collector.c; do
        [[ -f "$moddir/$f" ]] || die "필수 소스 파일 없음: $f"
    done

    info "aegis_mod.so 빌드 중..."

    pushd "$moddir" > /dev/null
        # 여러 .c 를 한 번에 컴파일 → aegis_mod.so 생성
        $APXS -c \
            aegis_mod.c \
            aegis_mod.config.c \
            aegis_mod.collector.c
    popd > /dev/null

    local so="$moddir/.libs/aegis_mod.so"
    [[ -f "$so" ]] || die ".so 빌드 결과물을 찾을 수 없습니다: $so"

    info "aegis_mod.so 설치 중..."

    # -i: 설치, -n: 모듈 이름 (LoadModule aegis_module ...)
    # -a 는 사용하지 않음: Debian/RHEL 에 따라 활성화 방법이 다르기 때문
    $APXS -i -n aegis "$so"

    # 모듈 활성화
    local os; os=$(detect_os)
    case "$os" in
        debian)
            if command -v a2enmod &>/dev/null; then
                a2enmod aegis
                success "a2enmod aegis 완료"
            else
                warn "a2enmod 를 찾을 수 없습니다. 수동으로 LoadModule 을 추가하세요."
            fi
            ;;
        rhel)
            # apxs -i 가 /etc/httpd/modules/ 에 복사함
            # LoadModule 은 aegis.conf 에서 처리
            ;;
    esac

    success "aegis_mod.so 설치 완료"
}

_create_dirs() {
    info "런타임 디렉토리 생성 중..."
    mkdir -p "$AEGIS_CONF_DIR" "$AEGIS_RUN_DIR"
    chmod 755 "$AEGIS_RUN_DIR"
    success "디렉토리 준비 완료"
}

_write_apache_conf() {
    info "Apache 모듈 설정 파일 작성 중..."

    local os; os=$(detect_os)

    if [[ "$os" == "debian" && -d "/etc/apache2/conf-available" ]]; then
        local conf="/etc/apache2/conf-available/aegis.conf"
        if [[ -f "$conf" ]]; then
            warn "$conf 이미 존재합니다. 덮어쓰지 않습니다."
            return
        fi
        cat > "$conf" <<'EOF'
# -------------------------------------------------------
# aegis-mod Apache 설정
# AegisEnabled On 을 원하는 Location/Directory 블록에 추가
# -------------------------------------------------------
AegisAgentSocket  /var/run/aegis/agent.sock
AegisTimeout      200
AegisFailOpen     On
# AegisControlURL https://your-aegis-server.example.com

# 전체 사이트에 적용하려면 아래 주석을 해제
# <Location />
#     AegisEnabled On
# </Location>
EOF
        a2enconf aegis 2>/dev/null || true
        success "Apache 설정 저장됨: $conf"

    elif [[ "$os" == "rhel" && -d "/etc/httpd/conf.d" ]]; then
        local conf="/etc/httpd/conf.d/aegis.conf"
        if [[ -f "$conf" ]]; then
            warn "$conf 이미 존재합니다. 덮어쓰지 않습니다."
            return
        fi
        # RHEL은 a2enmod 가 없으므로 conf.d 에 LoadModule 도 함께 작성
        cat > "$conf" <<'EOF'
LoadModule aegis_module modules/aegis_mod.so

AegisAgentSocket  /var/run/aegis/agent.sock
AegisTimeout      200
AegisFailOpen     On
# AegisControlURL https://your-aegis-server.example.com

# <Location />
#     AegisEnabled On
# </Location>
EOF
        success "Apache 설정 저장됨: $conf"
    else
        warn "Apache 설정 디렉토리를 찾지 못했습니다. 수동으로 설정하세요."
    fi
}

_write_agent_conf() {
    local conf="$AEGIS_CONF_DIR/agent.conf"
    if [[ -f "$conf" ]]; then
        warn "$conf 이미 존재합니다. 덮어쓰지 않습니다."
        return
    fi
    info "에이전트 기본 설정 파일 작성 중..."
    cat > "$conf" <<EOF
# aegis-agent 설정
server_url    = http://localhost:8080
agent_socket  = /var/run/aegis/agent.sock
fail_open     = true
timeout_ms    = 200
EOF
    success "에이전트 설정 저장됨: $conf"
}