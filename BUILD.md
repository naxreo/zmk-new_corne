<!-- 네 ZMK 키보드 저장소가 함께 쓰는 로컬 빌드 스크립트(build.sh)의 설치·설정·사용 안내 -->

# 로컬 빌드 (build.sh)

GitHub Actions 를 기다리지 않고 내 Mac 의 Docker 로 ZMK 펌웨어를 빌드한다.
빌드가 끝나면 keymap-drawer 키맵 그림과 키 위치 이름표(`key_positions.png`)도 갱신한다.

아래 네 저장소가 같은 스크립트를 쓴다. 저장소마다 다른 값은 `build.env` 한 파일에만 둔다.

| 저장소 | 키보드 | 컨트롤러 |
|---|---|---|
| zmk-new_corne | Eyelash Corne | nice!nano v2 |
| zmk-config-Keyball39 | Keyball39 | nice!nano v2 |
| zmk-config-totem | TOTEM | Seeed XIAO BLE |
| lily58-wireless-view-zmk-config | Lily58 | nice!nano v2 |

## 1. 처음 한 번 설치

1. Docker Desktop 을 설치하고 실행한다. 설치 스크립트는 Docker 를 대신 설치하지 않는다.
2. 저장소 루트에서 `./install.sh` 를 실행한다.

`install.sh` 는 아래 항목을 점검하고, 없는 것은 Homebrew 로 설치한다.

| 항목 | 쓰는 곳 | 없을 때 |
|---|---|---|
| Docker 데몬 | 펌웨어 빌드 | 직접 설치·실행 안내만 한다 |
| `uv` | keymap-drawer 실행 | `brew install uv` |
| `rsvg-convert` | `key_positions.png` 변환 (SVG → PNG) | `brew install librsvg` |
| `zmkfirmware/zmk-build-arm:stable` 이미지 | 펌웨어 빌드 | `docker pull` |
| keymap-drawer | 키맵 그림 | `uv` 캐시로 받는다 |

설치 없이 점검만 하려면 `./install.sh --check` 를 쓴다.

## 2. 사용법

```bash
./build.sh                 # build.yaml 의 대상 중 settings_reset 을 뺀 전부
./build.sh left            # 결과 파일명에 left 가 들어간 대상만
./build.sh right reset     # 오른쪽 + settings_reset
./build.sh all             # settings_reset 포함 전부
./build.sh --draw-only     # 펌웨어 없이 그림만 갱신 (Docker 불필요)
./build.sh --update        # west.yml 이 그대로여도 west update 다시 실행
./build.sh --clean         # west 작업 공간(Docker 볼륨) 삭제
```

빌드 대상은 `build.yaml` 의 `include` 목록에서 읽는다. GitHub Actions 와 같은 파일이라 둘이 어긋나지 않는다.
인자는 결과 파일명의 일부와 비교한다. 예를 들어 `left` 는 `eyelash_corne_studio_left` 에도 맞는다.

### 결과물

| 경로 | 내용 | git |
|---|---|---|
| `firmware/<이름>.uf2` | 펌웨어. 이름은 `artifact-name`, 없으면 shield 첫 단어 | 커밋하지 않음 |
| `keymap-drawer/<KEYBOARD>.yaml`, `.svg` | keymap-drawer 키맵 그림 | 커밋 |
| `key_positions.png` | 키 위치 이름표 | 커밋 |
| `logs/build_<시각>.log`, `_fail.log` | 실행 로그, 실패 로그 | 커밋하지 않음 |

### 키 위치 이름표

`key_positions.png` 는 키마다 이름, ZMK 키 위치 번호, 기본 레이어 글자를 적은 그림이다.
키를 바꿔 달라고 요청할 때 "L19 를 바꿔줘" 처럼 위치를 가리키는 데 쓴다.

- `L1`, `R1` 은 왼쪽·오른쪽 반쪽의 키를 키 위치 번호 순서로 센 이름이다. 좌우는 키 중심이 전체 가로 범위의 가운데보다 왼쪽인지로 나눈다.
- `M1` 은 `build.env` 의 `MIDDLE_KEYS` 에 적은 가운데 키(조이스틱, 엔코더 등)다.
- `#n` 은 ZMK 키 위치 번호(콤보·`hold-trigger-key-positions` 에 쓰는 값)다.

물리 레이아웃은 keymap-drawer 그림과 같은 것을 쓴다.

## 3. 저장소별 설정 (build.env)

```bash
KEYBOARD=eyelash_corne                     # config/<KEYBOARD>.keymap (필수)
TITLE="Eyelash Corne"                      # 이름표 그림 제목 (기본값 KEYBOARD)
VOLUME=zmk-corne-ws                        # west 작업 공간 Docker 볼륨 (기본값 zmk-ws-<폴더명>)
DRAW_LAYOUT_ARGS="-j config/eyelash_corne.json"  # keymap draw 레이아웃 인자 (비우면 키보드 이름으로 찾음)
MIDDLE_KEYS="6 19 20 21 34 35"             # M 으로 표시할 키 위치 번호 (없으면 비움)
```

`DRAW_LAYOUT_ARGS` 에 쓸 수 있는 값은 아래 셋이다.

| 값 | 쓰는 경우 | 예 |
|---|---|---|
| `-j <파일>` | QMK info.json 형식 물리 레이아웃 파일이 있을 때 | Corne, Keyball39 |
| `-d <파일>` | 셰이드에 ZMK 물리 레이아웃(`zmk,physical-layout`) dtsi 가 있을 때 | TOTEM |
| 비움 | keymap-drawer 가 키보드 이름으로 레이아웃을 아는 경우 | Lily58 |

`VOLUME` 은 저장소마다 달라야 한다. `west.yml` 의 ZMK 버전이 저장소마다 달라서 소스를 함께 쓸 수 없다.

## 4. 새 저장소에 넣기

```bash
./install.sh --copy-to ~/Projects/<저장소>
```

공통 파일(`build.sh`, `install.sh`, `scripts/key_positions.py`, `BUILD.md`)을 복사하고,
대상에 `build.env` 가 없으면 견본을 만든다. 그 다음 아래 순서로 맞춘다.

1. `build.env` 의 `KEYBOARD`, `TITLE`, `DRAW_LAYOUT_ARGS`, `MIDDLE_KEYS` 를 고친다.
2. `./build.sh --draw-only` 로 그림이 나오는지 본다.
3. `./build.sh` 로 펌웨어를 빌드한다.
4. `.gitignore` 에 `firmware/`, `logs/` 를 넣는다.

공통 파일을 고쳤다면 같은 명령으로 나머지 저장소에도 복사한다. 이미 있는 `build.env` 는 덮어쓰지 않는다.

## 5. 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| `Docker 데몬에 연결할 수 없음` | Docker Desktop 실행 (`open -a Docker`) |
| 처음 빌드가 수 분 걸림 | 볼륨에 ZMK·Zephyr 소스를 받는 중. 두 번째부터는 `west.yml` 이 바뀔 때만 다시 받는다 |
| `west 작업 공간 준비 실패`, 로그에 `error waiting for container: unexpected EOF` | 소스를 받는 중 Docker 데몬이 꺼졌다. Docker 를 다시 켜고 `./build.sh` 를 다시 실행하면 이어서 받는다 |
| `CMake Error: Not a file: .../pristine.cmake` | 예전 스크립트가 다른 경로로 만든 빌드 폴더다. 지금 스크립트는 이런 폴더를 자동으로 지우고 다시 빌드한다 |
| `[draw] 그림 갱신 실패` | 실행 로그에서 keymap-drawer 오류를 본다. `&lt (1) X` 처럼 괄호로 감싼 숫자는 파싱하지 못하므로 `&lt 1 X` 로 쓴다 |
| `레이아웃 키 수와 키맵 키 수가 다르다` | `DRAW_LAYOUT_ARGS` 가 다른 레이아웃을 가리킨다. 셰이드의 물리 레이아웃 파일을 지정한다 |
| 빌드는 되는데 보드·셰이드를 못 찾음 | 저장소 루트에 `zephyr/module.yml` 이 있으면 저장소를 ZMK 모듈로 넘긴다. `config/boards/` 아래 셰이드는 자동으로 찾는다 |
