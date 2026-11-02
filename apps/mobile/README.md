# SignBridge

수어를 인식하고 기능을 실행하는 Flutter 앱입니다. 기본 화면은 **LLM 비서**이며 입력을 모아 한국어 번역 후보·추가 질문을 받고, 사용자 확인 후 Android 알람/문자 작성/볼륨 조절로 연결합니다. API 키와 서버 설정은 [LLM 비서 안내](../../docs/ASSISTANT.md), 숫자·날짜 입력과 새 모델 준비는 [임시 13개 클래스 안내](../../docs/ASSISTANT_DIGIT_ALARMS.md)를 참고하세요.

기존 단어별 즉시 실행은 중단했습니다. `엄마` 또는 `아프다`를 인식해도 전화하지 않습니다. 볼륨은 `위(방향)`/`아래` 입력 → 해석 → 확인 후 한 단계 조절합니다. `위(내장)`는 볼륨 명령이 아닙니다. 전화·지도 기능을 LLM 도구로 연결하는 확장은 별도 작업입니다.

**개발자 모드** 스위치를 켜면 임시 13개 클래스에 대응하는 단어·숫자 버튼으로 입력과 확인을 시험할 수 있습니다. 두 ‘위’는 별도 버튼입니다. 숫자 수어는 8만 포함하며, 날짜·시간 화면의 전체 숫자 키패드는 직접 입력용으로 유지합니다. 버튼만으로 새 카메라 모델이 학습되지는 않습니다.

개발자 모드에서는 카메라가 꺼집니다. 날짜 알람은 시간 `HHMM`과 날짜 `MMDD`를 별도 단계로 입력합니다. `그렇다`는 확인 중인 요청을 승인하고 `틀리다`는 폐기 후 재입력합니다.

LLM/숫자 입력 카메라는 동일 라벨이 85% 이상으로 3회 연속 관측되면 한 번 추가합니다. 단어마다 손을 0.8초 이상 내렸다가 다시 표현하세요. 실행 승인 단계 진입 시에도 손을 내려야 이전 동작이 승인으로 이어지지 않습니다. 앱 복귀 후 카메라는 자동으로 켜지지 않습니다.

**회사 위치 등록 / 변경**에서 회사 이름과 위도·경도를 저장합니다. 네이버맵의 국내 지원 좌표 범위를 검사하고 앱 재시작 후에도 유지합니다. 출발지는 네이버맵에서 현재 위치를 사용합니다. Android에 네이버맵이 없으면 설치 안내를 표시합니다.

엄마에게 전화하려면 연락처와 전화 권한을 허용해야 합니다. 번호가 없거나 여러 개이면 오류를 표시합니다. Android 일반 앱은 긴급번호에 직접 발신할 수 없으므로 119는 전화 앱에서 통화 버튼을 눌러야 합니다. 웹에서는 119 및 네이버맵 연결을 요청할 수 있고 연락처 조회와 시스템 볼륨 변경은 Android에서 지원합니다. iOS용 네이티브 동작은 구현되어 있지 않습니다.

현재 모델의 클래스 순서는 0: 아프다, 1: 위, 2: 아래, 3: 회사, 4: 엄마입니다. 입력은 30프레임 × 452개 특징(기본 특징·속도·가속도·손 감지 마스크)입니다. 실제 수어 영상의 인식 정확도와 실기기의 통화·지도·볼륨 동작은 별도 검증이 필요합니다.

## 개발 및 검증

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
