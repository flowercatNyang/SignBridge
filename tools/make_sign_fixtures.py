"""Generate cross-platform regression fixtures from the supplied Python extractor."""
import json
from pathlib import Path
import sys
from types import SimpleNamespace as NS
import numpy as np

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'assets'))
from modules.features import extract_keypoints

rng=np.random.default_rng(123)
def points(n):
    return [dict(x=float(x),y=float(y),z=float(z)) for x,y,z in rng.uniform(-0.2,0.8,(n,3)).astype(np.float32)]
def wrapped(p):
    return NS(landmark=[NS(**v) for v in p]) if p else None

cases=[]
for name,has_r,has_l,has_p,w,h in [
    ('empty',False,False,False,640,480),
    ('both_landscape',True,True,True,640,480),
    ('right_portrait',True,False,True,480,640),
    ('left_only',False,True,True,640,480),
    ('no_pose',True,True,False,640,480),
    ('pose_only',False,False,True,640,480),
]:
    right=points(21) if has_r else None
    left=points(21) if has_l else None
    pose=points(33) if has_p else None
    expected=extract_keypoints(NS(right_hand_landmarks=wrapped(right),left_hand_landmarks=wrapped(left),pose_landmarks=wrapped(pose)),w,h)
    cases.append(dict(name=name,right=right,left=left,pose=pose,width=w,height=h,expected=expected.tolist()))
target=root/'test/fixtures/sign_features.json'
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
print(f'Wrote {len(cases)} Python reference cases')
