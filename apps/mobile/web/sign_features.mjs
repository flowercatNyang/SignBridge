// Port of the repository's modules/features.py. Coordinates are from the unmirrored image.
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

// Matches Python build_temporal_features; live windows always contain 30 frames.
export function buildTemporalFeatures(frames, masks) {
  if (frames.length !== 30 || masks.length !== 30 ||
      frames.some(frame => frame.length !== 150) || masks.some(mask => mask.length !== 2)) {
    throw new Error('Expected 30 frames of 150 features and two hand masks');
  }
  const base = frames.map(frame => Float32Array.from(frame));
  for (let hand = 0; hand < 2; hand++) {
    const first = masks.findIndex(mask => mask[hand] > .5);
    if (first < 0) continue;
    let previous = first;
    for (let t = 0; t < 30; t++) {
      if (masks[t][hand] > .5) { previous = t; continue; }
      let next = t + 1;
      while (next < 30 && masks[next][hand] <= .5) next++;
      if (next === 30) next = previous;
      const ratio = next === previous ? 0 : (t - previous) / (next - previous);
      for (let c = hand * 63; c < (hand + 1) * 63; c++) {
        base[t][c] = base[previous][c] + ratio * (base[next][c] - base[previous][c]);
      }
    }
  }
  const result = new Float32Array(30 * 452), previousVelocity = new Float32Array(150);
  for (let t = 0; t < 30; t++) {
    const offset = t * 452;
    for (let c = 0; c < 150; c++) {
      const velocity = t === 0 ? 0 : Math.fround(base[t][c] - base[t - 1][c]);
      result[offset + c] = base[t][c];
      result[offset + 150 + c] = velocity;
      result[offset + 300 + c] = velocity - previousVelocity[c];
      previousVelocity[c] = velocity;
    }
    result[offset + 450] = masks[t][0];
    result[offset + 451] = masks[t][1];
  }
  return result;
}

export class SignSequence {
  constructor() { this.reset(); }
  reset() { this.frames=[]; this.masks=[]; this.missingSince=null; this.lastPrediction=-Infinity; }
  missing(timestamp) {
    if (this.missingSince===null) this.missingSince=timestamp;
    if (timestamp-this.missingSince>=1500) {
      this.frames=[]; this.masks=[];
      this.lastPrediction=-Infinity;
    }
  }
  add(features, timestamp, handMask) {
    // Processing latency is not loss of tracking. Only observed absence resets.
    if (this.missingSince!==null && timestamp-this.missingSince>=1500) this.reset();
    this.missingSince=null;
    this.frames.push(Float32Array.from(features));
    this.masks.push(Float32Array.from(handMask));
    if (this.frames.length>30) { this.frames.shift(); this.masks.shift(); }
    if (this.frames.length<30 || timestamp-this.lastPrediction<500) return null;
    this.lastPrediction=timestamp;
    return buildTemporalFeatures(this.frames,this.masks);
  }
}

export function predictionText(logits, labels) {
  if (!labels.length || logits.length!==labels.length || !Array.from(logits).every(Number.isFinite)) {
    throw new Error('Invalid sign model output');
  }
  const best=Array.from(logits).reduce((a,_,i)=>logits[i]>logits[a]?i:a,0);
  const confidence=1/Array.from(logits).reduce((sum,v)=>sum+Math.exp(v-logits[best]),0);
  return `${labels[best]} · ${Math.floor(confidence*100)}%`;
}
