"""Export a v2 checkpoint and verify ONNX against PyTorch on CPU.

Validated with torch, numpy, onnx==1.16.2, onnxruntime==1.20.1.
Run from the repository root: python apps/mobile/tools/export_sign_model.py
"""
import hashlib
import argparse
import json
from pathlib import Path
import sys

import numpy as np
import onnx
import onnxruntime as ort
import torch

ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ROOT.parents[1]
sys.path.insert(0, str(REPO_ROOT))
from modules.models import SignLanguageModel
from modules.features import INPUT_DIM, SEQUENCE_LENGTH, build_temporal_features
from modules.vocabulary import DISPLAY_LABELS


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description='Export a validated v2 checkpoint with its own vocabulary')
    parser.add_argument('--checkpoint', type=Path, default=REPO_ROOT / 'models/sign_language_five_words.pth')
    parser.add_argument('--target', type=Path, default=ROOT / 'assets/models/sign_language_five_words.onnx')
    args = parser.parse_args()
    source, target = args.checkpoint.resolve(), args.target.resolve()
    asset_root = (ROOT / 'assets').resolve()
    if asset_root not in target.parents:
        parser.error('--target must be under apps/mobile/assets')
    checkpoint = torch.load(source, map_location='cpu', weights_only=True)
    if checkpoint.get('format_version') != 2:
        raise ValueError('Expected a v2 temporal-feature checkpoint')
    labels = checkpoint['label_map']
    words = checkpoint['word_dictionary']
    expected_words = [words[key] for key in sorted(labels, key=labels.get)]
    assert labels and sorted(labels.values()) == list(range(len(labels)))
    dictionary = json.loads((REPO_ROOT / 'data/processed/ksl_word_dictionary.json').read_text(encoding='utf-8'))
    assert all(dictionary.get(key) == words[key] for key in labels)
    model = SignLanguageModel(**checkpoint['model_config']).cpu().eval()
    assert model.config['num_classes'] == len(labels) and model.config['input_dim'] == INPUT_DIM == 452
    model.load_state_dict(checkpoint['model_state'], strict=True)
    torch.set_num_threads(1)
    shape = (1, SEQUENCE_LENGTH, INPUT_DIM)
    target.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(model, torch.zeros(shape), str(target),
                      input_names=['features'], output_names=['logits'],
                      opset_version=17, dynamo=False)
    onnx.checker.check_model(onnx.load(target))
    session = ort.InferenceSession(str(target), providers=['CPUExecutionProvider'])
    assert session.get_inputs()[0].shape == list(shape)
    assert session.get_outputs()[0].shape == [1, len(labels)]
    rng = np.random.default_rng(42)
    inputs = [np.zeros(shape, np.float32)]
    inputs += [rng.normal(size=shape).astype(np.float32) for _ in range(10)]
    # Compare real temporal preprocessing too, including missing-hand interpolation.
    for _ in range(5):
        frames = rng.normal(size=(30, 150)).astype(np.float32)
        masks = rng.integers(0, 2, (30, 2)).astype(np.float32)
        for hand in range(2):
            frames[masks[:, hand] == 0, hand * 63:(hand + 1) * 63] = 0
        inputs.append(build_temporal_features(frames, masks)[None])
    max_error = 0.0
    for features in inputs:
        with torch.no_grad():
            expected = model(torch.from_numpy(features)).numpy()
        actual = session.run(['logits'], {'features': features})[0]
        np.testing.assert_allclose(actual, expected, rtol=1e-4, atol=1e-4)
        assert np.argmax(actual) == np.argmax(expected)
        max_error = max(max_error, float(np.max(np.abs(actual - expected))))
    report = {'source_checkpoint': source.relative_to(REPO_ROOT).as_posix() if REPO_ROOT in source.parents else str(source),
              'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'onnx_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'input_shape': list(shape), 'classes': len(labels), 'opset': 17,
              'class_order': expected_words, 'feature_config': checkpoint.get('feature_config'),
              'validation_cases': len(inputs), 'max_absolute_logit_error': max_error}
    write_json(target.with_suffix('.json'), report)
    write_json(ROOT / 'assets/data/core_label_map.json', labels)
    write_json(ROOT / 'assets/data/core_ksl_word_dictionary.json', {key: words[key] for key in labels})
    write_json(ROOT / 'assets/models/sign_model.json', {
        'model': target.relative_to(asset_root).as_posix(),
        'labels': 'data/core_label_map.json',
        'dictionary': 'data/core_ksl_word_dictionary.json',
        'input': 'features', 'output': 'logits',
        'featureSchema': 'ksl-temporal-452-v2',
        'frames': SEQUENCE_LENGTH, 'features': INPUT_DIM,
        'labelOverrides': {key: display for key, display in DISPLAY_LABELS.items() if key in labels},
    })
    fixture = json.loads((ROOT / 'test/fixtures/sign_features.json').read_text(encoding='utf-8'))[1]
    frames = np.repeat(np.array(fixture['expected'], dtype=np.float32)[None], 30, axis=0)
    features = build_temporal_features(frames, np.ones((30, 2), np.float32))
    with torch.no_grad():
        logits = model(torch.from_numpy(features[None])).numpy()[0].tolist()
    write_json(ROOT / 'test/fixtures/sign_inference.json',
               {'features': features.reshape(-1).tolist(), 'logits': logits})
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
