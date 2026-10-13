# SignBridge

MediaPipe 관절 특징과 경량 1D-CNN·GRU를 이용한 한국수어 단어 인식 프로젝트입니다. 현재 대상은 **아프다, 위, 아래, 회사, 엄마** 5단어입니다.

## 저장소 구조

```text
SignBridge/
├── apps/
│   ├── webcam/          # Python 웹캠 실시간 인식 데모
│   └── mobile/          # Flutter 앱, Android/Web 추론, 앱 테스트
├── scripts/
│   ├── data/            # 데이터 선택, 변환, 영상 전처리, 품질 확인
│   ├── training/        # 4단계 모델 학습
│   └── evaluation/      # 독립 촬영자 평가
├── modules/             # 공용 모델·특징·데이터·게이트·경로 정의
├── assets/mediapipe/     # 손/상체 추출용 .task 모델
├── data/                # 원본/전처리 데이터 (Git 제외)
├── models/              # 학습된 .pth 가중치
├── reports/             # 학습 기록, 데이터 분할, 평가 결과 JSON
├── notebooks/           # 전처리·학습·평가 실행용 노트북
├── docs/                # 앱 인수인계, 실험 결과, 이전 파이프라인 설명
├── tools/               # 전달용 ZIP 생성 등 개발 보조 도구
├── tests/               # 모델·특징·샘플러·실시간 게이트 테스트
├── requirements.txt
└── README.md
```

공용 Python 코드는 기존 `modules` 패키지를 유지합니다. 파일 이동은 모델 구조나 입력/출력 라벨을 바꾸지 않습니다. 경로 기준은 `modules/paths.py`로 통일했으며, 기본 데이터·모델·자산 위치는 실행한 터미널 위치와 관계없이 저장소 루트를 기준으로 찾습니다.

## 설치와 웹캠 실행

저장소 루트에서 실행합니다.

```bash
python -m venv .venv
source .venv/bin/activate
# Windows PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python apps/webcam/handsign_translate.py
```

통합 브랜치에는 앱 ONNX 모델과 대응하는 `models/sign_language_five_words.pth`를 포함합니다. 그 외 학습 가중치와 데이터는 Git에서 제외합니다. `models/sign_language_gru.pth`는 이전 모델이므로 이번 5단어 추론에 사용하지 마세요. 카메라 권한을 허용하고, 종료는 `q`, 인식 초기화는 `ESC`입니다.

## Flutter 앱 실행

앱 작업 디렉터리는 `apps/mobile/`입니다. 기존 앱은 Flutter 2.8 / Dart 2.15 기준이며 iOS 네이티브 동작은 구현되어 있지 않습니다.

```bash
cd apps/mobile
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
```

Android 빌드와 기능 설명은 [앱 README](apps/mobile/README.md)를 참고하세요. 모델·라벨·전처리 연결 및 검증 절차는 [통합 안내](docs/INTEGRATION.md)에 정리했습니다. 현재 앱 기능은 기존 단축키 실행이며, 논의 중인 수리 접수 기능은 아직 구현하지 않았습니다.

## 데이터 → 학습 → 평가

```bash
# 1. 기존 전문가 NPY에서 5단어 선택 + 팀 영상 전처리
python scripts/data/prepare_five_word_data.py --source-data data/processed --raw-mov ~/Downloads/raw_mov

# 2. 전처리 결과 확인
python scripts/data/audit_five_word_data.py

# 3. 촬영자 분리 4단계 학습
python scripts/training/train_pipeline.py \
  --held-out-signer 박세준 --validation-signer 김정우 \
  --batch-size 32 --stage0-epochs 20 --stage1-epochs 40 \
  --stage2-epochs 15 --stage3-epochs 30 \
  --output-dir models/five_words_loso \
  --report-dir reports/five_words_loso \
  --export-path models/sign_language_five_words.pth

# 4. 학습에서 제외한 촬영자 평가
python scripts/evaluation/evaluate_model.py \
  --checkpoint models/sign_language_five_words.pth \
  --output reports/five_words_loso/evaluation.json
```

전문가 배열만 변환하려면 `scripts/data/migrate_expert_npy.py`, 기존 도메인 폴더 구조의 영상을 처리하려면 `scripts/data/preprocess_videos.py`를 사용합니다. 모든 실행 스크립트는 `--help`를 지원합니다. 노트북은 `notebooks/`에서 같은 스크립트를 호출합니다.

특징은 `[30, 452]`이며 150 관절 특징 + 150 속도 + 150 가속도 + 2 손 검출 mask로 구성됩니다. 라벨은 `modules/vocabulary.py`에서 0=아프다, 1=위, 2=아래, 3=회사, 4=엄마로 정의합니다.

전문가 자료는 클래스당 50개, 팀 영상은 클래스당 15개입니다. `촬영자_각도_단어`와 `촬영자_단어` 파일명을 처리하며 각도 생략은 정면입니다. 학습/검증/테스트 촬영자를 분리하고, 적응 학습 배치는 전문가와 팀 자료를 1:1로 구성합니다. Stage 0은 마스킹 복원, Stage 1은 전문가 분류, Stage 2는 encoder 고정 적응, Stage 3은 전체 미세조정입니다.

## 실시간 동작과 결과

현재 신뢰도 기준은 70%, 최근 5회 중 3회 합의입니다. `NO_SIGN/TRANSITION`은 모델 출력 클래스가 아닌 게이트 상태이며, 손 미검출이 연속 5프레임이면 버퍼를 초기화합니다. 손이 보이는 비수어 동작을 모두 거부하는 기능은 아닙니다.

독립 촬영자 1명의 저장 영상 15개에서 Top-1 60%, Top-3 100%였습니다. 위/아래 혼동이 남아 있고 실제 웹캠 정확도는 측정하지 않았습니다. 자세한 과정은 [실험 결과](docs/RUN_RESULTS.md), 앱 연결 방법은 [인수인계 문서](docs/HANDOFF.md)를 참고하세요. 이전 73단어 설명은 [보존 문서](docs/legacy_pipeline.md)에 남겨 두었습니다.

## 검증과 전달 자료

```bash
python -m unittest discover -s tests -v
python tools/build_handoff.py --repo . --output dist/SignBridge_handoff.zip
```

전달용 ZIP은 추론 코드·새 모델·MediaPipe 자산·설명을 포함하며 원본 영상과 학습 데이터를 포함하지 않습니다. 원본 `data/`, 배포 체크포인트 외의 `*.pth`, 가상환경, 캐시, `dist/`는 Git에서 제외됩니다.
