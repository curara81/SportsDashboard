# 와치 운동 시작 안 됨 — 수정 내역 (2026-05-30)

## 근본 원인
1. `WorkoutManager.startWorkout`가 HealthKit 권한(requestAuthorization) 호출 안 함.
   - DashboardViewModel은 read-only(toShare:[])만 요청 → 운동 share 권한 없음.
2. `beginCollection` 콜백에 `guard success else { return }` → 권한/엔타이틀먼트 없으면
   조용히 실패, `isActive` false 유지 → UI 안 바뀜 = "시작 안 됨".
3. entitlements 파일 `<dict/>` (healthkit 엔타이틀먼트 없음). xcodegen이 매 regen마다 wipe.

## 적용한 수정 (WatchApp/Services/WorkoutManager.swift)
- startWorkout 안에서 `store.requestAuthorization(toShare:read:)` 호출 추가,
  완료 콜백에서 `beginSession(config:)` 호출 (auth 후 세션 시작).
- 새 `@MainActor private func beginSession(config:)` 추출 — 기존 do/catch 세션 생성 로직.
- share set: workoutType + activeEnergyBurned + distanceWalkingRunning + distanceCycling + heartRate.
- beginCollection 실패 시 print 로그 (조용한 실패 제거).
- 주의: 클래스 프로퍼티명은 `store` (healthStore 아님), workoutType은 `HKObjectType.workoutType()`.

## entitlements 영속화
- WatchApp/SportsDashboard.entitlements = healthkit: true 만 (health-records / background-delivery 제거 — Personal Team 서명 깨짐 방지).
- project.yml 워치 타겟 entitlements에 properties 추가:
  ```
  entitlements:
    path: WatchApp/SportsDashboard.entitlements
    properties:
      com.apple.developer.healthkit: true
  ```
  → 이제 xcodegen regen해도 healthkit 유지됨.

## 빌드 절차 (중요)
1. **xcodegen generate 실행하지 말 것** (지금은 불필요. 기존 .xcodeproj가 entitlements 파일 참조 중).
   - regen하면 Xcode UI에서 수동 설정한 Team이 project.yml의 DEVELOPMENT_TEAM=P469A874Y6로 리셋됨.
2. Xcode에서 양쪽 타겟 Team = "DONG HO JUNG (Personal Team)" 확인 (P469A874Y6 에러나면).
3. scheme=SportsDashboard, destination=DONG HO의 iPhone, ⌘R.
4. 와치에서 걷기/러닝 시작 탭 → HealthKit 권한 시트 뜸 → 전부 허용 → 운동 시작됨.
   - 첫 실행만 권한 시트. 이후 바로 시작.

## 미해결/주의
- project.yml DEVELOPMENT_TEAM: P469A874Y6 하드코딩 → "No Account for Team" 에러 가능.
  Personal Team ID와 불일치 시 빌드 실패. Xcode UI에서 Team 수동 선택으로 우회.
- 실기기 와치에서만 정상 동작 (시뮬레이터 X).

## 2026-05-30 v2/v3 — 카운트다운 + 종료버그 + 애플식 3페이지
- "못 멈춤" 버그: endWorkout()의 `guard success else return`이 조용한 실패.
  toShare 비워서 endCollection 실패 → isActive 계속 true → 종료 화면 안 뜸.
  고침: UI 상태 먼저 끄고(낙관적 종료) HK 정리는 뒤에.
- 3초 카운트다운: beginCountdown(type:) → 3-2-1 햅틱 → beginSession. cancelCountdown() 취소.
  CountdownView 공용(WorkoutStartView + PaceWorkoutView).
- ActiveWorkoutView → TabView(.page) 3페이지, 애플 운동앱 구조:
  - tag0 controlsPage(왼쪽): 큰 종료/일시정지·재개 버튼
  - tag1 metricsPage(가운데 기본): activeStatusBar(운동중 펄스+40pt 타이머)+측정값
  - tag2 nowPlayingPage(오른쪽): 음악 제어 안내
- 음악: watchOS 앱내 직접제어 API 없음. 측면버튼/제어센터 안내만.
- 디바이스 빌드/설치/실행 성공. 프로세스 alive, 크래시 없음.
- 와치 id: 3BD5E8BA-A7AB-55C3-BBDF-B4F302BF8C82 / bundle: com.curara.SportsDashboard.watchkitapp

## elevate 레포 분석 (참고)
- TS/Angular → 코드 재사용 불가. 공식만 Swift 재구현(MPL-2.0, 공식 재구현은 의무 없음).
- 우선순위: ①CTL/ATL/TSB(피트니스/피로/폼, EWMA 42/7일) ②HRSS(TRIMP, 1h역치=100)
  ③GAP(경사보정 5차다항식) ④RSS ⑤Riegel 레이스예측 T2=T1×(D2/D1)^1.06
- HealthKit 친화도 최고: HRSS→CTL/ATL/TSB. readiness 점수랑 직결.

## 2026-05-30 v4 — 측정/저장 안 되던 근본원인 해결 (핵심!)
- 증상: 걷기 해도 심박/속도 측정 0, 건강앱 동기화 안 됨.
- 진짜 원인: NSHealthUpdateUsageDescription "운동 기록을 저장합니다."가 **너무 짧아서**
  watchOS가 "invalid value" 판정 → 크래시. (Share 문자열은 길어서 통과, Update만 짧아 거부 →
  크래시가 Update만 지목한 것과 일치). 출처: Apple Developer Forums.
- 그동안 toShare:[] 우회 → share 권한 없음 → HKLiveWorkoutBuilder 수집 실패
  → 심박/거리/칼로리 0 + finishWorkout 저장 0. (read 권한만으론 라이브 수집 안 됨)
- 해결:
  1. NSHealthUpdateUsageDescription 길게 (34B→220B). Watch/iOS/iPhone plist 전부.
  2. toShare 복구: workoutType + heartRate + distance(run/cycle) + activeEnergy.
  3. endWorkout finishWorkout 결과 로깅 (저장 확인).
  4. currentSpeed를 모든 운동타입서 계산 (걷기도 km/h 표시). mainMetric에 속도 추가.
- 빌드/설치/실행 성공. 단, 첫 실행 시 HealthKit 권한 시트에서 "쓰기" 포함 전부 허용해야 함.
  이미 거부 상태면: 아이폰 건강 앱 > 공유 > 앱 > SportsDashboard > 모두 켜기.

## 2026-06-18 — 지표 계산 버그 감사 (멀티에이전트, 22검토→13확정→수정)
fitnessAge 보간 버그(계단식+클램프없음)→연속보간 재작성. 추가로 전체 MetricsEngine 감사:
HIGH(6):
1. TRIMP 3종(Banister/Edwards/Lucia)+LoadFocus: `durationMin<5` 가드가 5분+ 간격 통째 버림
   → 희소 샘플링서 워크아웃 통째 0. 고침: 버리지 말고 maxIntervalMinutes(1.0)로 clamp.
2. Lucia/LoadFocus: vt1/vt2 가드 없음 → 0이면 전샘플 weight3(최대) 과대. 고침: vt1>0,vt2>vt1 가드.
3. Monotony: SD=0(균일 비제로주간=최대단조)을 monotony=0(안전)으로 오판 → 정반대.
   고침: 균일 비제로→greatestFiniteMagnitude(위험), 전휴식만 0.
4. HRV status: 21일 베이스라인이 최근 7일 포함→자기오염, 실제 불균형 가림.
   고침: 베이스라인 [28d..7d) 분리. recentValues 비면 insufficientData.
5. Readiness rhrScore: delta=5 절벽(4.9→51, 5.0→25, 0.1bpm에 26점). 고침: 50에서 연속.
6. evaluateTrainingStatus: Recovery가 Peaking에 가려짐(CTL>40 운동선수 회복주간을 피킹 오판).
   고침: Recovery를 Peaking 앞에서 검사. vo2 nil→0 강제대신 unknown 처리.
MEDIUM/LOW(7): cardiac drift 시간가중(인덱스→시간분할+duration-weighted),
   recovery Int 반올림(절삭→.rounded()), Readiness NaN 가드, rateGCT 0ms→150 하한.
기각 9개: dead code(vo2maxFromSwain/predictRaceTime/Lucia 호출자 없음) 또는 설계의견(sRPE스케일,
   same-day TSB 관례, 종단샘플 누락=정상 Riemann적분). 적절히 필터됨.
파일: Shared/Services/MetricsEngine.swift (주) + SportsDashboard/MetricsEngine.swift(HRV/Readiness 동기화).
워치+iOS 둘 다 BUILD SUCCEEDED.

## 2026-06-18 v5 — 8개 기능 추가 (가민 패리티)
1. 운동상세: 기존 경로지도+요약 유지. (고도프로파일 차트는 별도 작업으로 분리)
2. HR존 게이지: 운동중 zoneSeconds[5] 누적(Karvonen, UserProfile.zones 주입). 라이브 스택바+존별시간.
3. 자동 일시정지: 3초간 <0.5m 이동시 isAutoPaused. autoPauseEnabled 토글. activeStatusBar 표시.
4. 부하 피드백: 요약화면에 트레이닝효과 카드.
5. 트레이닝효과: MetricsEngine.trainingEffect(zoneSeconds) → 유산소/무산소 0~5 (Firstbeat 근사).
6. 레이스예측 자동: HealthKitManager.fetchBestRecentRun() → 최근 best run Riegel 스케일 자동입력.
7. 일일활동: fetchTodayActivity() 걸음/거리/칼로리/운동분. 대시보드 상단 카드.
8. 알림: NotificationManager 회복완료 알림(회복시간 후) + 3일+ 휴식시 넛지. authorize서 권한요청.
랩 시스템: WorkoutManager.Lap, 자동(매km)+수동(랩버튼). 요약+운동중 랩 카드.
신규 함수: trainingEffect, fetchBestRecentRun, fetchTodayActivity, NotificationManager.
모든 변경 기존 파일에 추가(xcodegen regen 회피 → DEVELOPMENT_TEAM 보존).
워치+iOS 둘 다 BUILD SUCCEEDED.

## 2026-06-18 v6 — 차트 톱니 수정 + 고도프로파일 확인
- 트레이닝밸런스 차트 톱니파형 원인: updateTrainingMetrics가 운동 행끼리만 CTL/ATL EMA
  적용 → 쉬는 날 감쇠 누락 → 운동일마다 점프. 가민은 매일 적용(쉬는날 load=0).
  고침: firstWorkout~today 매 캘린더 일별 순회. 운동일=실행 갱신+persist, 쉬는날=
  load 0으로 EMA 감쇠 + transient point(차트용, 미persist). recentLoads=일별 연속 시리즈.
  TrainingHistoryView는 trimp>0 필터라 히스토리엔 운동만 보임.
- 고도 프로파일: WorkoutRouteView에 elevationCard 이미 완성(차트+상승/하강/최고,
  hysteresis 1m 필터, hasElevationData 가드). locations:[CLLocation] 경로로 전달됨.
- iOS 디바이스 설치 성공: pbxproj에 iOSApp/SportsDashboard.entitlements 추가
  (healthkit:true) + 양 타겟 DEVELOPMENT_TEAM=P469A874Y6 명시. 단 GUI 빌드는 실제로
  GFJK8DP9ZC(로그인 계정)로 서명 — 자동관리라 무관.
- iOS SIGKILL은 lldb 디버거 attach 이슈(무료계정). devicectl 직접 launch는 정상.
  → 아이폰서 앱 아이콘 직접 탭하면 됨. Xcode ⌘R은 디버거라 SIGKILL 가능.
- 워치+iOS 시뮬레이터 빌드 SUCCEEDED. 디바이스 빌드는 사용자가 나중에.

## 다음 세션 디바이스 빌드 절차
- 워치: xcodebuild -scheme "SportsDashboard Watch App" -destination id=3BD5E8BA-... -allowProvisioningUpdates build
  → devicectl install (워치 잠금 풀고)
- iOS: Xcode GUI에서 스킴 SportsDashboard + 아이폰 선택 → 빌드 (CLI는 No Accounts).
  설치 후 아이폰 설정>일반>VPN 및 기기관리>개발자앱 신뢰. 건강 권한 허용.
- 무료 Personal Team: 프로파일 7일 만료 → 매주 재설치 필요.
