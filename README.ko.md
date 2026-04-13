🇺🇸 [English](README.md)

<div align="center">

<h1 align="center">
  broodwar.live
</h1>

<p align="center">
  <em>스타크래프트: Brood War 경쟁전을 위한 커뮤니티 플랫폼.</em><br>
  <em>선수 통계. 리플레이 분석. 빌드 오더. 라이브 스트림.</em>
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

BW 경쟁 커뮤니티의 통합 플랫폼 — Brood War 판 [basketball-reference.com](https://www.basketball-reference.com)을 목표로 합니다. Elixir/Phoenix, Phoenix LiveView, SQLite, Rust NIFs로 구축되었습니다.

## 기능

| 기능 | 설명 |
|------|------|
| **선수 프로필** | 커리어 통계, Elo 히스토리, 상대 전적 |
| **경기 기록** | 빌드 오더, APM, 병력 타임라인이 포함된 경기 결과 |
| **리플레이 분석** | `.rep` 파일을 업로드하면 빌드 오더, APM 곡선, 병력 구성을 즉시 분석 |
| **빌드 오더** | 프로 리플레이 근거 기반의 구조화된 검색 가능한 데이터베이스 |
| **밸런스 분석** | 맵, 시대, 실력대별 종족 상성 승률 |
| **라이브 스트림** | 한국 스트림 추적, ASL/BSL 일정 |
| **토너먼트** | 토너먼트 대진표, 결과 및 히스토리 |
| **위키** | 맵, 전략, 게임 메카닉에 관한 커뮤니티 지식 베이스 |

## 빠른 시작

```bash
# 의존성 설치 및 데이터베이스 설정
mix setup

# 서버 시작
mix phx.server
```

[localhost:4000](http://localhost:4000)에 접속하세요.

## 아키텍처

```
lib/
├── broodwar/                 # 도메인 컨텍스트
│   ├── players.ex            # 선수 프로필, Elo, 커리어 통계
│   ├── matches.ex            # 경기 결과, 상대 전적
│   ├── replays.ex            # 리플레이 업로드, 파싱된 데이터
│   ├── builds_context.ex     # 빌드 오더 데이터베이스
│   ├── streams.ex            # 라이브 스트림 추적
│   ├── tournaments.ex        # 토너먼트 데이터
│   ├── wiki/                 # 위키 페이지 및 콘텐츠
│   ├── maps/                 # 맵 풀 및 메타데이터
│   └── ingestion/            # 백그라운드 데이터 동기화
│       ├── liquipedia.ex     # Liquipedia 스크래핑
│       ├── player_sync.ex    # 선수 데이터 동기화
│       └── tournament_sync.ex
├── broodwar_nif/             # Rust NIF 브릿지
│   └── replay_parser.ex      # bw-engine 래퍼
├── broodwar_web/             # 웹 레이어
│   ├── live/                 # LiveView 페이지
│   │   ├── players_live.ex   # 선수 목록 + 검색
│   │   ├── player_detail_live.ex
│   │   ├── matches_live.ex   # 경기 기록
│   │   ├── match_detail_live.ex
│   │   ├── replay_live.ex    # 리플레이 업로드 + 브라우저
│   │   ├── replay_detail_live.ex
│   │   ├── builds_live.ex    # 빌드 오더 데이터베이스
│   │   ├── build_detail_live.ex
│   │   └── balance_live.ex   # 밸런스 분석
│   └── controllers/
│       └── api/              # JSON API
│           ├── player_controller.ex
│           ├── match_controller.ex
│           ├── replay_controller.ex
│           ├── build_controller.ex
│           ├── map_controller.ex
│           ├── balance_controller.ex
│           ├── stream_controller.ex
│           └── tournament_controller.ex
└── native/
    └── replay_parser/        # Rust NIF (Rustler 사용)
```

### 주요 기술 결정 사항

- **Phoenix LiveView**로 모든 인터랙티브 UI 구현 — SPA 없음, 클라이언트 사이드 프레임워크 없음
- **SQLite** — `ecto_sqlite3` 사용, 단일 파일 데이터베이스로 앱과 함께 배포
- **Rust NIFs** — Rustler를 통한 리플레이 파싱, [bw-engine](https://github.com/broodwar-live/bw-engine)에 위임
- **Oban** — 백그라운드 작업 처리 (Liquipedia 스크래핑, 리플레이 처리, 통계 집계)
- **Req** — HTTP 클라이언트

## API

`/api`에서 공개 JSON API를 제공합니다. 전체 [API 규칙](https://github.com/broodwar-live/.claude/blob/main/rules/api.md)을 참조하세요.

```
GET /api/players          # 선수 목록 (검색/필터)
GET /api/players/:id      # 선수 프로필 및 통계
GET /api/matches          # 경기 기록
GET /api/replays          # 리플레이 메타데이터
GET /api/builds           # 빌드 오더 데이터베이스
GET /api/maps             # 맵 풀
GET /api/balance          # 종족 상성 승률
GET /api/streams          # 라이브 스트림
GET /api/tournaments      # 토너먼트 데이터
```

## 개발

### 사전 요구 사항

- Elixir 1.18+ / Erlang OTP 27+
- Rust stable 툴체인 (NIF 컴파일용)
- Node.js (esbuild/tailwind 에셋 도구용)

### 명령어

```bash
mix setup                 # 의존성 설치, DB 생성, 에셋 빌드
mix phx.server            # 개발 서버 시작
mix test                  # 테스트 실행
mix precommit             # 컴파일 (경고를 에러로 처리) + 포맷 + 테스트
mix format                # 코드 포맷
```

### 데이터베이스

동시 읽기를 위해 WAL 모드를 사용하는 SQLite. 마이그레이션은 반드시 되돌릴 수 있어야 합니다.

```bash
mix ecto.create           # 데이터베이스 생성
mix ecto.migrate          # 마이그레이션 실행
mix ecto.reset            # 삭제 + 재생성 + 시드
```

## 관련 프로젝트

- [bw-engine](https://github.com/broodwar-live/bw-engine) — Rust 리플레이 파서 및 게임 엔진 (NIF + WASM)
- [assets-pipeline](https://github.com/broodwar-live/assets-pipeline) — BW 에셋 추출 도구
- [assets](https://github.com/broodwar-live/assets) — 사전 빌드된 유닛 스프라이트 및 아이콘
- [alphacraft](https://github.com/broodwar-live/alphacraft) — 경쟁전 BW를 위한 ML 에이전트

## 법적 고지

이 프로젝트는 Blizzard Entertainment, Inc. 또는 Microsoft Corporation과 제휴, 보증 또는 관련이 없습니다. "StarCraft" 및 "Brood War"는 Blizzard Entertainment, Inc.의 등록 상표입니다. 이 프로젝트는 팬이 팬을 위해 만든 무료 오픈소스 비상업적 커뮤니티 프로젝트입니다.

## 라이선스

MIT
