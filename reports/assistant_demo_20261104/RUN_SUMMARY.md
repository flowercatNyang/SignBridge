# 2026-11-04 영상 데이터 실행 결과

최종 기준은 `stable/` 결과입니다. 원본 영상과 기존 전문가 NPY, 기존 5단어 모델은 보존했습니다. 얼굴 랜드마크는 추가하지 않았습니다.

## 입력과 파일명 처리

- 영상 위치: `C:\Users\sejee\Downloads\영상_데이터`
- 총 195개 = 13개 클래스 × 5명 × 각 3개.
- 수어자: 김건우, 김정우, 노태권, 박세준, 백인원. 각 39개.
- 파일명 형식: `시연자이름_단어뜻_방향` (`signer-word-angle`).
- `위`는 방향 WORD2576, `위(내장)`은 장기 WORD2100, `팔(8)`은 숫자 WORD2639로 처리했습니다. 마지막 토큰은 촬영 방향이며 단어 라벨과 구분합니다.
- 이전 `시연자_방향_단어` 형식도 명시적인 옵션으로 계속 지원합니다.

## 실제 실행 순서와 역할

| 순서 | 실행 파일 | 역할 | 결과물 |
|---|---|---|---|
| 1 | `scripts/data/extend_expert_data.py` | 기존 NPY의 8개 클래스 400개는 유지하고, 빠진 5개 클래스 250개를 원본 OpenPose 3D JSON에서 기존 특징 규칙으로 보충 | `data/expert_assistant_demo/X_train.npy` [650,30,150], y_train.npy, 라벨 맵, expert_provenance.json |
| 2 | `python -m modules.preprocessing` | 팀원 영상 195개의 손·상체를 MediaPipe로 처리하고 미검출 손 보간, 30프레임 재표본화, 속도·가속도·mask 생성 | `data/processed_assistant_demo/sequences/team/`의 NPZ 195개 |
| 3 | `scripts/data/prepare_assistant_data.py` | 내부에서 prepare_dataset.main → migrate_expert_npy.migrate → run_preprocessing → audit_dataset.audit를 호출. 전문가를 452차원으로 변환하고 캐시된 팀원 결과와 병합 | 전문가 NPZ 650개 + 팀원 NPZ 195개, manifest.csv, dataset_summary.json |
| 4 | `scripts/training/train_pipeline.py` | 아래 4단계 학습. 테스트·검증 수어자는 학습에서 제외 | `models/assistant_demo_loso_20261104_stable/`의 단계별·최종 PTH |
| 5 | `scripts/evaluation/evaluate_model.py` | expert_only.pth와 final.pth를 같은 미학습 수어자 영상에 평가 | `stable/expert_only_evaluation.json`, `stable/evaluation.json` |
| 6 | `apps/mobile/tools/export_sign_model.py` | 최종 PTH를 ONNX로 내보내고 16개 입력에서 출력 비교. 앱 모델 설정·라벨·별칭 갱신 | `apps/mobile/assets/models/sign_language_assistant_demo.onnx`와 검증 JSON |
| 7 | `scripts/evaluation/verify_onnx.py` | 실제 테스트 시퀀스 39개에서 Python 로더·PyTorch·ONNX 출력을 비교 | `stable/runtime_checks.json` |

1과 2는 독립적으로 병행했습니다. 3에서는 이미 생성한 팀원 NPZ를 재사용했습니다. 합쳐진 전체 데이터는 하나의 X_train.npy가 아니라 **845개 NPZ와 manifest.csv**이며, 각 NPZ의 `x`는 [30,452] float32 특징입니다. 452 = 기본 150 + 속도 150 + 가속도 150 + 손 검출 mask 2입니다.

전문가 보충은 좌표 표현을 맞추는 처리입니다. OpenPose와 MediaPipe의 검출 오차·분포까지 같아지는 것은 아닙니다. 기존 클래스 한 샘플을 재계산해 기존 NPY와 MSE 0.0인 것을 확인했지만, 이 확인이 두 검출기의 동등성을 보장하지는 않습니다.

## 데이터 분리와 학습

| 용도 | 전문가 | 팀원 | 합계 |
|---|---:|---:|---:|
| 학습 | 585 | 117 (김건우·노태권·백인원) | 702 |
| 검증 | 65 | 39 (김정우) | 104 |
| 최종 테스트 | 0 | 39 (박세준) | 39 |

클래스당 전문가 50개와 팀원 15개를 사용했습니다. Stage 0에도 검증·테스트 수어자는 포함하지 않았습니다.

| 단계 | epoch | 학습률 | 역할 |
|---|---:|---:|---|
| Stage 0 | 20 | 0.001 | 관절 시퀀스 마스킹 복원 자기지도 사전학습 |
| Stage 1 | 20 | 0.001 | 전문가만으로 13개 단어 분류 학습 |
| Stage 2 | 10 | 0.0005 | encoder를 고정하고 classifier 적응. 전문가:팀원 1:1 배치 |
| Stage 3 | 20 | 0.0001 | 전체 encoder 미세조정, 학습 수어자 ID에 gradient reversal 적용 |

모델은 기존 DepthwiseConv1D → 2-layer GRU → Attention pooling → Linear(13)입니다. batch size 64, seed 42이며, 검증 지표로 단계별 체크포인트를 선택했습니다. 테스트 결과로 epoch·학습률·모델을 고르지 않았습니다.

## 최종 평가 결과

| 모델 | Top-1 | Top-3 | Top-5 |
|---|---:|---:|---:|
| 전문가만 학습 | 51.28% (20/39) | 71.79% | 76.92% |
| 팀원 적응 후 최종 | 69.23% (27/39) | 87.18% (34/39) | 100.00% (39/39) |

최종 macro F1: 0.6672. 이는 **한 명을 제외한 LOSO 한 fold의 저장 영상 평가**입니다. 5명 전체 fold 평균, 외부 일반인 테스트, 실시간 이동 창 정확도는 측정하지 않았습니다.

| 단어 | 정답/영상 | 정확도 |
|---|---:|---:|
| 아프다 | 2/3 | 66.67% |
| 위(내장) | 3/3 | 100.00% |
| 아래 | 0/3 | 0.00% |
| 회사 | 2/3 | 66.67% |
| 엄마 | 3/3 | 100.00% |
| 나 | 2/3 | 66.67% |
| 가깝다 | 3/3 | 100.00% |
| 매일매일 | 2/3 | 66.67% |
| 일어나다 | 2/3 | 66.67% |
| 8 | 3/3 | 100.00% |
| 그렇다 | 2/3 | 66.67% |
| 틀리다 | 3/3 | 100.00% |
| 위(방향) | 0/3 | 0.00% |

특히 방향 위·아래는 각각 0/3이므로 볼륨 시연의 영상 인식 성능이 확보됐다고 볼 수 없습니다. 문자·알람 등의 실제 수행 성공률도 이 단어 정확도와 별개입니다.

기존 앱 신뢰도 기준 0.85를 저장 영상 출력에 적용하면 12/39개만 기준을 넘었고 그중 12개가 정답이었습니다. 나머지는 기준 미달입니다. 이 통계는 실제 앱의 3회 예측 합의·손 내리기 규칙을 실행한 결과가 아닙니다.

## 품질과 실행 검증

- 영상 195개 모두 처리했고 실패 0개입니다. NPZ 845개가 모두 [30,452]이며 NaN/무한대가 없음을 검사했습니다.
- 30프레임 mask 기준으로 손이 검출된 비율이 절반 미만인 영상이 44개 있습니다. 준비·대기 구간도 포함된 수치라 모두 잘못된 영상이라는 뜻은 아닙니다. 전체 미검출 영상은 0개입니다. `low_hand_coverage.csv`로 확인할 수 있습니다.
- ONNX 내보내기 16개 입력 비교 통과. 실제 테스트 시퀀스 39개에서도 예측 클래스가 모두 일치했고 최대 logit 차이는 2.6226044e-06입니다. 변환 일치는 단어 인식 정확도와 별개입니다.
- 최종 Python 테스트 27개, 웹 특징 테스트 15개 통과.
- 기존 Python 3.11 환경의 torch 2.12.0.dev20260408+cu128, MediaPipe 0.10.9, OpenCV 4.12.0을 재사용했고 ONNX 1.16.2/ONNX Runtime 1.20.1은 프로젝트 가상환경에 추가했습니다.

## 학습 종료 오류와 정상 실행 경로

첫 학습은 모델과 기록을 저장한 뒤 종료 코드 0xc0000409를 반환했습니다. 짧은 진단에서도 재현했고 Windows 이벤트에는 ucrtbase.dll 충돌이 기록됐습니다. 정확한 라이브러리 내부 원인은 확정하지 않았습니다.

cuDNN을 끈 GPU 진단이 정상 종료되어 `--disable-cudnn` 옵션을 추가하고 **동일한 데이터·모델·학습률·epoch·seed**로 전체 학습을 별도 stable 경로에서 다시 실행했습니다. 이 재실행의 종료 코드는 0이며 평가 두 번과 ONNX 변환도 모두 0입니다. 이 문서와 현재 앱 모델은 정상 종료한 stable 실행 결과입니다. 최초 실행과 진단 기록은 상위 폴더에 보존했습니다.

## 최종 결과물

- 학습 모델: `models/assistant_demo_loso_20261104_stable/final.pth`
- 전문가 사전학습 모델: 같은 폴더의 `expert_only.pth`
- 단계별 모델: stage0_encoder.pth, stage1_best.pth, stage2_best.pth, stage3_best.pth
- 앱 모델: `apps/mobile/assets/models/sign_language_assistant_demo.onnx`
- 앱 설정: `apps/mobile/assets/models/sign_model.json`
- 앱 라벨: `apps/mobile/assets/data/core_label_map.json`, `core_ksl_word_dictionary.json`
- 평가·혼동행렬·개별 예측: `stable/evaluation.json`, `stable/predictions.csv`, `stable/per_class.csv`
- 분할·학습 기록: `stable/split_summary.json`, `stable/training_history.json`
- 실제 입력 ONNX 검증: `stable/runtime_checks.json`
- 정상 종료 기록: `stable/process_exit.json`, `stable/pipeline_exit.json`

현재 앱 자산은 새 13개 모델을 가리킵니다. 기존 5단어 PTH/ONNX 파일은 보존했습니다. 이미 설치된 휴대전화 앱에는 다시 빌드·설치해야 반영됩니다. 이번 실행에서 Flutter APK 빌드, 실기기 카메라/PiP, LLM 호출, 문자·전화·알람 실제 수행은 실행하지 않았습니다. Git commit/push도 수행하지 않았습니다.

## 재실행 명령

프로젝트 루트 PowerShell에서 실행합니다. 데이터가 이미 준비됐다면 1~2단계를 생략할 수 있습니다. 새 학습은 별도 output-dir/report-dir로 보관하세요.

```powershell
$env:SIGNBRIDGE_VOCABULARY = 'assistant_demo'
$env:PYTHONUTF8 = '1'
$env:OMP_NUM_THREADS = '4'

# 최초 1회: 이미 출력 폴더가 있으면 덮어쓰지 않음
.\.venv\Scripts\python.exe scripts/data/extend_expert_data.py --output-root data/expert_assistant_demo

.\.venv\Scripts\python.exe scripts/data/prepare_assistant_data.py --source-data data/expert_assistant_demo --raw-mov "$env:USERPROFILE/Downloads/영상_데이터"

.\.venv\Scripts\python.exe scripts/training/train_pipeline.py --held-out-signer 박세준 --validation-signer 김정우 --batch-size 64 --disable-cudnn --output-dir models/assistant_demo_loso_20261104_stable --report-dir reports/assistant_demo_20261104/stable

.\.venv\Scripts\python.exe scripts/evaluation/evaluate_model.py --checkpoint models/assistant_demo_loso_20261104_stable/final.pth --output reports/assistant_demo_20261104/stable/evaluation.json

.\.venv\Scripts\python.exe apps/mobile/tools/export_sign_model.py --checkpoint models/assistant_demo_loso_20261104_stable/final.pth --target apps/mobile/assets/models/sign_language_assistant_demo.onnx

.\.venv\Scripts\python.exe scripts/evaluation/verify_onnx.py --checkpoint models/assistant_demo_loso_20261104_stable/final.pth --onnx apps/mobile/assets/models/sign_language_assistant_demo.onnx --manifest data/processed_assistant_demo/manifest.csv --output reports/assistant_demo_20261104/stable/runtime_checks.json
```
