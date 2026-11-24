#!/usr/bin/env bash
# GitHub Actions 없이 로컬 Docker 컨테이너에서 ZMK 펌웨어(uf2)를 빌드하고 키맵 그림을 갱신하는 공통 스크립트
#
# 네 저장소(zmk-new_corne, zmk-config-Keyball39, zmk-config-totem, lily58-wireless-view-zmk-config)가
# 같은 파일을 쓴다. 저장소마다 다른 값은 build.env 에 둔다. 자세한 내용은 BUILD.md 참고.
#
# 사용법
#   ./build.sh                 build.yaml 의 대상 중 settings_reset 을 뺀 전부 빌드
#   ./build.sh left            결과 파일명에 'left' 가 들어간 대상만 (여러 개 가능)
#   ./build.sh right reset     오른쪽 + settings_reset
#   ./build.sh all             settings_reset 포함 전부
#   ./build.sh --update left   west.yml 변경 여부와 상관없이 west update 를 다시 실행
#   ./build.sh --clean         west 작업 공간(Docker 볼륨)을 지우고 종료
#   ./build.sh --draw-only     펌웨어 빌드 없이 그림만 갱신
#
# 결과물
#   firmware/<이름>.uf2                     펌웨어
#   keymap-drawer/<KEYBOARD>.yaml·.svg     keymap-drawer 키맵 그림
#   key_positions.png                       키 위치 이름표 (L1·R1·M1, #번호)
#
# west 작업 공간(zmk·zephyr 소스, 빌드 캐시)은 Docker 볼륨에 둔다.
# 저장소 루트의 zephyr/ (보드 모듈 정의)와 west 가 받는 zephyr 소스가 겹치지 않게 하려는 것이다.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="zmkfirmware/zmk-build-arm:stable"
OUT_DIR="$REPO_DIR/firmware"

# 저장소별 설정. KEYBOARD 는 필수, 나머지는 기본값이 있다
KEYBOARD=""; TITLE=""; VOLUME=""; DRAW_LAYOUT_ARGS=""; MIDDLE_KEYS=""
# shellcheck source=/dev/null
[ -f "$REPO_DIR/build.env" ] && . "$REPO_DIR/build.env"
TITLE="${TITLE:-$KEYBOARD}"
VOLUME="${VOLUME:-zmk-ws-$(basename "$REPO_DIR")}"

RUN_TS=$(date +"%Y%m%d_%H%M%S")
SCRIPT_NAME=$(basename "$0" .sh)
LOG_DIR="$REPO_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}_${RUN_TS}.log"
FAIL_FILE="$LOG_DIR/${SCRIPT_NAME}_${RUN_TS}_fail.log"
touch "$FAIL_FILE"

log()      { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log_fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" "$FAIL_FILE"; }

START=$(date +%s)
OK=0; FAIL=0; SKIP=0

summary() {
    log "[종료] 성공=$OK 실패=$FAIL 스킵=$SKIP  소요=$(( $(date +%s) - START ))s"
    log "[로그] $LOG_FILE"
    log "[실패로그] $FAIL_FILE"
}

if [ -z "$KEYBOARD" ] || [ ! -f "$REPO_DIR/config/$KEYBOARD.keymap" ]; then
    log_fail "build.env 의 KEYBOARD 가 비었거나 config/$KEYBOARD.keymap 이 없다"
    FAIL=1; summary; exit 1
fi

# 컨테이너 안에서 명령 실행. 출력은 화면과 실행 로그에 함께 남긴다
in_docker() {
    docker run --rm \
        -v "$VOLUME":/ws \
        -v "$REPO_DIR":/repo \
        -w /ws \
        "$IMAGE" bash -c "$1" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# keymap-drawer 명령. 설치돼 있으면 그대로, 없으면 uvx 로 임시 실행한다
KEYMAP_CMD=()
if command -v keymap >/dev/null 2>&1; then
    KEYMAP_CMD=(keymap)
elif command -v uvx >/dev/null 2>&1; then
    KEYMAP_CMD=(uvx --from keymap-drawer keymap)
fi

# 1) keymap-drawer 로 키맵 그림 갱신 (CI draw 워크플로와 같은 parse → draw 순서)
draw_keymap() {
    local DRAW_DIR="$REPO_DIR/keymap-drawer" TMP_YAML TMP_SVG CFG=()
    if [ ${#KEYMAP_CMD[@]} -eq 0 ]; then
        log_fail "[draw] keymap·uvx 명령이 없어 그림 갱신 실패 (./install.sh 실행)"
        FAIL=$((FAIL + 1)); return
    fi
    [ -f "$REPO_DIR/keymap_drawer.config.yaml" ] && CFG=(-c keymap_drawer.config.yaml)
    log "[draw] keymap-drawer 그림 갱신"
    mkdir -p "$DRAW_DIR"
    TMP_YAML=$(mktemp); TMP_SVG=$(mktemp)
    # DRAW_LAYOUT_ARGS 는 '-j 파일' 처럼 공백으로 나뉜 인자라 따옴표 없이 펼친다
    # shellcheck disable=SC2086
    if (cd "$REPO_DIR" &&
        "${KEYMAP_CMD[@]}" "${CFG[@]}" parse -z "config/$KEYBOARD.keymap" >"$TMP_YAML" 2>>"$LOG_FILE" &&
        "${KEYMAP_CMD[@]}" "${CFG[@]}" draw "$TMP_YAML" $DRAW_LAYOUT_ARGS >"$TMP_SVG" 2>>"$LOG_FILE"); then
        mv "$TMP_YAML" "$DRAW_DIR/$KEYBOARD.yaml"
        mv "$TMP_SVG" "$DRAW_DIR/$KEYBOARD.svg"
        log "[draw] 성공 → keymap-drawer/$KEYBOARD.yaml, keymap-drawer/$KEYBOARD.svg"
        OK=$((OK + 1))
    else
        rm -f "$TMP_YAML" "$TMP_SVG"
        log_fail "[draw] 그림 갱신 실패 (자세한 내용은 실행 로그 참고)"
        FAIL=$((FAIL + 1))
    fi
}

# 2) 키 위치 이름표 key_positions.png 갱신
draw_key_positions() {
    if ! command -v uv >/dev/null 2>&1 || ! command -v rsvg-convert >/dev/null 2>&1; then
        log_fail "[keys] uv·rsvg-convert 가 없어 key_positions.png 갱신 실패 (./install.sh 실행)"
        FAIL=$((FAIL + 1)); return
    fi
    log "[keys] key_positions.png 갱신"
    local TMP_PNG; TMP_PNG="$(mktemp).png"
    # shellcheck disable=SC2086
    if (cd "$REPO_DIR" &&
        uv run --quiet --no-project --with keymap-drawer python scripts/key_positions.py \
            --keymap "config/$KEYBOARD.keymap" --title "$TITLE" --middle "$MIDDLE_KEYS" \
            -o "$TMP_PNG" -- $DRAW_LAYOUT_ARGS >>"$LOG_FILE" 2>&1); then
        mv "$TMP_PNG" "$REPO_DIR/key_positions.png"
        log "[keys] 성공 → key_positions.png"
        OK=$((OK + 1))
    else
        rm -f "$TMP_PNG"
        log_fail "[keys] key_positions.png 갱신 실패 (자세한 내용은 실행 로그 참고)"
        FAIL=$((FAIL + 1))
    fi
}

FORCE_UPDATE=0
DRAW_ONLY=0
WANT=()
for arg in "$@"; do
    case "$arg" in
        --update) FORCE_UPDATE=1 ;;
        --draw-only) DRAW_ONLY=1 ;;
        --clean)
            log "Docker 볼륨 $VOLUME 삭제"
            docker volume rm "$VOLUME" >>"$LOG_FILE" 2>&1 || log_fail "볼륨 삭제 실패 (없거나 사용 중)"
            summary; exit 0 ;;
        --*) log_fail "알 수 없는 옵션: $arg (--update|--clean|--draw-only)"; FAIL=1; summary; exit 1 ;;
        *) WANT+=("$arg") ;;
    esac
done

# --draw-only: Docker 빌드 없이 그림만 갱신
if [ "$DRAW_ONLY" -eq 1 ]; then
    draw_keymap
    draw_key_positions
    summary
    [ "$FAIL" -eq 0 ]; exit
fi

if ! docker info >/dev/null 2>&1; then
    log_fail "Docker 데몬에 연결할 수 없음. Docker Desktop 실행 여부 확인"
    FAIL=1; summary; exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    log "빌드 이미지 받기 ($IMAGE)"
    docker pull "$IMAGE" 2>&1 | tee -a "$LOG_FILE"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        log_fail "빌드 이미지 받기 실패"; FAIL=1; summary; exit 1
    fi
fi

# build.yaml 의 include 목록을 '결과파일명|board|shield|snippet|cmake-args' 줄로 바꾼다 (컨테이너의 pyyaml 사용)
# 결과 파일명은 artifact-name, 없으면 shield 첫 단어, 그것도 없으면 board
TARGET_LINES=$(docker run --rm -v "$REPO_DIR":/repo:ro "$IMAGE" python3 -c "
import yaml
for t in yaml.safe_load(open('/repo/build.yaml'))['include']:
    shield = t.get('shield', '')
    name = t.get('artifact-name') or (shield.split()[0] if shield else t['board'].split('/')[0])
    print('|'.join([name, t['board'], shield, t.get('snippet', ''), t.get('cmake-args', '')]))
" 2>>"$LOG_FILE")
if [ -z "$TARGET_LINES" ]; then
    log_fail "build.yaml 에서 빌드 대상을 읽지 못했다"; FAIL=1; summary; exit 1
fi

# 빌드할 대상 고르기: 인자가 없으면 settings_reset 을 뺀 전부, 'all' 이면 전부, 그 밖에는 이름에 인자가 들어간 것
TARGETS=()
while IFS= read -r line; do
    name="${line%%|*}"
    pick=0
    if [ ${#WANT[@]} -eq 0 ]; then
        [ "$name" != "settings_reset" ] && pick=1
    else
        for w in "${WANT[@]}"; do
            if [ "$w" = "all" ] || [[ "$name" == *"$w"* ]]; then pick=1; fi
        done
    fi
    if [ "$pick" -eq 1 ]; then TARGETS+=("$line"); else SKIP=$((SKIP + 1)); fi
done <<<"$TARGET_LINES"
if [ ${#TARGETS[@]} -eq 0 ]; then
    log_fail "인자(${WANT[*]})에 맞는 빌드 대상이 없다. build.yaml 의 대상: $(cut -d'|' -f1 <<<"$TARGET_LINES" | tr '\n' ' ')"
    FAIL=1; summary; exit 1
fi
log "빌드 대상: $(printf '%s\n' "${TARGETS[@]}" | cut -d'|' -f1 | tr '\n' ' ')(볼륨 $VOLUME)"

# 1) west 작업 공간 준비. 처음이거나 config/west.yml 이 바뀌었을 때만 west update
# 완료 표시(.west/updated-west.yml)는 west update 가 끝난 뒤에만 남겨, 중간에 끊기면 다음 실행에서 다시 받는다
log "west 작업 공간 확인"
if ! in_docker "
    set -e
    mkdir -p /ws/config
    cp /repo/config/west.yml /ws/config/west.yml
    [ -d /ws/.west ] || west init -l /ws/config
    if ! cmp -s /ws/config/west.yml /ws/.west/updated-west.yml || [ $FORCE_UPDATE = 1 ]; then
        echo 'west update 실행 (처음에는 수 분 걸린다)'
        west update --fetch-opt=--filter=tree:0
        cp /ws/config/west.yml /ws/.west/updated-west.yml
    else
        echo 'west.yml 변경 없음, west update 생략'
    fi
"; then
    log_fail "west 작업 공간 준비 실패"
    FAIL=1; summary; exit 1
fi

# 저장소 루트에 zephyr/module.yml 이 있으면 저장소 자체를 ZMK 모듈로 넘긴다 (boards/ 아래 보드·셰이드)
EXTRA_MODULES=""
[ -f "$REPO_DIR/zephyr/module.yml" ] && EXTRA_MODULES="-DZMK_EXTRA_MODULES=/repo"

# 2) 대상별 빌드
mkdir -p "$OUT_DIR"
for line in "${TARGETS[@]}"; do
    IFS='|' read -r NAME BOARD SHIELD SNIPPET EXTRA <<<"$line"
    SNIPPET_OPT=""; [ -n "$SNIPPET" ] && SNIPPET_OPT="-S $SNIPPET"
    SHIELD_OPT=""; [ -n "$SHIELD" ] && SHIELD_OPT="-DSHIELD=\"$SHIELD\""
    log "[$NAME] 빌드 시작 (board: $BOARD, shield: ${SHIELD:-없음})"
    if in_docker "
        set -e
        # 볼륨을 다른 경로에 붙여 만든 예전 빌드 폴더는 지운다 (CMake 캐시가 없는 경로를 가리켜 실패한다)
        if [ -f build/$NAME/CMakeCache.txt ] && ! grep -q '=/ws/zmk/app' build/$NAME/CMakeCache.txt; then
            echo '예전 경로의 빌드 폴더 삭제: build/$NAME'
            rm -rf build/$NAME
        fi
        west zephyr-export >/dev/null
        west build -p auto -s zmk/app -d build/$NAME -b $BOARD $SNIPPET_OPT -- \
            $SHIELD_OPT \
            -DZMK_CONFIG=/repo/config \
            $EXTRA_MODULES \
            $EXTRA
        cp build/$NAME/zephyr/zmk.uf2 /repo/firmware/$NAME.uf2
    "; then
        log "[$NAME] 성공 → firmware/$NAME.uf2"
        OK=$((OK + 1))
    else
        log_fail "[$NAME] 빌드 실패 (자세한 내용은 실행 로그 참고)"
        FAIL=$((FAIL + 1))
    fi
done

# 3) 그림 갱신
draw_keymap
draw_key_positions

summary
[ "$FAIL" -eq 0 ]
