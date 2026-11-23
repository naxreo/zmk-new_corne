# nice_view_mod 원본과 수정 사항

ZMK 기본 `nice_view` 셰이드를 복사해 고친 셰이드다.

- 원본: cormoran/zmk `v0.3-branch+dya` 의 `app/boards/shields/nice_view`
  (해당 폴더 마지막 커밋 `d09087f4dc280b8fdb1d32d63b03cc10162b89ce`, MIT)
- 기본 셰이드와 겹치지 않도록 이름을 `nice_view_mod`, Kconfig 조건을 `SHIELD_NICE_VIEW_MOD` 로 바꿨다

## 수정 사항 (코드에는 `[mod]` 주석으로 표시)

- `widgets/util.c` `draw_battery()`: 배터리 막대 대신 잔량 숫자(`87%`)를 그린다. 충전 중에는 `%` 대신 번개 아이콘을 붙인다
- `widgets/peripheral_status.c`: 오른쪽 그림을 무작위 풍선·산 대신 vim 로고로 고정
- `widgets/vim_logo.c`: zmk-nice-oled `assets/vim.c` 의 `vim_68x160` 을 기본 그림 형식(140x68)으로 변환해 추가
- `widgets/art.c`(풍선·산 그림)는 쓰지 않아 삭제

화면을 다시 그리는 시점은 기본 셰이드와 같다. 배터리·연결 상태가 바뀔 때만 다시 그리므로 입력 지연에 주는 영향도 기본 화면과 같다.

## 기본 화면으로 되돌리기

`build.yaml`·`build.sh` 의 셰이드를 `nice_view_mod` → `nice_view` 로 바꾸고, 빌드 캐시(`/ws/build/left`, `/ws/build/right`)를 지운 뒤 빌드한다.
