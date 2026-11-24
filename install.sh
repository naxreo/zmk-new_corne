#!/usr/bin/env bash
# build.sh 실행에 필요한 도구를 점검·설치하고, 공통 빌드 파일을 다른 ZMK 저장소에 복사하는 스크립트
#
# 사용법
#   ./install.sh                       도구 점검·설치 (Docker 확인, uv·librsvg 설치, 빌드 이미지·keymap-drawer 받기)
#   ./install.sh --check               설치 없이 점검만
#   ./install.sh --copy-to <저장소>    공통 파일(build.sh, install.sh, scripts/key_positions.py, BUILD.md)을 복사
#                                      대상에 build.env 가 없으면 견본을 만든다
#
# macOS + Homebrew 기준이다. Docker Desktop 은 직접 설치·실행해야 한다.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="zmkfirmware/zmk-build-arm:stable"
COMMON_FILES=(build.sh install.sh scripts/key_positions.py BUILD.md)

OK=0; FAIL=0
ok()   { echo "  [OK] $*"; OK=$((OK + 1)); }
fail() { echo "  [실패] $*"; FAIL=$((FAIL + 1)); }

# 공통 파일을 다른 저장소로 복사
copy_to() {
    local DEST="$1"
    [ -d "$DEST/config" ] || { echo "ZMK 설정 저장소가 아니다 (config/ 없음): $DEST"; exit 1; }
    for f in "${COMMON_FILES[@]}"; do
        mkdir -p "$DEST/$(dirname "$f")"
        cp "$REPO_DIR/$f" "$DEST/$f" && echo "복사: $f"
    done
    chmod +x "$DEST/build.sh" "$DEST/install.sh"
    if [ ! -f "$DEST/build.env" ]; then
        local kb
        kb=$(basename "$(ls "$DEST"/config/*.keymap 2>/dev/null | head -1)" .keymap)
        cat >"$DEST/build.env" <<EOF
# build.sh 가 읽는 이 저장소의 설정 (항목 설명은 BUILD.md)
KEYBOARD=$kb
TITLE="$kb"
VOLUME=zmk-ws-$(basename "$(cd "$DEST" && pwd)")
DRAW_LAYOUT_ARGS=""
MIDDLE_KEYS=""
EOF
        echo "생성: build.env (KEYBOARD=$kb, 값 확인 필요)"
    fi
    echo "다음 단계: $DEST/build.env 확인 → ./build.sh --draw-only 로 그림 확인 → ./build.sh"
}

CHECK_ONLY=0
case "${1:-}" in
    --copy-to) [ -n "${2:-}" ] || { echo "복사할 저장소 경로가 필요하다"; exit 1; }; copy_to "$2"; exit 0 ;;
    --check) CHECK_ONLY=1 ;;
    "") ;;
    *) echo "알 수 없는 인자: $1 (--check | --copy-to <저장소>)"; exit 1 ;;
esac

# Homebrew 패키지 확인. 없으면 설치 (--check 면 보고만)
brew_need() {
    local cmd="$1" pkg="$2"
    if command -v "$cmd" >/dev/null 2>&1; then ok "$cmd"; return; fi
    if [ "$CHECK_ONLY" -eq 1 ]; then fail "$cmd 없음 (brew install $pkg)"; return; fi
    if ! command -v brew >/dev/null 2>&1; then fail "$cmd 없음, Homebrew 도 없다 (https://brew.sh)"; return; fi
    echo "  $pkg 설치"
    if brew install "$pkg"; then ok "$cmd 설치됨"; else fail "$pkg 설치 실패"; fi
}

echo "[1/4] Docker"
if ! command -v docker >/dev/null 2>&1; then
    fail "docker 없음. Docker Desktop 설치 필요 (https://www.docker.com/products/docker-desktop)"
elif ! docker info >/dev/null 2>&1; then
    fail "Docker 데몬에 연결할 수 없음. Docker Desktop 실행 필요 (open -a Docker)"
else
    ok "Docker 데몬 실행 중"
fi

echo "[2/4] uv (keymap-drawer 실행용), rsvg-convert (key_positions.png 변환용)"
brew_need uv uv
brew_need rsvg-convert librsvg

echo "[3/4] 빌드 이미지 $IMAGE"
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    ok "이미지 있음"
elif [ "$CHECK_ONLY" -eq 1 ]; then
    fail "이미지 없음 (docker pull $IMAGE)"
elif docker info >/dev/null 2>&1 && docker pull "$IMAGE"; then
    ok "이미지 받음"
else
    fail "이미지 받기 실패 (Docker 실행 후 다시 시도)"
fi

echo "[4/4] keymap-drawer"
if ! command -v uv >/dev/null 2>&1; then
    fail "uv 가 없어 확인 불가"
elif [ "$CHECK_ONLY" -eq 1 ]; then
    ok "uv 로 실행 시 자동으로 받는다"
elif uv run --quiet --no-project --with keymap-drawer python -c "import keymap_drawer" &&
     uvx --from keymap-drawer keymap --version >/dev/null; then
    ok "keymap-drawer 캐시 준비됨"
else
    fail "keymap-drawer 받기 실패"
fi

echo "[결과] 성공=$OK 실패=$FAIL"
[ "$FAIL" -eq 0 ]
