"""Compare Android feature extraction against the committed Python fixtures (JDK required)."""
import json
from pathlib import Path
import struct
import subprocess

root=Path(__file__).resolve().parents[1]
out=root/'build/sign-tests'
out.mkdir(parents=True,exist_ok=True)
cases=json.loads((root/'test/fixtures/sign_features.json').read_text())
with (out/'features.bin').open('wb') as f:
    f.write(struct.pack('>i',len(cases)))
    for c in cases:
        f.write(struct.pack('>ii',c['width'],c['height']))
        for key in ['right','left','pose']:
            f.write(struct.pack('>?',c[key] is not None))
            if c[key]:
                for p in c[key]: f.write(struct.pack('>fff',p['x'],p['y'],p['z']))
        f.write(struct.pack('>150f',*c['expected']))
subprocess.run(['javac','-encoding','UTF-8','-d',str(out),str(root/'android/app/src/main/java/com/example/testsign/SignFeatures.java'),str(root/'test/SignFeaturesCheck.java')],check=True)
subprocess.run(['java','-cp',str(out),'SignFeaturesCheck',str(out/'features.bin')],check=True)
subprocess.run(['javac','-encoding','UTF-8','-d',str(out),str(root/'android/app/src/main/java/com/example/testsign/SignSequence.java'),str(root/'test/SignSequenceCheck.java')],check=True)
subprocess.run(['java','-cp',str(out),'com.example.testsign.SignSequenceCheck'],check=True)
