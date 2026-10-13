# SignBridge

수어를 번역하고 해당 단어의 기능을 자동 실행하는 Flutter 앱입니다. 메뉴에는 **단축키 실행**만 있습니다.

| 번역 결과 | 실행 기능 |
| --- | --- |
| 아프다 | 119 전화 앱 발신 화면 |
| 회사 | 등록한 회사 위치까지 네이버맵 대중교통 길찾기 |
| 엄마 | 연락처 이름이 정확히 `엄마`인 번호로 전화 |
| 위, 아래 | 미디어 볼륨 한 단계 올리기 / 내리기 |

**개발자 모드** 스위치를 켜면 5개 단어 버튼으로 실제 기능을 직접 테스트할 수 있습니다. 개발자 모드에서는 카메라 자동 실행이 중지되며, 스위치를 끄면 다시 활성화됩니다. 기본값은 꺼짐이며 앱을 다시 시작하면 꺼집니다.

신뢰도 75% 이상에서 자동 실행합니다. 다른 단어는 버튼 없이 계속 실행합니다. 같은 단어는 손을 0.8초 이상 내렸다가 다시 보여 주면 재실행합니다. 앱 복귀 후에도 자동 실행을 계속하며, **다시 인식하기**는 수동 초기화용입니다. 숫자 단축키, 통화 종료, 메시지, 타이머, 배달 앱 연결 및 기존 기기·기록·설정 화면은 제거했습니다.

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
