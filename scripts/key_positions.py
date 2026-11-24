# 키맵의 물리 레이아웃으로 키 위치 이름표 그림(key_positions.png)을 만드는 스크립트
#
# 각 키에 L1·R1·M1 같은 이름, ZMK 키 위치 번호(#n), 기본 레이어 글자를 적는다.
# 키 변경을 요청할 때 "L19 를 바꿔줘" 처럼 위치를 가리키는 용도다.
#
# 실행 (build.sh 가 부른다)
#   uv run --no-project --with keymap-drawer python scripts/key_positions.py \
#       --keymap config/eyelash_corne.keymap --title "Eyelash Corne" \
#       --middle "6 19 20 21 34 35" -o key_positions.png -- -j config/eyelash_corne.json
#
# -- 뒤에는 keymap draw 에 넘기는 레이아웃 인자(-j / -d / -z)를 그대로 쓴다. 없으면 키맵 이름으로 찾는다.

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml
from keymap_drawer.config import Config
from keymap_drawer.physical_layout import PhysicalLayoutGenerator

# 레이아웃 인자 → PhysicalLayoutGenerator 필드
LAYOUT_FLAGS = {"-j": "qmk_info_json", "-d": "dts_layout", "-z": "zmk_keyboard", "-k": "qmk_keyboard"}

STYLE = """
svg.keymap { font-family: Helvetica, Arial, sans-serif; }
text.label { font-size: 20px; font-weight: bold; }
rect.key { stroke: #555; }
g.side-l rect.key { fill: #dbe8fb; }
g.side-l text.tap { fill: #1f4fd6; }
g.side-r rect.key { fill: #fbe0e0; }
g.side-r text.tap { fill: #c62828; }
g.side-m rect.key { fill: #e3f3df; }
g.side-m text.tap, g.side-m text.shifted { fill: #2e7d32; }
text.tap { font-size: 26px; font-weight: bold; }
text.hold { font-size: 10px; }
"""


def run_keymap(*args: str) -> str:
    """keymap-drawer CLI 를 같은 파이썬으로 실행하고 표준 출력을 돌려준다."""
    out = subprocess.run([sys.executable, "-m", "keymap_drawer", *args], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"keymap {args[0]} 실패\n{out.stderr}")
    return out.stdout


# 마우스 동작 이름을 짧게 (mmv MOVE_UP → MS UP, mkp LCLK → LCLK)
SHORTEN = {"mmv MOVE_": "MS ", "mkp ": "", "msc SCRL_": "SCRL "}


def legend(key) -> str:
    """기본 레이어 키를 짧은 글자로 바꾼다. 탭/홀드가 다르면 '탭/홀드'."""
    if key is None:
        return ""
    if isinstance(key, str):
        text = key
    else:
        tap, hold = str(key.get("t", "")), str(key.get("h", ""))
        text = f"{tap}/{hold}" if hold else tap
    text = text.replace("&", "")
    for old, new in SHORTEN.items():
        text = text.replace(old, new)
    return text


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--keymap", required=True, help="ZMK .keymap 경로")
    ap.add_argument("--title", required=True, help="그림 제목에 쓸 키보드 이름")
    ap.add_argument("--middle", default="", help="M 으로 표시할 키 위치 번호 (공백 구분)")
    ap.add_argument("-o", "--output", required=True, help="결과 PNG 경로")
    ap.add_argument("layout_args", nargs=argparse.REMAINDER, help="-- 뒤 레이아웃 인자")
    args = ap.parse_args()

    layout_args = [a for a in args.layout_args if a != "--"]
    if not shutil.which("rsvg-convert"):
        sys.exit("rsvg-convert 가 없다 (./install.sh 또는 brew install librsvg)")

    # 아이콘 매핑 없이 기본 설정으로 파싱해 키 이름을 글자로 받는다
    parsed = yaml.safe_load(run_keymap("parse", "-z", args.keymap))
    base_layer = next(iter(parsed["layers"].values()))

    # 레이아웃 지정: 인자로 받은 것이 우선, 없으면 파싱 결과의 zmk_keyboard
    spec = dict(parsed.get("layout") or {})
    if layout_args:
        spec = {LAYOUT_FLAGS[layout_args[0]]: layout_args[1]}
    gen_spec = {k: Path(v) if k in ("qmk_info_json", "dts_layout") else v for k, v in spec.items()}
    keys = PhysicalLayoutGenerator(config=Config(), **gen_spec).generate().keys
    if len(keys) != len(base_layer):
        sys.exit(f"레이아웃 키 수({len(keys)})와 키맵 키 수({len(base_layer)})가 다르다")

    # 왼쪽/오른쪽은 키 중심이 전체 가로 범위의 가운데보다 왼쪽인지로 나눈다
    xs = [k.pos.x for k in keys]
    center = (min(xs) + max(xs)) / 2
    middle = {int(n) for n in args.middle.split()}
    count = {"L": 0, "R": 0, "M": 0}
    # keymap-drawer 기본 스타일이 left·right 클래스를 쓰므로 겹치지 않는 이름을 쓴다
    side_class = {"L": "side-l", "R": "side-r", "M": "side-m"}
    legends = []
    for pos, (pkey, bkey) in enumerate(zip(keys, base_layer)):
        side = "M" if pos in middle else ("L" if pkey.pos.x < center else "R")
        count[side] += 1
        legends.append({"t": f"{side}{count[side]}", "h": f"#{pos} {legend(bkey)}", "type": side_class[side]})

    sides = "L=left, R=right" + (", M=middle" if middle else "")
    title = f"{args.title} key names  ({sides} / #n = ZMK key position, legend = base layer)"
    draw_yaml = {"layout": spec, "layers": {title: legends}}
    draw_cfg = {
        "draw_config": {
            "key_w": 84, "key_h": 84, "split_gap": 40, "shrink_wide_legends": 14,
            "svg_extra_style": STYLE, "append_colon_to_layer_header": False,
        }
    }

    with tempfile.TemporaryDirectory() as tmp:
        yml, cfg, svg = Path(tmp, "keys.yaml"), Path(tmp, "config.yaml"), Path(tmp, "keys.svg")
        yml.write_text(yaml.safe_dump(draw_yaml, allow_unicode=True))
        cfg.write_text(yaml.safe_dump(draw_cfg, allow_unicode=True))
        svg.write_text(run_keymap("-c", str(cfg), "draw", str(yml)))
        subprocess.run(["rsvg-convert", "-b", "white", "-z", "1.2", "-o", args.output, str(svg)], check=True)
    print(f"생성: {args.output}")


if __name__ == "__main__":
    main()
