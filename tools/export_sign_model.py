"""Export the supplied model and verify ONNX against PyTorch on CPU.

Dependencies: torch, numpy, onnx==1.19.1, onnxruntime==1.20.1.
Run from the repository root: python tools/export_sign_model.py
"""
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
import onnx
import onnxruntime as ort
import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'assets'))
from modules.models import SignLanguageModel


def main():
    source = ROOT / 'assets/models/sign_language_gru.pth'
    target = source.with_suffix('.onnx')
    labels = json.loads((ROOT / 'assets/data/core_label_map.json').read_text(encoding='utf-8'))
    words = json.loads((ROOT / 'assets/data/core_ksl_word_dictionary.json').read_text(encoding='utf-8'))
    assert sorted(labels.values()) == list(range(112))
    assert all(isinstance(words.get(key), str) and words[key] for key in labels)
    model = SignLanguageModel(num_classes=len(labels)).cpu().eval()
    model.load_state_dict(torch.load(source, map_location='cpu', weights_only=True), strict=True)
    torch.set_num_threads(1)
    torch.onnx.export(model, torch.zeros(1, 30, 150), str(target),
                      input_names=['features'], output_names=['logits'],
                      opset_version=17, dynamo=False)
    onnx.checker.check_model(onnx.load(target))
    session = ort.InferenceSession(str(target), providers=['CPUExecutionProvider'])
    rng = np.random.default_rng(42)
    inputs = [np.zeros((1, 30, 150), np.float32)]
    inputs += [rng.normal(size=(1, 30, 150)).astype(np.float32) for _ in range(10)]
    max_error = 0.0
    for features in inputs:
        with torch.no_grad():
            expected = model(torch.from_numpy(features)).numpy()
        actual = session.run(['logits'], {'features': features})[0]
        np.testing.assert_allclose(actual, expected, rtol=1e-4, atol=1e-4)
        assert np.argmax(actual) == np.argmax(expected)
        max_error = max(max_error, float(np.max(np.abs(actual - expected))))
    report = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'onnx_sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
              'input_shape': [1, 30, 150], 'classes': len(labels), 'opset': 17,
              'validation_cases': len(inputs), 'max_absolute_logit_error': max_error}
    target.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    # A landmark-derived case for checking the browser's actual WASM runtime.
    fixture = json.loads((ROOT / 'test/fixtures/sign_features.json').read_text())[1]
    features = np.repeat(np.array(fixture['expected'], dtype=np.float32)[None, None, :], 30, axis=1)
    with torch.no_grad():
        logits = model(torch.from_numpy(features)).numpy()[0].tolist()
    (ROOT / 'test/fixtures/sign_inference.json').write_text(
        json.dumps({'frame': fixture['expected'], 'logits': logits}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
