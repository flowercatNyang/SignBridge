// Port of assets/modules/features.py. Coordinates are from the unmirrored image.
const hp = [0,1,2,3,0,5,6,7,0,9,10,11,0,13,14,15,0,17,18,19];
const hc = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20];
const up = [1,1,2,3,1,5,6], uc = [0,2,3,4,5,6,7];
const zero = n => Array.from({length:n}, () => [0,0,0]);
const pixel = (p,w,h) => [Math.fround(p.x*w), Math.fround(p.y*h), Math.fround(p.z*w)];

function geometry(coords, parents, children, a, b) {
  const n = parents.length, out = new Float32Array(n*3+a.length);
  if (coords.flat().every(v => v === 0)) return out;
  const bones = parents.map((p,i) => coords[children[i]].map((v,j) => Math.fround(v-coords[p][j])));
  bones.forEach(([x,y,z],i) => {
    const norm = Math.hypot(x,y)+1e-6;
    out[i]=x/norm; out[n+i]=y/norm; out[2*n+i]=z;
  });
  a.forEach((v,i) => {
    const [x,y]=bones[v], [s,t]=bones[b[i]];
    out[3*n+i]=Math.acos(Math.max(-1,Math.min(1,(x*s+y*t)/(Math.hypot(x,y)*Math.hypot(s,t)+1e-6))));
  });
  return out;
}

export function extractFeatures(hands, handedness, poseLandmarks, w, h) {
  if (!(w>0 && h>0)) throw new Error('Invalid frame dimensions');
  let pose=zero(8), right=zero(21), left=zero(21);
  if (poseLandmarks?.length) {
    const p=poseLandmarks;
    const ls=pixel(p[11],w,h), rs=pixel(p[12],w,h);
    pose=[pixel(p[0],w,h),ls.map((v,i)=>Math.fround((v+rs[i])/2)),rs,
      pixel(p[14],w,h),pixel(p[16],w,h),ls,pixel(p[13],w,h),pixel(p[15],w,h)];
  }
  hands.forEach((hand,i)=> {
    const name=handedness[i]?.[0]?.categoryName;
    if (name==='Right') right=hand.map(p=>pixel(p,w,h));
    if (name==='Left') left=hand.map(p=>pixel(p,w,h));
  });
  const neck=pose[1].slice();
  const width=Math.hypot(...pose[5].map((v,i)=>v-pose[2][i]));
  const scale=width<1e-6 ? 1 : width;
  const normalize=coords=>coords.map(p=>p.map((v,i)=>Math.fround(Math.fround(v-neck[i])/scale)));
  pose=normalize(pose);
  if (right.some(p=>p.some(v=>v!==0))) right=normalize(right);
  if (left.some(p=>p.some(v=>v!==0))) left=normalize(left);
  const out=new Float32Array(150);
  out.set(geometry(right,hp,hc,[0,4,8],[1,5,9]),0);
  out.set(geometry(left,hp,hc,[0,4,8],[1,5,9]),63);
  out.set(geometry(pose,up,uc,[2,5,1],[3,6,4]),126);
  if (!out.every(Number.isFinite)) throw new Error('Invalid landmarks');
  return out;
}

export class SignSequence {
  constructor() { this.reset(); }
  reset() { this.frames=[]; this.missingSince=null; this.lastPrediction=-Infinity; }
  missing(timestamp) {
    if (this.missingSince===null) this.missingSince=timestamp;
    if (timestamp-this.missingSince>=1500) {
      this.frames=[];
      this.lastPrediction=-Infinity;
    }
  }
  add(features, timestamp) {
    // Processing latency is not loss of tracking. Only observed absence resets.
    if (this.missingSince!==null && timestamp-this.missingSince>=1500) this.reset();
    this.missingSince=null;
    this.frames.push(features);
    if (this.frames.length>30) this.frames.shift();
    if (this.frames.length<30 || timestamp-this.lastPrediction<1000) return null;
    this.lastPrediction=timestamp;
    const input=new Float32Array(30*150);
    this.frames.forEach((frame,i)=>input.set(frame,i*150));
    return input;
  }
}

export function predictionText(logits, labels) {
  if (logits.length!==112 || labels.length!==112 || !Array.from(logits).every(Number.isFinite)) {
    throw new Error('Invalid sign model output');
  }
  const best=Array.from(logits).reduce((a,_,i)=>logits[i]>logits[a]?i:a,0);
  const confidence=1/Array.from(logits).reduce((sum,v)=>sum+Math.exp(v-logits[best]),0);
  return `${labels[best]} · ${Math.round(confidence*100)}%`;
}
