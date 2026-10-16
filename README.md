# SignBridge

수어를 인식하고 기능을 실행하는 Flutter 앱입니다. 메뉴에는 기존 **단축키 실행**과 새 **LLM 비서**가 있습니다. LLM 비서는 입력을 모아 한국어 번역 후보·추가 질문을 받고, 사용자 확인 후 Android 알람/문자 작성 화면으로 연결합니다. API 키와 서버 설정은 [LLM 비서 안내](../../docs/ASSISTANT.md)를 참고하세요.

| 번역 결과 | 실행 기능 |
| --- | --- |
| 아프다 | 119 전화 앱 발신 화면 |
| 회사 | 등록한 회사 위치까지 네이버맵 대중교통 길찾기 |
| 엄마 | 연락처 이름이 정확히 `엄마`인 번호로 전화 |
| 위, 아래 | 미디어 볼륨 한 단계 올리기 / 내리기 |

**개발자 모드** 스위치를 켜면 5개 단어 버튼으로 실제 기능을 직접 테스트할 수 있습니다. 개발자 모드에서는 카메라 자동 실행이 중지되며, 스위치를 끄면 다시 활성화됩니다. 기본값은 꺼짐이며 앱을 다시 시작하면 꺼집니다.

개발자 모드의 **LLM 수어 조합 테스트**에는 보내다·늦다·일어나다·8 등을 추가했습니다. 이 버튼은 기능을 즉시 실행하지 않고 수어 인식 라벨을 누른 순서로 모읍니다. 비서 화면으로 전달해 같은 LLM 처리 경로를 시험할 수 있습니다. 개발자 모드에서는 카메라도 꺼집니다. 사용 예시는 [LLM 비서 안내](../../docs/ASSISTANT.md)를 참고하세요.

앱은 홈 화면에서 시작하며 번역·기기·기록·설정 탭을 제공합니다. 홈의 **수화 번역 카메라 시작** 또는 메뉴의 **단축키 실행**을 선택해야 카메라가 켜집니다. 뒤로 가면 홈으로 돌아가며 카메라는 종료됩니다. 기기·기록·설정은 기존 데모 화면입니다.

신뢰도 75% 이상에서 자동 실행합니다. 다른 단어는 버튼 없이 계속 실행합니다. 같은 단어는 손을 0.8초 이상 내렸다가 다시 보여 주면 재실행합니다. 앱 복귀 후에도 자동 실행을 계속하며, **다시 인식하기**는 수동 초기화용입니다. 숫자 단축키, 통화 종료, 타이머, 배달 앱 연결은 지원하지 않습니다.

**회사 위치 등록 / 변경**에서 회사 이름과 위도·경도를 저장합니다. 네이버맵의 국내 지원 좌표 범위를 검사하고 앱 재시작 후에도 유지합니다. 출발지는 네이버맵에서 현재 위치를 사용합니다. Android에 네이버맵이 없으면 설치 안내를 표시합니다.

엄마에게 전화하려면 연락처와 전화 권한을 허용해야 합니다. 번호가 없거나 여러 개이면 오류를 표시합니다. Android 일반 앱은 긴급번호에 직접 발신할 수 없으므로 119는 전화 앱에서 통화 버튼을 눌러야 합니다. 웹에서는 119 및 네이버맵 연결을 요청할 수 있고 연락처 조회와 시스템 볼륨 변경은 Android에서 지원합니다. iOS용 네이티브 동작은 구현되어 있지 않습니다.

현재 모델의 클래스 순서는 0: 아프다, 1: 위, 2: 아래, 3: 회사, 4: 엄마입니다. 입력은 30프레임 × 452개 특징(기본 특징·속도·가속도·손 감지 마스크)입니다. 실제 수어 영상의 인식 정확도와 실기기의 통화·지도·볼륨 동작은 별도 검증이 필요합니다.

## 개발 및 검증

### PiP 백그라운드 실행 (Android)

단축키 실행 화면에서 카메라 영상이 나온 뒤 **백그라운드 실행**을 누르면,
작은 PiP 창에 카메라 영상이 표시되고 다른 앱을 사용하는 동안에도 수어 단축키를 인식합니다.
Android 8.0 이상이며 PiP를 지원하는 기기에서 사용할 수 있습니다. 앱의 '화면 속 화면' 권한이
꺼져 있으면 설정에서 허용해야 합니다. 개발자 모드에서는 버튼이 비활성화됩니다.

PiP 창을 전체 화면으로 펼치면 단축키 화면으로 돌아옵니다. 창을 닫거나 화면을 잠그면
카메라와 인식을 중지합니다. PiP 없이 앱을 뒤로 보내면 기존처럼 인식이 중지됩니다.
화면이 꺼진 상태의 상시 촬영이나 iOS·웹 백그라운드 촬영은 지원하지 않습니다.

실기기 검증: 카메라 허용 → 버튼 진입 → 다른 앱 위에서 미리보기 및 `위`/`아래` 볼륨 명령 확인
→ 전체 화면 복귀 → PiP 닫기 → 재진입 후 화면 잠금으로 촬영 중지 확인.
PiP 권한 거부와 카메라 권한 거부 시 안내 및 정상 화면 복구도 확인합니다.
통화·연락처 등 권한이 필요한 명령은 전체 화면에서 먼저 권한을 허용해 주세요.

구현 기준: [Android 공식 PiP 안내](https://developer.android.com/develop/ui/views/picture-in-picture).

### 빌드와 테스트

저장소 루트에서 먼저 `cd apps/mobile`을 실행하세요. Python 모델과 특징의 기준 소스는 루트 `modules/`입니다. 앱의 모델 변환·fixture 생성 도구도 이 소스를 참조합니다. 전체 연결은 [통합 안내](../../docs/INTEGRATION.md)를 참고하세요.

Flutter 2.8 / Dart 2.15를 사용합니다.

```sh
dart format lib test
flutter analyze
flutter test
flutter build web
node --test test/sign_features_test.mjs
python tools/check_sign_java.py
```

Android는 Gradle 6.7 / Android Gradle Plugin 4.1에 맞춰 JDK 11로 빌드합니다.

```powershell
.\tools\build-android.ps1 -JdkHome 'C:\path\to\jdk-11'
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

모델과 영상 처리는 `lib/src/hand_camera/`, `android/app/src/main/java/com/example/testsign/`, `web/hand_camera.js`, `web/sign_worker.js`에서 처리합니다. 모델 설정은 `assets/models/sign_model.json`, 사전은 `assets/data/core_ksl_word_dictionary.json`에 있습니다. `tools/export_sign_model.py`는 ONNX 변환과 PyTorch 결과 비교를 수행합니다.

연동 참고: [네이버맵 URL Scheme](https://guide.ncloud-docs.com/docs/en/maps-url-scheme), [Android 전화 Intent](https://developer.android.com/reference/android/content/Intent#ACTION_CALL), [Android 볼륨 제어](https://developer.android.com/reference/android/media/AudioManager).
