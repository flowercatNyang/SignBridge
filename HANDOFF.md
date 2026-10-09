# 친구에게 전달할 앱 연동 자료

현재 모델은 아프다·위·아래·회사·엄마 5단어를 분류합니다. 새 모델은 `models/sign_language_five_words.pth`입니다. GitHub에 기존부터 있는 `models/sign_language_gru.pth`는 이번 5단어 모델이 아니므로 사용하지 마세요.

## 추론에 필요한 파일

- `models/sign_language_five_words.pth`: 새 가중치. Git에서 제외되므로 별도 전달 필요.
- `handsign_translate.py`: 웹캠 데모 및 실시간 파이프라인 참고.
- `modules/`: 모델 구조, 관절 특징 계산, 실시간 게이트, 클래스 매핑. 반드시 가중치와 함께 현재 버전을 사용.
- `hand_landmarker.task`, `pose_landmarker_lite.task`: MediaPipe 손/상체 추출 모델.
- `requirements.txt`: Python 의존성.
- `HANDOFF.md`, `RUN_RESULTS.md`: 연동 설명과 실제 평가 결과.

배포용 추론에는 전문가 NPY, 팀 영상, 전처리 NPZ, 학습 중간 체크포인트가 필요하지 않습니다. 추가 학습을 이어받는 경우에는 `data/` 전체와 `Downloads/raw_mov/` 원본 영상을 별도로 받아야 합니다. `data/processed_five/manifest.csv`의 `source_video`는 기존 컴퓨터의 절대 경로이므로 다른 컴퓨터에서 전처리를 다시 실행할 때 경로를 맞춰야 합니다.

## Python 데모 실행

전달받은 폴더에서 가상환경을 만들고 실행합니다.

```bash
python -m venv .venv
# macOS/Linux
source .venv/bin/activate
# Windows PowerShell에서는 .venv\Scripts\Activate.ps1
pip install -r requirements.txt
python handsign_translate.py --checkpoint models/sign_language_five_words.pth
```

카메라 권한을 허용합니다. `q`는 종료, `ESC`는 인식 초기화입니다. 학습 및 테스트에 사용한 환경은 Python 3.13/macOS이며, 다른 운영체제에서의 패키지 호환성은 별도 확인해야 합니다.

## 앱에 연결할 입력/출력 계약

모델 입력은 float32 `[batch, 30, 452]`입니다. 기존 150차원 입력이나 MediaPipe 원본 랜드마크를 그대로 넣으면 안 됩니다. `modules/features.py`의 `extract_keypoints()`와 `build_temporal_features()`를 그대로 사용하세요. 452차원 순서는 150 관절 특징, 150 속도, 150 가속도, 2 손 검출 mask입니다. 목 중심 이동, 어깨 폭 정규화, 손 미검출 보간도 일치해야 합니다.

출력은 `[batch, 5]` logits이며 softmax 후 라벨은 다음과 같습니다.

| 인덱스 | 단어 |
|---:|---|
| 0 | 아프다 |
| 1 | 위 |
| 2 | 아래 |
| 3 | 회사 |
| 4 | 엄마 |

`torch.load()` 결과에는 `model_config`, `model_state`, `label_map`, `word_dictionary`, `feature_config`가 포함됩니다. `modules/models.py`의 `SignLanguageModel(**checkpoint['model_config'])`에 `model_state`를 불러오고 `eval()` 상태에서 추론합니다. 구현 예시는 `modules/utils.py`의 `load_models_and_maps()`입니다.

웹캠은 2프레임 간격, 검출용 최대 변 640픽셀, 30프레임 창을 사용합니다. 게이트는 신뢰도 0.7 이상, 최근 5회 중 3회 합의를 사용하고 손 미검출이 연속 5프레임이면 초기화합니다. `NO_SIGN/TRANSITION`은 모델 출력 클래스가 아닌 게이트 상태입니다. 손이 보이는 비수어 동작을 확실하게 거부하는 모델은 아니며 Top-1/Top-2 확률 차이 필터도 아직 없습니다.

`.pth`는 Python/PyTorch 체크포인트입니다. Android/iOS 앱에 파일을 복사하는 것만으로 실행되는 모델 형식은 아닙니다. Python 서버에서 추론을 호출하거나 앱 실행 환경에 맞는 모델 형식으로 변환해야 하며, 어느 방식이든 동일한 특징 전처리를 구현해야 합니다.

독립 촬영자 1명의 저장 영상 15개에서 Top-1 60%, Top-3 100%입니다. 위/아래 혼동이 남아 있고 웹캠 정확도는 아직 측정하지 않았습니다. 전체 진행 과정은 `RUN_RESULTS.md`를 참고하세요.

## GitHub에서 제외되는 자료

새 `.pth` 가중치와 중간 모델은 `*.pth`, 원본/전처리 데이터는 `data/` 규칙으로 제외됩니다. `Downloads/raw_mov/`는 저장소 밖에 있어서 푸시되지 않습니다. 가상환경, 캐시, `.DS_Store`도 전달할 필요가 없습니다. 기존부터 추적된 예전 `models/sign_language_gru.pth`는 ignore 규칙과 관계없이 GitHub에 남아 있습니다.
