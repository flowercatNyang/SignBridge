import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {extractFeatures,SignSequence,predictionText} from '../web/sign_features.mjs';

const cases=JSON.parse(readFileSync(new URL('./fixtures/sign_features.json',import.meta.url)));
for(const c of cases) test(`Python feature parity: ${c.name}`,()=> {
  const hands=[],sides=[];
  // Reverse detector order to verify that handedness, not array position, is used.
  if(c.left) { hands.push(c.left); sides.push([{categoryName:'Left'}]); }
  if(c.right) { hands.push(c.right); sides.push([{categoryName:'Right'}]); }
  const actual=extractFeatures(hands,sides,c.pose,c.width,c.height);
  assert.equal(actual.length,150);
  // acos near pi amplifies float32/float64 rounding; allow 0.0001 radians.
  actual.forEach((v,i)=>assert.ok(Math.abs(v-c.expected[i])<1e-4,`${c.name}[${i}]: ${v} vs ${c.expected[i]}`));
});
test('Only full sequences infer, at most once per second, with a bounded window',()=> {
  const sequence=new SignSequence();
  for(let i=0;i<29;i++) assert.equal(sequence.add(new Float32Array(150).fill(i),i*67),null);
  const input=sequence.add(new Float32Array(150).fill(29),29*67);
  assert.equal(input.length,4500); assert.equal(input[0],0); assert.equal(input[4499],29);
  assert.equal(sequence.add(new Float32Array(150),30*67),null);
  for(let i=31;i<44;i++) sequence.add(new Float32Array(150),i*67);
  assert.ok(sequence.add(new Float32Array(150),44*67));
  assert.equal(sequence.frames.length,30);
  assert.ok(sequence.add(new Float32Array(150),5000));
  assert.equal(sequence.frames.length,30);
  sequence.reset(); assert.equal(sequence.frames.length,0);
});
test('Slow inference still collects 30 frames instead of resetting to 1/30',()=> {
  const sequence=new SignSequence();
  for(let i=0;i<29;i++) {
    assert.equal(sequence.add(new Float32Array(150),i*1200),null);
    assert.equal(sequence.frames.length,i+1);
  }
  assert.equal(sequence.add(new Float32Array(150),29*1200).length,4500);
});
test('Brief tracking loss preserves frames; sustained absence and stop clear them',()=> {
  const sequence=new SignSequence(),frame=new Float32Array(150);
  sequence.add(frame,0);
  sequence.missing(100);
  sequence.add(frame,700);
  assert.equal(sequence.frames.length,2);
  sequence.missing(800);
  sequence.missing(2300);
  assert.equal(sequence.frames.length,0);
  sequence.add(frame,2400);
  assert.equal(sequence.frames.length,1);
  // A slow next detection must also expire an already observed absence.
  sequence.missing(2500);
  sequence.add(frame,4500);
  assert.equal(sequence.frames.length,1);
  sequence.reset(); assert.equal(sequence.frames.length,0);
});
test('Korean labels follow the class index even at low confidence',()=> {
  const map=JSON.parse(readFileSync(new URL('../assets/data/core_label_map.json',import.meta.url)));
  const words=JSON.parse(readFileSync(new URL('../assets/data/core_ksl_word_dictionary.json',import.meta.url)));
  const labels=[];
  for(const [word,index] of Object.entries(map)) labels[index]=words[word];
  const logits=new Float32Array(112); logits[49]=20;
  assert.equal(predictionText(logits,labels),'감사 · 100%');
  assert.equal(predictionText(new Float32Array(112),labels),'고민 · 1%');
  const lowConfidence=new Float32Array(112); lowConfidence[49]=1;
  assert.equal(predictionText(lowConfidence,labels),'감사 · 2%');
  logits[0]=NaN;
  assert.throws(()=>predictionText(logits,labels),/Invalid/);
});
