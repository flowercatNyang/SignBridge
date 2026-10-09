# SignBridge training pipeline

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
