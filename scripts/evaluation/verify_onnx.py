"""Compare exported ONNX and Python inference on held-out real sequences."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import numpy as np
import onnxruntime as ort
import torch
from modules.data import read_manifest
from modules.paths import PROJECT_ROOT
from modules.utils import load_models_and_maps


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--checkpoint', type=Path, required=True)
    parser.add_argument('--onnx', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--confidence-threshold', type=float, default=.85)
    args = parser.parse_args()
    if not 0 <= args.confidence_threshold <= 1:
        parser.error('--confidence-threshold must be between 0 and 1')
    checkpoint = torch.load(args.checkpoint, map_location='cpu', weights_only=True)
    model, labels, _, _, _ = load_models_and_maps(str(PROJECT_ROOT), torch.device('cpu'), str(args.checkpoint))
    rows = [row for row in read_manifest(args.manifest)
            if row.domain == 'team' and row.signer_id == checkpoint['held_out_signer']]
    if not rows:
        raise ValueError('No held-out real sequences found')
    sequences = []
    for row in rows:
        if checkpoint['label_map'].get(row.class_key) != row.label:
            raise ValueError('Manifest vocabulary differs from checkpoint')
        with np.load(row.path) as archive:
            sequences.append(archive['x'].astype(np.float32))
    features = np.stack(sequences)
    with torch.no_grad():
        logits = model(torch.from_numpy(features)).numpy()
    session = ort.InferenceSession(str(args.onnx), providers=['CPUExecutionProvider'])
    converted = np.concatenate([session.run(['logits'], {'features': frame[None]})[0] for frame in features])
    np.testing.assert_allclose(converted, logits, rtol=1e-4, atol=1e-4)
    predictions = logits.argmax(1)
    if not np.array_equal(converted.argmax(1), predictions):
        raise ValueError('ONNX/PyTorch class predictions differ')
    scores = np.exp(logits - logits.max(1, keepdims=True))
    scores /= scores.sum(1, keepdims=True)
    confidence = scores.max(1)
    truth = np.asarray([row.label for row in rows])
    accepted = confidence >= args.confidence_threshold
    result = {
        'checkpoint': str(args.checkpoint.resolve()), 'onnx': str(args.onnx.resolve()),
        'torch_version': str(torch.__version__), 'onnxruntime_version': ort.__version__,
        'labels': labels, 'real_sequence_onnx_cases': len(rows),
        'max_real_logit_error': float(np.max(np.abs(converted - logits))), 'real_argmax_equal': True,
        'confidence_threshold': args.confidence_threshold, 'above_threshold_samples': int(accepted.sum()),
        'above_threshold_correct': int(((predictions == truth) & accepted).sum()),
        'above_threshold_accuracy': float((predictions[accepted] == truth[accepted]).mean()) if accepted.any() else None,
        'threshold_note': 'Offline clip scores only; does not test live consensus or hand-release gating.',
        'predictions': [{'sequence': str(row.path), 'true_label': int(row.label),
                         'predicted_label': int(prediction), 'confidence': float(score)}
                        for row, prediction, score in zip(rows, predictions, confidence)],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'predictions'}, ensure_ascii=True))


if __name__ == '__main__':
    main()
