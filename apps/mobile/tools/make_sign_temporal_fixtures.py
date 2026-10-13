"""Generate Python reference windows for Android and browser temporal features."""
import json
from pathlib import Path
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[1]))
from modules.features import build_temporal_features

rng = np.random.default_rng(2026)
cases = []
for name in ['both', 'gaps_and_edges', 'single_detection', 'absent']:
    frames = rng.normal(size=(30, 150)).astype(np.float32)
    masks = np.ones((30, 2), dtype=np.float32)
    if name == 'gaps_and_edges':
        masks[:3, 0] = 0
        masks[6:13, 0] = 0
        masks[-4:, 1] = 0
        masks[2:7, 1] = 0
    elif name == 'single_detection':
        masks[:] = 0
        masks[15, 0] = 1
    elif name == 'absent':
        masks[:] = 0
    for hand in range(2):
        frames[masks[:, hand] == 0, hand * 63:(hand + 1) * 63] = 0
    expected = build_temporal_features(frames, masks)
    cases.append({'name': name, 'frames': frames.tolist(), 'masks': masks.tolist(),
                  'expected': expected.reshape(-1).tolist()})
(ROOT / 'test/fixtures/sign_temporal.json').write_text(json.dumps(cases) + '\n', encoding='utf-8')
print(f'Wrote {len(cases)} temporal reference cases')
