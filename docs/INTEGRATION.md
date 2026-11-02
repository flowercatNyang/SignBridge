# Sejun 브랜치 통합 안내

`main`의 Python 모델 프로젝트와 `SexyInwon`의 Flutter 앱을 통합했습니다. 통합 이후 LLM 비서 메뉴를 추가했으며 설정은 [LLM 비서 안내](ASSISTANT.md)를 참고하세요. 수리 접수 MVP는 아직 포함되지 않습니다.

## 작업 위치

- Python 모델·특징의 기준 소스: `modules/`
- 데이터 준비: `scripts/data/`
- 학습·평가: `scripts/training/`, `scripts/evaluation/`
- 웹캠 데모: `apps/webcam/`
- Flutter 앱과 플랫폼별 추론: `apps/mobile/`
- 앱 내부 도구·테스트·디자인 자료는 기존 상대 경로를 유지합니다.

앱에 복제되어 있던 Python `assets/modules/`와 웹캠 스크립트는 제거했습니다. 모델 변환과 fixture 생성 도구는 루트 `modules/`를 참조합니다. 제거 전 모델·특징·어휘 코드가 루트와 같은 것을 확인했으며 원본은 `SexyInwon` 이력에 남아 있습니다.

## 모델 연결

- Python 체크포인트: `models/sign_language_five_words.pth`
- 앱 실행 모델: `apps/mobile/assets/models/sign_language_five_words.onnx`
- 앱 설정: `apps/mobile/assets/models/sign_model.json`
- 라벨: `apps/mobile/assets/data/core_label_map.json`
- 입력: float32 `[1, 30, 452]`
- 출력 순서: 아프다, 위, 아래, 회사, 엄마

배포 체크포인트는 앱 브랜치에서 가져왔으며 로컬 `models/five_words_loso/sign_language_five_words.pth`와 SHA-256이 같습니다. 배포 체크포인트와 ONNX는 Git에 포함하고 원본 영상·학습 배열·중간 가중치는 제외합니다. 앱에 남아 있는 이전 `sign_language_gru.*`는 현재 pubspec에 등록되어 있지 않은 이전 자료입니다.

학습 후 배포 모델을 갱신할 때 저장소 루트에서 실행합니다. 변환은 앱 모델·라벨·검증 fixture를 갱신하므로 함께 검토하고 커밋하세요.

```bash
python -m pip install onnx==1.19.1 onnxruntime==1.20.1
python apps/mobile/tools/export_sign_model.py
```

기본 Python 의존성은 먼저 루트 `requirements.txt`로 설치합니다. `.pth` 자체를 Flutter가 실행하지 않습니다. Android와 Web은 ONNX를 사용하고 iOS 네이티브 기능은 아직 미구현입니다.

## 검증 명령

저장소 루트:

```bash
python -m unittest discover -s tests -v
node --test apps/mobile/test/sign_features_test.mjs
python apps/mobile/tools/check_sign_java.py
```

Flutter 2.8 / Dart 2.15 환경에서:

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter build web
```

Android는 기존 Gradle 6.7 / AGP 4.1 설정과 JDK 11을 사용합니다. 빌드 환경의 Flutter/Android SDK 호환성은 별도 확인이 필요합니다. `tools/build-android.ps1`은 앱 디렉터리에서 실행합니다. 기존 저장소는 Gradle wrapper 실행 파일과 JAR를 제외하고 있으므로, 해당 파일이 없는 신규 환경에서는 Flutter SDK의 Android 프로젝트 생성 절차로 wrapper를 준비해야 합니다. 플랫폼 파일을 전체 덮어쓰지 마세요.

브라우저 통합 검증 도구 `apps/mobile/tools/check_sign_browser.cjs`는 앱의 `.model-tools/browser/` 아래 Playwright와 설치된 Chrome, Flutter web 빌드가 필요합니다. ONNX/MediaPipe 웹 런타임은 현재 외부 CDN을 사용합니다.

Python 웹캠 신뢰도/합의 기준과 Flutter 자동 실행 기준은 원래 구현이 다르며 이번 병합에서 바꾸지 않았습니다. 실제 카메라 인식률, 통화·지도·볼륨 동작은 기기에서 확인해야 합니다.

### 이번 통합에서 실행한 검증

- Python: 실행 가능한 13개 테스트 통과. 앱 자산 경로, 체크포인트/ONNX 해시, 라벨 순서, 공유 전처리와 앱 fixture의 일치 포함.
- JavaScript: 15개 테스트 통과. 특징·시간축 보간·버퍼·신뢰도 경계 검증 포함.
- Python 소스 37개 구문 분석 통과.
- 전체 Python 테스트 명령은 PyTorch 미설치로 세 테스트 모듈을 불러오지 못했습니다. 전체 성공으로 간주하지 않습니다.
- 현재 PC에 Flutter/Dart SDK와 Java 컴파일러가 없어 Flutter 분석·빌드·Dart 테스트·Java 검증은 실행하지 못했습니다.
- ONNX/PyTorch 추론 비교를 새로 실행하지 않았습니다. 체크인된 변환 보고서에 기록된 두 파일의 해시가 실제 배포 파일과 일치하는 것까지 확인했습니다.
- 학습·영상 전처리·실제 전화/지도 실행은 하지 않았습니다.

## 로컬 작업 보존

통합 전 미커밋 정리 작업은 로컬 `codex/preserve-local-layout` 브랜치의 `12a791d` 커밋에 보존했습니다. 최신 main의 폴더 구조를 유지하고 누락된 네 가지 데이터 준비 스크립트를 그 백업에서 복구했습니다. 기존 `/data/` ignore가 `scripts/data/`까지 제외하던 문제는 저장소 루트 데이터 폴더만 제외하도록 수정했습니다.
