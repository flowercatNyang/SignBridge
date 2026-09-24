# SignBridge

스마트폰·웨어러블 연동 UI와 **MediaPipe 손·상체 추적 및 GRU 수화 단어 인식**을 제공하는 Flutter 데모입니다.

## 실행

Flutter **2.8.0 / Dart 2.15.0**을 유지합니다. Android 카메라는 **Android 7.0(API 24) 이상**에서 실행합니다.

```sh
flutter pub get
flutter run
```

웹은 다음 명령으로 실행합니다.

```sh
flutter build web
node tools/preview.cjs
```

주소는 http://127.0.0.1:8080 입니다. 웹 카메라는 **HTTPS 또는 localhost**와 브라우저 카메라 권한이 필요합니다. 다른 기기에서 일반 HTTP의 LAN 주소로 접속하면 카메라를 사용할 수 없습니다.

## 데모 사용

1. **기기** 탭에서 내 스마트폰, 스마트링, 무선 이어폰, 스마트워치의 가상 연결 상태를 변경합니다. 실제 Bluetooth 연결은 아직 구현하지 않았습니다.
2. **수화 번역 카메라 시작**을 누릅니다. Android는 카메라 권한을 요청하고 시작합니다. 웹에서는 미리보기 안의 **카메라 시작 / 재시도**를 누르고 권한을 허용합니다.
3. 양손과 어깨가 보이도록 수화를 하면 손 관절점·연결선과 함께 **카메라 위에 인식한 한국어 단어와 신뢰도**를 표시합니다. 30프레임을 모아 최소 0.5초 간격으로 추론하므로 최초 결과까지 약 2초 이상 필요합니다. 실제 속도는 기기 처리 성능에 따라 달라집니다. 테스트 용도로 신뢰도 하한 없이 가장 높은 점수의 단어를 표시합니다. 전면 영상과 관절점은 함께 좌우 반전되며, 추론에는 반전 전 좌표를 사용합니다.
4. **카메라 전환**으로 전·후면을 바꿀 수 있습니다. 장치가 해당 카메라를 제공해야 하며, 웹은 브라우저가 지원하는 카메라를 선택합니다.
5. 화면을 나가거나 앱이 백그라운드로 전환되면 카메라와 모델을 해제합니다. 웹 탭으로 돌아왔을 때는 시작 버튼을 다시 누릅니다.

권한 거부, 카메라 없음·사용 중, 모델 로딩 실패는 화면에 안내하고 재시도를 제공합니다. 권한을 영구 거부한 경우 OS 또는 브라우저의 앱 권한 설정에서 허용해야 합니다.

## 모델 및 구현 범위

- 제공된 `hand_landmarker (2).task`는 내용 변경 없이 **`assets/hand_landmarker.task`**로 이름을 정리했습니다. Flutter 2.8에서 공백이 포함된 asset 경로가 URL 인코딩되는 문제를 피하고, `pubspec.yaml`에 등록했습니다.
- `assets/models/sign_language_gru.pth`와 `assets/modules/models.py`를 이용해 만든 **`assets/models/sign_language_gru.onnx`**를 실행합니다. `pose_landmarker_lite.task`로 상체도 추적하고, 원본 `features.py`에 맞춰 오른손 63 + 왼손 63 + 상체 24개 특징을 어깨 폭으로 정규화해 `[1, 30, 150]` 입력을 만듭니다. 출력 112개 클래스는 `assets/data/core_label_map.json`과 `core_ksl_word_dictionary.json`으로 한국어에 매핑합니다. 이는 학습된 수화 **단어 분류**이며 자유로운 문장 번역은 아닙니다.
- 원본 Python 예제의 숫자 메뉴·카테고리 제한 없이 전체 112개 클래스를 대상으로 인식합니다. 제공된 `core_category_map.json`은 원본 자료로 보관합니다. 느린 추론 자체로는 동작 버퍼를 초기화하지 않습니다. 손 또는 상체가 감지되지 않는 동안은 수집을 쉬고, 1.5초 이상 감지가 복구되지 않으면 버퍼를 비웁니다. 카메라 전환·일시 중지·화면 종료 시에도 이전 결과와 버퍼를 비웁니다.
- **단축키 실행**에서 숫자 수어 1~9를 기능에 연결합니다. 1/2는 112/119 발신 화면, 3은 등록 번호 발신, 4는 배달의민족 실행, 5는 Google 영어 번역, 6은 등록 번호로 메시지 작성, 7은 수어로 분·초를 입력하는 Android 타이머, 8~9는 미정입니다. 신뢰도 85% 이상으로 한 번 인식하면 명령을 확인한 뒤 실행합니다. 설정에서 개발자 모드를 켜면 번호 버튼으로 실제 실행 경로를 테스트할 수 있습니다. 기기 제어 모드는 통화 종료 유사 표현을 지원하지만 현재 단어 모델에는 통화 종료 문장이 없으므로 개선 모델 연결이 필요합니다. 자동 기록 추가는 없습니다. [모델 교체 및 플랫폼 지원 안내](docs/model-and-actions.md)를 참고하세요.
- Android: `tasks-vision:0.10.9`, `onnxruntime-android:1.20.0`, CPU. 회전된 프레임에 손·자세 추론과 수화 추론을 별도 단일 작업 스레드에서 실행합니다. 최대 약 15fps로 제한하고 처리 중 프레임을 건너뛰어 대기열 누적을 방지합니다. 기존 Gradle/JDK/Flutter 조합을 유지하기 위해 Android Camera API를 사용합니다.
- 웹: `@mediapipe/tasks-vision@0.10.14`, `onnxruntime-web@1.20.1`, CPU/WASM. 모델은 앱 asset에서, 런타임 JS/WASM은 jsDelivr에서 로드하므로 첫 실행에 인터넷 연결이 필요합니다. 손·자세 추론은 최대 약 15fps이고 수화 추론은 전용 Web Worker에서 수행하며, 동시에 하나의 요청만 처리합니다.
- 영상은 기기 메모리에서만 처리하며 녹화하거나 서버로 전송하지 않습니다.
- **iOS 네이티브 카메라·MediaPipe 연결은 구현하지 않았습니다.** 해당 플랫폼에는 지원 플랫폼 안내를 표시합니다.
- 기기와 설정은 메모리에 보관합니다. 초기 기록 4개는 샘플 데이터이며, 가이드의 동작별 명령은 향후 기능 예시입니다.

MediaPipe 공식 문서: [Android](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/android), [웹](https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/web_js).

ONNX Runtime 공식 문서: [Java](https://onnxruntime.ai/docs/get-started/with-java.html), [웹 실행](https://onnxruntime.ai/docs/tutorials/web/build-web-app.html).

## 코드 구성

- `lib/src/demo_app.dart`: 홈, 웨어러블 기기, 기록, 설정
- `lib/src/translation.dart`: 손 인식 카메라 페이지
- `lib/src/hand_camera/`: Android 플랫폼 뷰 및 웹 iframe 연결
- `android/app/src/main/java/com/example/testsign/HandCameraView.java`: 카메라 권한, 프레임 처리, MediaPipe 추론, 관절점 렌더링, 자원 해제
- `SignFeatures.java`, `SignTranslator.java` (위 Java 디렉터리): 150차원 전처리, ONNX 추론, 단어 매핑
- `web/hand_camera.html`, `web/hand_camera.js`: 웹 영상·모델 로딩, 관절점 렌더링, 권한 오류·전환·해제
- `web/sign_features.mjs`, `web/sign_worker.js`: 150차원 전처리·시퀀스 관리, 별도 작업 스레드의 ONNX 추론
- `tools/export_sign_model.py`: ONNX 변환과 PyTorch 결과 비교. 원본·변환본 SHA-256 및 검증 결과는 `assets/models/sign_language_gru.json`에 기록
- `test/widget_test.dart`: 웨어러블 목록·상태, 화면 이동, 실행 동작 없음, SOS, 작은 화면 검증

## 검증 및 빌드

```sh
dart format lib test
flutter analyze
flutter test
flutter build web
```

Android는 기존 Gradle 6.7 / Android Gradle Plugin 4.1에 맞춰 **JDK 11**로 빌드합니다.

```powershell
.\tools\build-android.ps1 -JdkHome 'C:\path\to\jdk-11'
```

이 스크립트는 현재 프로세스에서만 Java 설정을 변경합니다. APK는 `build/app/outputs/flutter-apk/app-debug.apk`에 생성됩니다.

수화 연결 검증: 정적 분석, 위젯 테스트 7개, 웹·Android 디버그 APK 빌드 통과. PyTorch와 ONNX의 11개 입력 비교에서 최대 로짓 오차 `2.87e-6` 이하. 원본 Python 전처리와 Java/JavaScript 전처리 각각 6개 케이스 비교 통과(각도 부동소수점 허용 오차 `1e-4`). 웹 테스트 10개로 전처리·30프레임 버퍼·추론 주기·신뢰도·한국어 매핑을 검증합니다. Java와 JavaScript 모두 1.2초 간격의 느린 프레임, 일시적 감지 누락, 장시간 감지 누락, 초기화를 회귀 검사합니다.

브라우저 검사는 가상 카메라·고정 관절점을 사용하고 **실제 ONNX 모델과 WASM 런타임**을 실행합니다. PyTorch 기준 로짓과의 최대 오차 `3.82e-6` 이하, 카메라 위 결과 표시, 손 감지 해제, 카메라 전환, 권한 거부 후 재시도, 종료 시 스트림 해제를 확인했습니다. 실제 수화 영상의 정확도와 Android 실기기 성능은 아직 검증하지 않았습니다.

```sh
node --test test/sign_features_test.mjs
python tools/check_sign_java.py
```

모델을 교체할 때는 Python 환경에 `torch`, `numpy`, `onnx==1.19.1`, `onnxruntime==1.20.1`을 설치한 뒤 `python tools/export_sign_model.py`를 실행하고 앱을 다시 빌드합니다. Python 원본 전처리를 변경했다면 먼저 `python tools/make_sign_fixtures.py`로 기준 데이터를 갱신하고 두 플랫폼의 전처리 코드도 맞춰야 합니다. Anaconda에서 OpenMP 충돌이 발생하면 해당 실행 프로세스의 `MKL_THREADING_LAYER=SEQUENTIAL`을 사용합니다.

브라우저 회귀 검사는 설치된 Chrome과 Playwright가 필요합니다. `npm install --prefix .model-tools/browser --no-package-lock playwright@1.56.1` 후 웹 빌드를 하고 `node tools/check_sign_browser.cjs`를 실행합니다. 검증 화면은 `build/sign-tests/translation.png`에 생성됩니다. `.model-tools/`는 로컬 검증 패키지 전용이며 앱에 포함되지 않습니다.
