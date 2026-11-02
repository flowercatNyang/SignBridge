# 수어 숫자 입력 · 날짜 알람 · 임시 13개 클래스 준비

## 현재 바뀐 동작

- 앱 첫 화면은 LLM 비서이며 카메라는 사용자가 켤 때만 동작합니다.
- `엄마`, `아프다`, `위` 등을 인식하는 것만으로 전화·긴급신고·볼륨을 실행하지 않습니다.
- `알람 · 숫자로 시간·날짜 입력`에서 **시간 HHMM → 날짜/반복 선택 → 날짜 MMDD → 최종 확인**으로 진행합니다.
- 오후 1시 5분은 `1305`, 오전 1시 5분은 `0105`입니다. 12월 5일은 날짜 단계에서 `1205`입니다.
- 날짜를 생략하면 다음 해당 시각 1회 또는 매일/평일 반복을 선택합니다.
- 날짜는 기기 현지 시간 기준으로 다음에 돌아오는 해당 날짜를 선택하고 연도를 포함해 보여줍니다. 2월 29일은 다음 윤년까지 찾습니다.
- 최종 화면에서 `그렇다` 또는 실행 버튼으로 승인합니다. `틀리다`는 이전 요청을 폐기하고 시간부터 다시 입력합니다.
- 날짜/시간 해석은 앱의 검증된 규칙으로 처리합니다. 이 단계는 NVIDIA API가 없어도 사용할 수 있습니다. LLM 비서의 일반 문장 변환·추가 질문·문자 작성은 기존 NVIDIA 연결을 사용합니다.
- 날짜/시간을 한 필드에 자유롭게 넣는 `1205 1305` 방식은 이번 UI에 추가하지 않았습니다. 단계별 필드로 모호함을 없앴습니다.

## 데이터 없이 먼저 테스트

1. Flutter 환경에서 앱을 실행합니다.
2. LLM 비서에서 개발자 모드를 켭니다.
3. `알람 · 숫자로 시간·날짜 입력`을 누릅니다.
4. `1, 3, 0, 5` → 입력 완료 → 특정 날짜 지정 → `1, 2, 0, 5` → 입력 완료.
5. 연도·날짜·시간을 확인합니다. `틀리다`로 재입력하거나 `그렇다`로 예약합니다.

버튼은 실제 인식 콜백과 같은 입력 처리 경로를 사용합니다. 버튼을 추가했다고 카메라가 새 단어를 인식하는 것은 아닙니다.

## Android 알람의 차이

- 날짜 없는 시각/요일 반복 알람: 기존 Android 시계 앱을 엽니다. 시계 앱에서 설정 결과를 확인합니다.
- 특정 날짜: SignBridge가 `AlarmManager.setAlarmClock`으로 예약하고 해당 시각에 **소리·진동 알림**을 표시합니다. 기본 시계 앱 목록에 추가되지 않으며, 중지할 때까지 계속 울리는 전체 화면 알람은 아닙니다.
- 알림 권한, 날짜 지정 알람 채널 및 정확한 알람 접근 권한이 필요합니다. 권한을 허용한 뒤 다시 승인해야 하며 자동으로 실행하지 않습니다.
- 앱이 정상 설치된 상태에서 재부팅·시간대 변경 시 미래 예약을 복원합니다. 앱 강제 중지/삭제, 권한 철회, 전원 꺼짐 및 기기 알림 설정에 따라 전달되지 않을 수 있습니다. 실기기에서 소리·진동과 잠금 화면을 확인하세요.
- Android 33 이상 compile SDK가 필요합니다. Flutter/Dart 버전은 기존 pubspec의 Dart 2.15~2.x 범위를 따릅니다.

Android 동작 근거: [정확한 알람](https://developer.android.com/develop/background-work/services/alarms), [알림 권한](https://developer.android.com/develop/ui/views/notifications/notification-permission).

## 임시 학습 단어 13개

기존 5개 모델/NPY는 보존했습니다. `SIGNBRIDGE_VOCABULARY=assistant_demo`일 때만 별도의 데이터와 클래스 목록을 사용합니다. 이전 `assistant23` 값도 임시 목록을 가리키는 호환 별칭으로 유지하지만, 새 출력 폴더는 `processed_assistant_demo`입니다. 과거 23개 라벨로 만든 데이터와 섞지 않습니다.

| 사전 ID | 단어 |
|---|---|
| WORD1152 | 아프다 |
| WORD2100 | 위 — 장기, 앱에는 위(내장) |
| WORD2576 | 상부 — 방향, 앱에는 위(방향) |
| WORD2577 | 아래 |
| WORD1592 | 회사 |
| WORD1528 | 엄마 |
| WORD1157 | 나 |
| WORD0948 | 가깝다 |
| WORD0932 | 매일매일 |
| WORD1273 | 일어나다 |
| WORD2268 | 그렇다 |
| WORD1359 | 틀리다 |
| WORD2639 | 팔 (숫자 8) |

걷다·귀·숫자 0~7·9는 `modules/vocabulary.py` 및 개발자 단어 버튼 목록에서 주석 처리했습니다. 그렇다·틀리다는 사용자 요청대로 유지합니다. 숫자 팔은 WORD2639이며 신체 팔 WORD1147과 다릅니다. 일어나다는 WORD1273을 사용합니다. 중복 표제어인 WORD1379를 별도 클래스로 추가하지 않았습니다. 배포 시 WORD2639는 `8`로 표시합니다.

`위(내장)`는 WORD2100, `위(방향)`는 사전의 상부 WORD2576입니다. 두 동작은 별도 클래스로 학습합니다. 영상 파일은 WORD ID로 구분하는 것을 권장하며 `수어자ID_위(내장).mp4`, `수어자ID_위(방향).mp4` 별칭도 지원합니다. 새 임시 목록에서는 `수어자ID_위.mp4`처럼 모호한 파일명을 거부합니다. 과거 5개 설정에서는 이 이름을 WORD2100으로 매핑했으므로 실제 방향 동작을 촬영했다면 파일명과 라벨을 수정하고 다시 전처리해야 합니다. 기존 모델의 잘못 섞인 라벨은 표시명만 바꿔서 고칠 수 없습니다.

볼륨 경로는 `위(방향)`/`아래` → LLM의 `adjust_volume` → 사용자 확인 → Android 미디어 볼륨 한 단계 조절입니다. 장기 위는 볼륨 명령에서 제외합니다. 기존 배포 모델의 WORD2100 출력도 위(내장)으로 표시하며, 방향 위 인식에는 13개 모델 학습·배포가 필요합니다. 데이터 준비 전에는 개발자 버튼으로 위(방향)/아래를 시험할 수 있습니다.

임시 모델은 숫자 8만 인식할 수 있으므로 `1305`, `1205`, `0800` 전체를 수어만으로 입력할 수 없습니다. 날짜·시간 화면에는 **0~9 수동 키패드**를 개발자 모드와 관계없이 유지했습니다. 학습 제외된 숫자는 키패드로 보완합니다. 새 13개 모델을 배포하기 전에는 기존 5개 단어만 카메라에서 인식합니다.

### 1. 전문가 데이터 준비

활성화한 13개 ID 모두를 포함하는 `X_train.npy`, `y_train.npy`, **그 y 값에 정확히 대응하는** `core_label_map.json`을 같은 디렉터리에 둡니다. 클래스당 전문가 시퀀스는 50개 이상 유지합니다. 기존 73개 배열에 일부 ID가 없으면 단어 사전만 추가해서는 안 됩니다. 해당 클래스의 실제 전문가 시퀀스를 같은 전처리 기준으로 준비하고 배열과 라벨 맵을 함께 구성해야 합니다.

준비 스크립트는 빠진 ID를 검사해 중단합니다. 150차원 또는 기존 452차원 시퀀스를 사용하며, 관절 순서·정규화가 기존 파이프라인과 같아야 합니다.

현재 저장소의 73개 전문가 라벨 맵에는 활성 목록 중 **WORD0948 가깝다, WORD0932 매일매일, WORD2268 그렇다, WORD1359 틀리다, WORD2576 상부** 5개가 없습니다. 해당 전문가 데이터가 다른 위치에 있는지 확인하거나 준비해야 합니다. 나머지 ID가 맵에 있다는 사실만으로 실제 데이터 품질·수량 검증까지 완료된 것은 아닙니다.

### 2. 팀원 영상 준비

파일명은 `수어자ID_WORD2639.mp4`, `수어자ID_정면_WORD2268.mov`처럼 **ID 표기**를 권장합니다. `수어자ID_팔.mp4` 같은 활성 단어 이름도 지원합니다. 각 파일은 한 단어/숫자 한 자리 동작입니다. 날짜 전체를 한 영상 클래스로 만들지 않습니다.

시작 최소 수량은 클래스당 총 3개입니다. LOSO 테스트 수어자, 검증 수어자, 학습 수어자가 서로 달라야 하므로 **최소 세 명이 모든 클래스에 참여**해야 합니다. 가능하면 수어자마다 여러 회 촬영하세요. 회차는 `signerA_take01_WORD2639.mp4`처럼 중간 토큰으로 구분할 수 있습니다. 학습 배치는 전문가:팀원을 약 1:1로 oversampling합니다.

### 3. 전처리 → 학습 → 평가 → 앱 배포

아래는 프로젝트 루트에서 실행할 PowerShell 예시입니다. 데이터 준비 전에는 실행하지 마세요. Python 의존성은 루트 requirements.txt를 사용하고, ONNX 내보내기는 스크립트 상단의 추가 의존성도 필요합니다.

```powershell
python -m pip install -r requirements.txt
python -m pip install onnx==1.19.1 onnxruntime==1.20.1

$env:SIGNBRIDGE_VOCABULARY = 'assistant_demo'

python scripts/data/prepare_assistant_data.py --source-data D:/SignBridge/expert --raw-mov D:/SignBridge/team

python scripts/training/train_pipeline.py --held-out-signer signerC --validation-signer signerB --output-dir models/assistant_demo_loso

python scripts/evaluation/evaluate_model.py --checkpoint models/assistant_demo_loso/final.pth --output reports/assistant_demo_loso/evaluation.json

python apps/mobile/tools/export_sign_model.py --checkpoint models/assistant_demo_loso/final.pth --target apps/mobile/assets/models/sign_language_assistant_demo.onnx
```

`signerA/B/C`는 실제 파일명에 쓰인 ID로 변경합니다. 새 데이터는 `data/processed_assistant_demo`에 만들어지며, 새 모델의 메타데이터와 라벨 맵도 함께 배포됩니다. 내보내기는 학습이 끝나고 평가 결과를 확인한 뒤 실행하세요. 앱을 다시 빌드해야 새 모델이 포함됩니다.

기존 5개 모델로 되돌리려면:

```powershell
Remove-Item Env:SIGNBRIDGE_VOCABULARY
python apps/mobile/tools/export_sign_model.py
```

새 단어 인식은 **동일 단어가 신뢰도 85% 이상으로 3회 연속 관측**되어야 추가합니다. 숫자마다 손을 0.8초 이상 내린 뒤 다음 숫자를 표현합니다. `0800`의 마지막 0도 따로 표현해야 합니다. 확인 단계로 넘어갈 때도 손을 내린 후 새 확인 동작을 해야 합니다. 이 값은 인식 정확도를 보장하지 않으며 실제 촬영과 실기기에서 검증해야 합니다.

## 검증 명령과 남은 범위

```powershell
python -m unittest discover -s backend/tests -v
python -m unittest discover -s tests -p test_assistant_vocabulary.py -v
cd apps/mobile
flutter test
```

이번 작업은 단계별 알람 입력·날짜 예약·수어 확인·임시 13개 클래스 학습 준비와 볼륨 연동을 다룹니다. 병원 검색·길 찾기·전화를 LLM 도구로 확장하는 작업은 포함하지 않습니다. 현재 백엔드 허용 도구는 `set_alarm`, `compose_message`, `adjust_volume`입니다.
