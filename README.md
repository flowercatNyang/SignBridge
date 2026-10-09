# SignBridge training pipeline

현재 실행 설정은 **아프다, 위, 아래, 회사, 엄마** 5단어입니다. 기존 73단어 설정과 메뉴 코드는 주석으로 보존했고 원본 데이터·모델도 유지합니다.

실행 결과와 데이터 분할은 [RUN_RESULTS.md](RUN_RESULTS.md)를 참고하세요. 최종 모델은 독립 촬영자 영상 15개에서 Top-1 60.0%, Top-3 100.0%이며, 위/아래 혼동이 남아 있습니다.

친구에게 전달할 파일과 앱 연동 입력/출력 계약은 [HANDOFF.md](HANDOFF.md)에 정리했습니다. 새 5단어 가중치는 Git에서 제외되므로 별도로 받아야 합니다.

모델 출력은 5개입니다. 미검출/대기는 6번째 학습 클래스가 아니라 기존 `RecognitionGate`의 `NO_SIGN` 상태로 처리합니다. 별도 비수어 동작 영상이나 배경 클래스는 현재 학습에 포함하지 않습니다.

게이트는 손 미검출이 연속 5프레임일 때 버퍼를 초기화합니다. 손이 보이면 정지/대기 동작도 30프레임 창의 입력이 될 수 있으므로, 모든 비수어 동작을 구분해 무시하는 기능은 아닙니다. 짧은 미검출 1~4프레임 동안에는 기존 창의 예측이 이어질 수 있습니다.

```bash
python prepare_five_word_data.py --raw-mov ~/Downloads/raw_mov
python train_pipeline.py --held-out-signer 박세준 --validation-signer 김정우 --batch-size 32 --stage0-epochs 20 --stage1-epochs 40 --stage2-epochs 15 --stage3-epochs 30 --output-dir models/five_words_loso --export-path models/sign_language_five_words.pth
python evaluate_model.py --checkpoint models/sign_language_five_words.pth
python handsign_translate.py
```

`modules/vocabulary.py`에서 0=아프다, 1=위, 2=아래, 3=회사, 4=엄마로 정의합니다. 원본 73클래스 NPY에서 해당 WORD 키의 전문가 250개만 추출하여 라벨을 다시 부여합니다. 팀 영상은 `촬영자_단어` 또는 `촬영자_각도_단어`로 해석합니다. 클래스당 15개, 총 75개이며 각도가 생략되면 정면입니다. 각도의 위/아래와 단어의 위/아래는 파일명 항목 수로 구분합니다.

현재 분할은 전문가 225개 학습/25개 검증, 팀원 3명 45개 학습/김정우 15개 검증/박세준 15개 최종 테스트입니다. Stage 2·3은 전문가 검증 정확도와 팀원 검증 정확도의 평균으로 모델을 선택하며 최종 테스트 사람은 자기지도 학습에도 넣지 않습니다. 새 모델은 `models/sign_language_five_words.pth`, 처리 데이터는 `data/processed_five`에 따로 저장합니다. 실시간 UI는 5단어를 바로 인식하고 ESC는 인식 상태를 초기화합니다.

전문가 원본 영상 없이 기존 150차원 NPY를 변환하므로, 전문가와 새 영상의 관절 추출 방식이 완전히 일치한다고 보장할 수 없습니다. 또 영상 전체를 30프레임으로 리샘플링하는 학습/평가와 웹캠의 30프레임 이동 창은 시간 구간이 다릅니다. 저장 영상 테스트 결과를 실제 웹캠 정확도로 해석해서는 안 됩니다.

아래는 기존 73단어 파이프라인 설명으로, 이전 설정을 확인할 수 있도록 보존했습니다.

이 저장소는 73개 한국수어 단어를 대상으로 전문가 영상과 팀원 영상을 같은 MediaPipe 파이프라인으로 전처리하고, 수어자 독립 모델을 학습하고 평가합니다.

## 데이터 구조

영상은 다음 구조로 배치합니다. 클래스 폴더명 또는 파일 경로에는 `WORD0005` 같은 `core_label_map.json`의 키가 포함되어야 합니다.

```text
data/raw_videos/
  expert/
    WORD0005/
      *.mp4
  team/
    signer_a/
      WORD0005/
        *.mp4
  external/
    person_001/
      WORD0005/
        *.mp4
```

전문가 데이터는 클래스당 최소 50개, 팀원 데이터는 클래스당 최소 9개가 필요합니다. 팀원 9개를 파일로 복제하지 않습니다. Stage 2와 Stage 3의 각 배치에서 전문가와 팀원을 1:1로 뽑아 팀원 데이터를 oversampling합니다.

## 특징

모든 영상은 동일한 MediaPipe Hand/Pose 파이프라인을 거쳐 30프레임으로 리샘플링됩니다. 손 미검출 구간은 검출된 앞뒤 프레임으로 보간하며 원래 검출 여부는 두 개의 mask로 보존합니다.

모델 입력은 프레임당 452차원입니다.

```text
150 관절 특징 + 150 속도 + 150 가속도 + 2 손 검출 mask
```

## 실행 순서

필요 패키지를 설치합니다.

```powershell
pip install -r requirements.txt
```

전문가 데이터가 기존 `X_train.npy`, `y_train.npy` 형식이면 먼저 새 데이터 구조로 변환합니다.

```powershell
python migrate_expert_npy.py
```

기존 배열이 `(N, 30, 150)`이면 속도, 가속도, 추정 손 mask를 추가해 영상별 `(30, 452)` 파일로 변환합니다. 이미 `(N, 30, 452)`이면 값은 그대로 옮깁니다. 결과는 `data/processed/sequences/expert`와 `data/processed/manifest.csv`에 저장됩니다. 기존 전문가 manifest를 교체하려면 `--overwrite`를 명시합니다.

영상이 준비된 뒤 전처리를 실행합니다.

```powershell
python preprocess_videos.py
```

전문가 NPY를 이미 변환했고 팀원 영상만 새로 추가했다면 팀원 도메인만 처리합니다.

```powershell
python preprocess_videos.py --domain team
```

특정 도메인만 다시 처리할 수도 있습니다.

```powershell
python preprocess_videos.py --domain team --overwrite
```

팀원 한 명을 완전히 제외해 LOSO 학습을 실행합니다. 제외된 사람은 Stage 0 자기지도 학습에도 사용되지 않습니다.

```powershell
python train_pipeline.py --held-out-signer signer_c --export-path models/sign_language_gru.pth
```

학습 단계는 다음과 같습니다.

1. Stage 0: 학습에 허용된 전체 시퀀스로 마스킹 복원
2. Stage 1: 전문가 데이터 단어 분류
3. Stage 2: 전문가와 팀원 1:1 배치로 classifier만 적응
4. Stage 3: 전체 encoder를 낮은 학습률로 미세조정하고, signer ID가 있으면 gradient reversal 학습

LOSO와 외부 고정 테스트를 평가합니다.

```powershell
python evaluate_model.py --checkpoint models/loso_signer_c/final.pth
```

실시간 인식을 실행합니다.

```powershell
python handsign_translate.py --checkpoint models/sign_language_gru.pth
```

실시간 인식은 `NO_SIGN`, `TRANSITION`, `SIGN` 상태와 신뢰도 임계값, 최근 예측 합의를 사용합니다. 임계값과 합의 조건은 `--confidence`, `--consensus-size`, `--consensus-required`로 조정할 수 있습니다.

## 노트북

`Data_Preprocessing.ipynb`, `GRU_Model_Training.ipynb`, `generate_graph.ipynb`는 위 스크립트를 순서대로 실행하는 얇은 실행용 노트북입니다. 팀원별 LOSO 결과를 비교하려면 팀원마다 `--held-out-signer`를 바꾸어 별도 출력 폴더에 학습합니다.
