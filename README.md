# SignBridge

MediaPipe 관절 특징과 경량 1D-CNN·GRU를 이용한 한국수어 단어 인식 프로젝트입니다. 현재 앱은 팀 영상 325개를 사용해 학습한 13단어 모델을 실행합니다. 위(내장)와 위(방향)를 별도로 인식합니다.

최신 SexyInwon의 홈·로고·백그라운드/PiP 카메라를 `apps/mobile`에 통합했습니다. 백그라운드에서는 단어만 모으며, 앱으로 가져와 해석·확인한 요청만 실행합니다. 통합 내역과 검증 범위는 [브랜치 통합 기록](docs/BRANCH_INTEGRATION.md)을 참고하세요.

## 저장소 구조

```text
SignBridge/
├── apps/
│   └── mobile/          # Flutter 앱, Android/Web 추론, 앱 테스트
├── scripts/
│   └── data/            # 전문가 NPY 변환 및 영상 처리 CLI
├── modules/             # 공용 모델·특징·데이터·경로 정의
├── assets/mediapipe/     # 손/상체 추출용 .task 모델
├── data/                # 원본/전처리 데이터 (Git 제외)
├── models/              # 학습된 .pth 가중치
├── reports/             # 학습 기록, 데이터 분할, 평가 결과 JSON
├── notebooks/           # 전처리·학습·평가 실행용 노트북
├── docs/                # 앱 인수인계, 실험 결과, 이전 파이프라인 설명
├── tests/               # 모델·특징·샘플러 테스트
├── requirements.txt
└── README.md
```

공용 Python 코드는 기존 `modules` 패키지를 유지합니다. 파일 이동은 모델 구조나 입력/출력 라벨을 바꾸지 않습니다. 경로 기준은 `modules/paths.py`로 통일했으며, 기본 데이터·모델·자산 위치는 실행한 터미널 위치와 관계없이 저장소 루트를 기준으로 찾습니다.

## 학습 환경 설치

저장소 루트에서 실행합니다.

```bash
python -m venv .venv
source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Flutter 앱 실행

LLM 번역·추가 질문·Android 알람/문자 작성 기능을 추가했습니다. 키 입력 위치와 실행 방법은 [LLM 비서 안내](docs/ASSISTANT.md)를 참고하세요. NVIDIA API 키는 `backend/.env`에 입력하며 앱에 넣지 않습니다.

앱 작업 디렉터리는 `apps/mobile/`입니다. 기존 앱은 Flutter 2.8 / Dart 2.15 기준이며 iOS 네이티브 동작은 구현되어 있지 않습니다.

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Android 빌드와 기능 설명은 [앱 README](apps/mobile/README.md)를 참고하세요. 모델·라벨·전처리 연결 및 검증 절차는 [통합 안내](docs/INTEGRATION.md)에 정리했습니다. 수리 접수 기능은 아직 구현하지 않았습니다.

## 데이터 → 학습 → 평가

프로젝트 Python 커널로 [전처리](notebooks/Data_Preprocessing.ipynb) → [학습](notebooks/GRU_Model_Training.ipynb) → [평가](notebooks/Model_Evaluation.ipynb) 순서대로 각 노트북의 모든 셀을 실행합니다. 첫 노트북은 전문가 NPY와 다운로드 폴더의 팀 영상 325개를 확인합니다. 클래스당 전문가 50개와 팀 영상 25개로 30프레임 × 452차원 데이터를 준비합니다. 학습 노트북 첫 셀에서 테스트·검증 수어자와 출력 경로를 지정합니다. 평가는 최종 체크포인트와 같은 manifest를 사용합니다.

전문가 NPY 변환과 도메인별 영상 처리만 실행할 때는 `scripts/data/`의 독립 CLI를 사용할 수 있습니다.

## 검증

```bash
python -m unittest discover -s tests -v
```
