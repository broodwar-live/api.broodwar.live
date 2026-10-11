🇺🇸 [English](README.md)

<div align="center">

<h1 align="center">
  broodwar.live
</h1>

<p align="center">
  <em>broodwar.live의 JSON API — 스타크래프트: Brood War 커뮤니티 플랫폼.</em><br>
  <em>선수 통계. 리플레이 파싱. 오프닝. 라이브 스트림.</em>
</p>

<p align="center">
  <a href="https://elixir-lang.org/">
    <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.18+-4B275F?logo=elixir&logoColor=white&style=for-the-badge">
  </a>
  <a href="https://www.phoenixframework.org/">
    <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white&style=for-the-badge">
  </a>
  <a href="https://www.sqlite.org/">
    <img alt="SQLite" src="https://img.shields.io/badge/SQLite-003B57?logo=sqlite&logoColor=white&style=for-the-badge">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-c6a0f6?style=for-the-badge">
  </a>
</p>

</div>

---

`api.broodwar.live`는 [broodwar.live](https://broodwar.live)의 경량 JSON API입니다. 웹사이트 자체는 Cloudflare Pages에 배포되는 Zola 정적 사이트이며, 동적 데이터는 `fetch()`로 이 API를 호출합니다. 이 저장소에는 **HTML, LiveView, 정적 에셋이 없습니다**.

주요 기능:

- 업로드된 `.rep` 파일을 Rust NIF로 파싱 (Rustler를 통한 [replay-core](https://github.com/broodwar-live/bw-engine))
- 선수, 경기, 리플레이, 오프닝, 밸런스 통계, 대회, 맵 데이터 제공
- 3분마다 라이브 스트림 폴링 (Twitch, SOOP/아프리카TV)
- Liquipedia에서 선수·대회 데이터 동기화 (운영자 실행)

## API

모든 엔드포인트는 `/api` 아래에 있으며 [API 규칙](https://github.com/broodwar-live/.claude/blob/main/rules/api.md)을 따릅니다. 오류 형식은 `{"error": {"code": "NOT_FOUND", "message": "..."}}`입니다. 목록은 `?page=`, `?per_page=`를 받습니다 (기본 50, 최대 200).

```
GET  /api/health                     # 상태 + DB 확인 (Fly 헬스체크)
GET  /api/players                    # ?race= &status= &search=
GET  /api/players/:id
GET  /api/players/:id/matches        # 시리즈 + 세트 + 출처, 페이지네이션
GET  /api/players/:id/ratings        # Elo 기록 (경기당 한 점)
GET  /api/players/:id/stats          # 시리즈 전적 + 리플레이 기반 통계
GET  /api/matches                    # ?tournament_id= &matchup=
GET  /api/head_to_head               # ?player_a=ID &player_b=ID
GET  /api/rankings                   # ?min_games= &active_days=
GET  /api/replays                    # 요약만 (parsed_data 제외)
GET  /api/replays/:id                # 전체 파싱 결과
POST /api/replays                    # multipart "file" 업로드 (아래 참고)
GET  /api/openings                   # ?race=T|P|Z &matchup=TvZ
GET  /api/builds
GET  /api/maps
GET  /api/maps/:id/stats             # 맵별 종족전 승률
GET  /api/balance                    # 종족전 승률 (전체 + 연도별), ?map_id=
GET  /api/streams                    # ?platform= &live=true
GET  /api/tournaments[/:slug[/:season]]

POST /api/admin/replays              # Bearer ADMIN_API_KEY: 업로드 + 연결 + 레이팅
POST /api/admin/replays/:id/rate     # Bearer ADMIN_API_KEY: 기존 리플레이 연결 + 레이팅
```

모든 통계에는 표본 크기(`n`)가 포함되며, 경기 데이터 기반 응답에는 `meta.source`(Liquipedia 출처 표기)와 시리즈별 `source`(페이지, URL, 리비전 ID)가 포함됩니다.

### 경기 데이터 출처

경기 결과는 [Liquipedia](https://liquipedia.net/starcraft)에서 가져오며 [CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) 라이선스를 따릅니다. 모든 시리즈는 원본 페이지와 리비전을 저장하고 API 응답에서 링크합니다. Elo는 세트(맵) 단위로 시간순 계산합니다 (시작 1500, K = 40 / 24 / 16: 30경기 미만 / 100경기 미만 / 그 이후). 자세한 내용은 영문 README를 참고하세요.

### 리플레이 업로드

`POST /api/replays`는 익명으로 사용할 수 있으므로 의도적으로 제한됩니다:

- 파일당 최대 5 MiB (실제 리플레이는 약 50–300 KB). 초과 시 `413`
- 파일이 `.rep` 매직 바이트(`reRS`/`seRS`)로 시작하지 않으면 파서를 호출하지 않고 `422`
- 클라이언트 IP당 시간당 10회 업로드. 초과 시 `retry-after` 헤더와 함께 `429` (조회는 IP당 분당 600회)
- 동일 파일(SHA-256 기준)은 기존 리플레이를 `200`으로 반환
- 익명 업로드는 선수를 생성하거나 Elo를 **절대** 변경하지 않습니다. 리플레이와 선수 연결 및 레이팅은 관리자 엔드포인트나 운영자 일괄 가져오기(`mix broodwar.import_replays`)로만 가능하며, 리플레이당 최대 한 번만 적용됩니다.

### 선수 이미지

선수 사진은 정적 사이트의 `https://broodwar.live/images/players/` 아래에 호스팅됩니다. API는 경로를 저장하고 절대 경로 `image_url`을 반환하며, 이미지를 직접 제공하지 않습니다.

## 개발

필수 조건: Elixir 1.18+ / OTP 27+, Rust stable (`mix compile` 시 Rustler가 NIF를 컴파일).

```bash
mix setup            # 의존성, SQLite DB 생성 + 마이그레이션, 시드
mix phx.server       # http://localhost:4000/api/health
mix test
```

CI와 동일한 검사:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
(cd native/replay_parser && cargo fmt --check && cargo clippy --all-targets -- -D warnings)
```

데이터 작업:

```bash
mix broodwar.ingest_matches --tournament "AfreecaTV/StarCraft League Remastered/17"
mix broodwar.recompute_ratings           # 전체 경기로 Elo 재계산
mix broodwar.seed                        # Liquipedia에서 선수 + 대회 동기화
mix broodwar.import_replays <dir>        # 신뢰된 일괄 가져오기 (연결 + 레이팅)
```

### 리플레이 파서 NIF

`native/replay_parser`가 replay-core의 유일한 Elixir 바인딩입니다. `bw-engine`을 고정된 git `rev`로 참조합니다 (`Cargo.toml` 수정 후 `cargo update -p replay-core`로 의도적으로 갱신). `bw-engine/crates/replay-nif`는 별도의 미사용 바인딩이며, 그 NIF들은 이 크레이트의 `parse/1`의 부분집합입니다.

`native/replay_parser/.cargo/config.toml`은 `git-fetch-with-cli = true`를 설정하여, 전역 git 설정의 SSH `insteadOf` 재작성을 따르는 `git` CLI를 Cargo가 사용하도록 합니다.

### 설정

| 환경 변수 | 용도 | 기본값 |
|---|---|---|
| `SECRET_KEY_BASE` | 프로덕션 필수 (`mix phx.gen.secret`) | — |
| `DATABASE_PATH` | SQLite 파일 | `/data/broodwar.db` (prod) |
| `PHX_HOST` | 공개 호스트 | `api.broodwar.live` |
| `ADMIN_API_KEY` | `/api/admin/*`용 Bearer 토큰. 미설정 시 관리자 라우트 비활성 | 미설정 |
| `CLIENT_IP_HEADER` | 프록시 뒤 실제 클라이언트 IP 헤더 | `fly-client-ip` (prod) |
| `TWITCH_CLIENT_ID` / `TWITCH_CLIENT_SECRET` | Twitch 폴링. 미설정 시 건너뜀 | 미설정 |
| `SOOP_CLIENT_ID` / `SOOP_CATEGORY` | SOOP(아프리카TV) 폴링. 미설정 시 건너뜀 | 미설정 |
| `STATIC_SITE_URL` | 선수 이미지 URL 기준 | `https://broodwar.live` |

SOOP 참고: 기존 `openapi.afreecatv.com/broad/search` 엔드포인트는 404를 반환합니다. SOOP의 `openapi.sooplive.co.kr/broad/list`는 [developers.sooplive.co.kr](https://developers.sooplive.co.kr)에서 등록한 `client_id`와 스타크래프트 카테고리 번호가 필요합니다. 둘 다 설정되기 전까지 SOOP 폴링은 건너뜁니다. 요청 형식은 SOOP 공개 Open API를 기반으로 하며, 키 없이 검증되지 않았습니다.

## 배포 (Fly.io)

`Dockerfile`은 NIF와 Elixir 릴리스를 빌드합니다. `fly.toml`은 `nrt`(도쿄, 한국과 가장 가까운 Fly 리전)에서 머신 한 대를 실행하며, SQLite는 `/data`에 마운트된 볼륨에 저장됩니다. 마이그레이션은 부팅 시 자동 실행됩니다.

```bash
# 1. 배포 없이 앱 생성 (fly.toml 유지, broodwar-api가 사용 중이면 이름 변경)
fly launch --no-deploy --copy-config --name broodwar-api --region nrt

# 2. SQLite용 볼륨 (머신 한 대만. SQLite는 공유 불가)
fly volumes create broodwar_data --region nrt --size 1

# 3. 시크릿
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) ADMIN_API_KEY=$(openssl rand -hex 32)
fly secrets set TWITCH_CLIENT_ID=... TWITCH_CLIENT_SECRET=...      # 선택
fly secrets set SOOP_CLIENT_ID=... SOOP_CATEGORY=...               # 선택

# 4. 배포 및 확인
fly deploy
curl https://broodwar-api.fly.dev/api/health

# 5. 커스텀 도메인
fly certs add api.broodwar.live
```

`broodwar.live`의 Cloudflare DNS에 `api` → `broodwar-api.fly.dev` `CNAME` 레코드를 **DNS only**(회색 구름)로 추가합니다. Fly가 TLS 인증서를 발급하고 `Fly-Client-IP`를 설정합니다. Cloudflare 프록시(주황 구름)를 사용하면 레이트 리미터에서 모든 클라이언트가 Cloudflare IP로 보이고, 인증서 설정이 추가로 필요합니다. 이후 `fly certs check api.broodwar.live`를 실행하세요.

백업: 데이터베이스는 볼륨의 단일 파일입니다. Fly가 매일 볼륨 스냅샷을 생성하며, 외부 백업은 `fly ssh console`에서 `sqlite3 /data/broodwar.db ".backup ..."`을 사용하세요.

## 관련 프로젝트

- [broodwar.live](https://github.com/broodwar-live/broodwar.live) — Zola 정적 사이트 (프론트엔드)
- [bw-engine](https://github.com/broodwar-live/bw-engine) — Rust 리플레이 파서 및 게임 엔진

## 법적 고지

이 프로젝트는 Blizzard Entertainment, Inc. 또는 Microsoft Corporation과 제휴, 보증 또는 관련이 없습니다. "StarCraft"와 "Brood War"는 Blizzard Entertainment, Inc.의 등록 상표입니다. 이 프로젝트는 팬들이 팬들을 위해 만든 무료 오픈소스 비상업적 커뮤니티 프로젝트입니다.

## 라이선스

MIT
