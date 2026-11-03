import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {extractFeatures,SignSequence,predictionText,buildTemporalFeatures} from '../web/sign_features.mjs';

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
test('Only full sequences infer, at most once per 500ms, with a bounded window',()=> {
  const sequence=new SignSequence();
  for(let i=0;i<29;i++) assert.equal(sequence.add(new Float32Array(150).fill(i),i*67,[1,1]),null);
  const input=sequence.add(new Float32Array(150).fill(29),29*67,[1,1]);
  assert.equal(input.length,13560); assert.equal(input[0],0); assert.equal(input[29*452+149],29);
  assert.equal(sequence.add(new Float32Array(150),30*67,[1,1]),null);
  assert.equal(sequence.add(new Float32Array(150),29*67+499,[1,1]),null);
  assert.ok(sequence.add(new Float32Array(150),29*67+500,[1,1]));
  assert.equal(sequence.frames.length,30);
  assert.ok(sequence.add(new Float32Array(150),5000,[1,1]));
  assert.equal(sequence.frames.length,30);
  sequence.reset(); assert.equal(sequence.frames.length,0);
});
test('Slow inference still collects 30 frames instead of resetting to 1/30',()=> {
  const sequence=new SignSequence();
  for(let i=0;i<29;i++) {
    assert.equal(sequence.add(new Float32Array(150),i*1200,[1,1]),null);
    assert.equal(sequence.frames.length,i+1);
  }
  assert.equal(sequence.add(new Float32Array(150),29*1200,[1,1]).length,13560);
});
test('Brief tracking loss preserves frames; sustained absence and stop clear them',()=> {
  const sequence=new SignSequence(),frame=new Float32Array(150);
  sequence.add(frame,0,[1,1]);
  sequence.missing(100);
  sequence.add(frame,700,[1,1]);
  assert.equal(sequence.frames.length,2);
  sequence.missing(800);
  sequence.missing(2300);
  assert.equal(sequence.frames.length,0);
  sequence.add(frame,2400,[1,1]);
  assert.equal(sequence.frames.length,1);
  // A slow next detection must also expire an already observed absence.
  sequence.missing(2500);
  sequence.add(frame,4500,[1,1]);
  assert.equal(sequence.frames.length,1);
  sequence.reset(); assert.equal(sequence.frames.length,0); assert.equal(sequence.masks.length,0);
});

const temporalCases=JSON.parse(readFileSync(new URL('./fixtures/sign_temporal.json',import.meta.url)));
for (const c of temporalCases) test('Python temporal parity: '+c.name,()=> {
  const before=JSON.stringify(c.frames);
  const actual=buildTemporalFeatures(c.frames,c.masks);
  assert.equal(actual.length,13560);
  actual.forEach((v,i)=>assert.ok(Math.abs(v-c.expected[i])<1e-6,c.name+' at '+i));
  assert.equal(JSON.stringify(c.frames),before,'Overlapping windows must keep raw frames');
  const sequence=new SignSequence();
  let window;
  c.frames.forEach((frame,i)=>{window=sequence.add(frame,i*67,c.masks[i]);});
  assert.deepEqual(window,actual);
});

test('Deployed labels follow checkpoint order and display overrides',()=> {
  const config=JSON.parse(readFileSync(new URL('../assets/models/sign_model.json',import.meta.url)));
  const report=JSON.parse(readFileSync(new URL('../assets/'+config.model.replace(/\.onnx$/,'.json'),import.meta.url)));
  const map=JSON.parse(readFileSync(new URL('../assets/data/core_label_map.json',import.meta.url)));
  const words=JSON.parse(readFileSync(new URL('../assets/data/core_ksl_word_dictionary.json',import.meta.url)));
  const labels=[],canonical=[];
  for(const [word,index] of Object.entries(map)) {
    canonical[index]=words[word];
    labels[index]=config.labelOverrides?.[word] ?? words[word];
  }
  assert.deepEqual(canonical,report.class_order);
  assert.equal(labels.length,report.classes);
  labels.forEach((label,i)=> {
    const logits=new Float32Array(labels.length); logits[i]=100;
    assert.equal(predictionText(logits,labels),label+' · 100%');
  });
  assert.equal(predictionText(new Float32Array(labels.length),labels),labels[0]+' · '+Math.floor(100/labels.length)+'%');
  const invalid=new Float32Array(labels.length); invalid[0]=NaN;
  assert.throws(()=>predictionText(invalid,labels),/Invalid/);
  assert.throws(()=>predictionText([1],labels),/Invalid/);
  assert.equal(config.features,452);
  assert.equal(config.frames,30);
});

test('Confidence below 75 percent cannot round up into an action',()=> {
  for (const probability of [.749,.749999,.75,.751]) {
    const logits=[Math.log(4*probability/(1-probability)),0,0,0,0];
    const percent=Number(predictionText(logits,['아프다','위','아래','회사','엄마']).match(/(\d+)%$/)[1]);
    assert.equal(percent>=75,probability>=.75);
  }
});
