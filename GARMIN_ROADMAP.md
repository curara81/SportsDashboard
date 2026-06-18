# 가민 패리티 로드맵 (감사 기반, 2026-06-17)

분석: 5개 인벤토리(현재 앱 103항목) + 4개 가민 기능맵(64기능) 멀티에이전트 감사.

## 이미 있음 (실동작, 가민급)
- **분석 엔진 거의 완성**: MetricsEngine 20개 지표 — TRIMP(Banister/Edwards/Lucia), CTL/ATL/TSB,
  ACWR, 회복시간, 트레이닝상태(8단계), VO2max추정, HRV상태, 피트니스나이, Monotony/Strain,
  심박회복(HRR), Riegel 레이스예측, Load Focus, 카디악드리프트
- 준비도 점수(수면+HRV+RHR), 모닝리포트 대시보드(워치+아이폰), HR존(Karvonen)
- 라이브 운동: HR/거리/칼로리/페이스/속도, 일시정지/재개/종료, 3초 카운트다운, 페이스 가이드+햅틱
- HealthKit 저장(finishWorkout), 워치-아이폰 설정 동기화, 운동기록 히스토리, GPS 경로 지도(저장된 운동)

## P0 — 핵심 루프 (달리기→다기록→저장→스트라바)
1. **라이브 GPS 경로 추적** [L] — CLLocationManager + HKWorkoutRouteBuilder.
   WorkoutManager에 추가. 라이브 거리/페이스 GPS 보정, 경로를 HKWorkout에 첨부 저장.
   Info.plist NSLocationWhenInUseUsageDescription 필요.
2. **고도/오르막·내리막** [M] — CLLocation.altitude 누적. ascent/descent published.
3. **케이던스(spm)** [M] — CMPedometer 또는 HKQuantityType stepCadence 라이브.
4. **스트라바 자동 업로드** [L] — OAuth2 + activities/uploads API. HKWorkout+route→GPX/TCX export.
   ⚠️ 사용자가 Strava API 앱 등록 필요(client_id/secret) + iOS 앱에서 OAuth.
   워치 단독 불가 → 아이폰 경유 업로드.
5. **러닝 다이내믹스 실연결** [M] — 목업→실데이터. authorization set에 running* 타입 추가.

## P1 — 코어
6. 진짜 랩 시스템(수동 랩버튼 + 전체 랩 리스트, 랩별 HR/페이스) [M]
7. 자동 일시정지(정지 감지) [S]
8. 운동 중 HR존 게이지 + time-in-zone [M]
9. 트레이닝 효과(유산소/무산소 TE 0-5) — Load Focus 확장 [M]
10. 운동 상세: 랩 스플릿 테이블 + 고도 프로파일 차트 [M]
11. Load Focus 실연결(목업→실데이터) [S]
12. 스포츠 종목 확대(수영 SWOLF, 하이킹, 실내, 로잉, 근력) [L]

## P2 — 나이스
13. 구조화 인터벌 운동(워밍업/본운동/휴식/반복) [L]
14. 커스텀 데이터 필드/화면 [L]
15. 일일 활동(걸음/층/이동) + 올데이 에너지 게이지 [M]
16. Now Playing 실제 미디어 컨트롤 [M]
17. SpO2/호흡수/스트레스 카드 [M]
18. 레이스예측 자동(히스토리 best effort 자동 추출) [S]

## P3 — 스트레치
19. 트레이닝 플랜/캘린더/추천운동 [XL]
20. 코스/내비게이션 [XL]
21. 챌린지/뱃지/세그먼트 [L]

## 불가 (가민 독점 Firstbeat/센서)
- Body Battery (Firstbeat 독점 — 회복시간으로 근사만)
- 정확한 VO2max/트레이닝효과 (Firstbeat — ACSM/Swift 추정으로 근사)
- 스트레스 점수 (Firstbeat HRV 알고리즘 — 근사 가능하나 동일 불가)
- Pulse Ox 연속측정 정확도 (애플워치 SpO2는 스팟 측정)

## 스트라바 연동 계획
- Strava API: OAuth2 (client_id, client_secret, redirect_uri). 사용자가 developers.strava.com 앱 등록.
- 플로우: 아이폰 앱에서 OAuth 인증 → refresh_token 저장(Keychain) → access_token 갱신.
- 업로드: POST /api/v3/uploads (multipart, data_type=gpx/tcx/fit).
- export: HKWorkout + HKWorkoutRoute(CLLocation[]) → GPX 생성(시간/위경도/고도/HR extension).
- 위치: 운동 종료 → 아이폰으로 운동ID 전달(WatchConnectivity) → 아이폰이 HealthKit서 읽어 GPX 만들어 업로드.
- 보안: client_secret/token은 절대 코드 하드코딩 금지. Keychain + 사용자 입력.
