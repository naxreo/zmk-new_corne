#!/usr/bin/env bash
# GitHub Actions 없이 로컬 Docker 컨테이너에서 ZMK 펌웨어(uf2)를 빌드하는 스크립트
#
# 사용법
#   ./build.sh                 왼쪽(Studio) + 오른쪽 빌드
#   ./build.sh left            왼쪽만
#   ./build.sh right reset     오른쪽 + settings_reset
#   ./build.sh --update left   west.yml 변경 여부와 상관없이 west update 를 다시 실행
#   ./build.sh --clean         west 작업 공간(Docker 볼륨)을 지우고 종료
#
# 결과물은 firmware/ 아래 uf2 로 복사된다.
# west 작업 공간(zmk·zephyr 소스, 빌드 캐시)은 Docker 볼륨 zmk-corne-ws 에 둔다.
# 저장소 루트의 zephyr/ (보드 모듈 정의)와 west 가 받는 zephyr 소스가 겹치지 않게 하려는 것이다.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="zmkfirmware/zmk-build-arm:stable"
VOLUME="zmk-corne-ws"
OUT_DIR="$REPO_DIR/firmware"

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

# 컨테이너 안에서 명령 실행. 출력은 화면과 실행 로그에 함께 남긴다
in_docker() {
    docker run --rm \
        -v "$VOLUME":/ws \
        -v "$REPO_DIR":/repo \
        -w /ws \
        "$IMAGE" bash -c "$1" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

# 빌드 대상: 이름 → shield | snippet | 추가 cmake 인자 | 결과 파일명 (build.yaml 과 맞춘다)
target_spec() {
    case "$1" in
        left)  echo "eyelash_corne_left nice_view|studio-rpc-usb-uart|-DCONFIG_ZMK_STUDIO=y -DCONFIG_ZMK_STUDIO_LOCKING=n|eyelash_corne_studio_left" ;;
        right) echo "eyelash_corne_right nice_view|||eyelash_corne_right" ;;
        reset) echo "settings_reset|||settings_reset" ;;
        *)     return 1 ;;
    esac
}

FORCE_UPDATE=0
TARGETS=()
for arg in "$@"; do
    case "$arg" in
        --update) FORCE_UPDATE=1 ;;
        --clean)
            log "Docker 볼륨 $VOLUME 삭제"
            docker volume rm "$VOLUME" >>"$LOG_FILE" 2>&1 || log_fail "볼륨 삭제 실패 (없거나 사용 중)"
            summary; exit 0 ;;
        left|right|reset) TARGETS+=("$arg") ;;
        *) log_fail "알 수 없는 인자: $arg (left|right|reset|--update|--clean)"; FAIL=1; summary; exit 1 ;;
    esac
done
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(left right)

if ! docker info >/dev/null 2>&1; then
    log_fail "Docker 데몬에 연결할 수 없음. Docker Desktop 실행 여부 확인"
    FAIL=1; summary; exit 1
fi

log "빌드 대상: ${TARGETS[*]}"

# 1) west 작업 공간 준비. 처음이거나 config/west.yml 이 바뀌었을 때만 west update
log "west 작업 공간 확인"
if ! in_docker "
    set -e
    mkdir -p /ws/config
    if [ ! -d /ws/.west ]; then
        cp /repo/config/west.yml /ws/config/west.yml
        west init -l /ws/config
        NEED=1
    elif ! cmp -s /repo/config/west.yml /ws/config/west.yml; then
        cp /repo/config/west.yml /ws/config/west.yml
        NEED=1
    fi
    if [ -n \"\${NEED:-}\" ] || [ $FORCE_UPDATE = 1 ]; then
        echo 'west update 실행 (처음에는 수 분 걸린다)'
        west update --fetch-opt=--filter=tree:0
    else
        echo 'west.yml 변경 없음, west update 생략'
    fi
"; then
    log_fail "west 작업 공간 준비 실패"
    FAIL=1; summary; exit 1
fi

# 2) 대상별 빌드
mkdir -p "$OUT_DIR"
for t in "${TARGETS[@]}"; do
    IFS='|' read -r SHIELD SNIPPET EXTRA ARTIFACT <<<"$(target_spec "$t")"
    SNIPPET_OPT=""; [ -n "$SNIPPET" ] && SNIPPET_OPT="-S $SNIPPET"
    log "[$t] 빌드 시작 (shield: $SHIELD)"
    if in_docker "
        set -e
        west zephyr-export >/dev/null
        west build -p auto -s zmk/app -d build/$t -b nice_nano_v2 $SNIPPET_OPT -- \
            -DSHIELD=\"$SHIELD\" \
            -DZMK_CONFIG=/repo/config \
            -DZMK_EXTRA_MODULES=/repo \
            $EXTRA
        cp build/$t/zephyr/zmk.uf2 /repo/firmware/$ARTIFACT.uf2
    "; then
        log "[$t] 성공 → firmware/$ARTIFACT.uf2"
        OK=$((OK + 1))
    else
        log_fail "[$t] 빌드 실패 (자세한 내용은 실행 로그 참고)"
        FAIL=$((FAIL + 1))
    fi
done

summary
[ "$FAIL" -eq 0 ]
