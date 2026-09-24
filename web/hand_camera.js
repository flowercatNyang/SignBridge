import { extractFeatures, SignSequence, predictionText } from './sign_features.mjs';
// Pinned runtime; the user-provided models are loaded from Flutter's asset bundle.
const runtime = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14';
const video = document.querySelector('#video');
const overlay = document.querySelector('#overlay');
const context = overlay.getContext('2d');
const status = document.querySelector('#status');
const startButton = document.querySelector('#start');
const flipButton = document.querySelector('#flip');
const translation = document.querySelector('#translation');
const sequence = new SignSequence();
const asset = path => new URL(`assets/assets/${path}`, location.href).href;
let poseDetector, signWorker, labels, workerBusy = false, epoch = 0, cancelLoading;
let modelConfig;
const edges = [[0,1],[1,2],[2,3],[3,4],[0,5],[5,6],[6,7],[7,8],[5,9],[9,10],[10,11],[11,12],[9,13],[13,14],[14,15],[15,16],[13,17],[0,17],[17,18],[18,19],[19,20]];
let detector, stream, animation, front = true, generation = 0, disposed = false;
let lastTime = -1, lastInference = -1;

function stop() {
  generation++;
  cancelAnimationFrame(animation);
  if (stream) stream.getTracks().forEach(track => track.stop());
  stream = null;
  video.srcObject = null;
  context.clearRect(0, 0, overlay.width, overlay.height);
  if (detector) detector.close();
  detector = null;
  if (poseDetector) poseDetector.close();
  poseDetector = null;
  if (signWorker) signWorker.terminate();
  signWorker = null;
  if (cancelLoading) { cancelLoading(); cancelLoading = null; }
  resetTranslation();
  flipButton.disabled = true;
  startButton.disabled = false;
}

function resetTranslation() {
  sequence.reset();
  epoch++;
  workerBusy=false;
  translation.textContent='카메라 시작 후 동작을 보여 주세요';
}

async function loadLabels() {
  const read=async path=> {
    const response=await fetch(asset(path));
    if(!response.ok) throw new Error(`Missing asset: ${path}`);
    return response.json();
  };
  modelConfig=await read('models/sign_model.json');
  if(modelConfig.frames!==30 || modelConfig.features!==150 || modelConfig.featureSchema!=='ksl-shoulder-normalized-150-v1') throw new Error('Unsupported feature schema');
  const [map,words]=await Promise.all([read(modelConfig.labels),read(modelConfig.dictionary)]);
  const names=new Array(Object.keys(map).length);
  if(!names.length) throw new Error('Empty labels');
  for(const [key,index] of Object.entries(map)) {
    if(!Number.isInteger(index) || index<0 || index>=names.length || names[index] || !words[key]) throw new Error('Invalid label map');
    names[index]=modelConfig.labelOverrides?.[key] ?? words[key];
  }
  return names;
}

function loadTranslator(token) {
  return new Promise((resolve,reject)=> {
    const worker=new Worker(new URL('sign_worker.js',location.href));
    signWorker=worker;
    const timer=setTimeout(()=>reject(new Error('Translation model loading timed out')),45000);
    const finish=()=>{ clearTimeout(timer); cancelLoading=null; };
    cancelLoading=()=>{ clearTimeout(timer); reject(new Error('Camera stopped')); };
    worker.onerror=event=> {
      finish(); reject(new Error(event.message));
      if(token===generation) { stop(); status.textContent='수화 모델 오류 · 카메라 시작 버튼으로 다시 시도해 주세요.'; }
    };
    worker.onmessage=({data})=> {
      if(token!==generation) return;
      if(data.type==='ready') { finish(); resolve(); }
      if(data.type==='prediction') {
        workerBusy=false;
        if(data.epoch!==epoch) return;
        try {
          translation.textContent=predictionText(data.logits,labels);
          parent.postMessage({type:'signPrediction',display:translation.textContent},location.origin);
        }
        catch(error) { stop(); status.textContent='수화 결과 처리 오류 · 다시 시도해 주세요.'; console.error(error); }
      }
      if(data.type==='error') {
        finish(); reject(new Error(data.message));
        console.error('Sign inference:',data.message);
        stop(); status.textContent='수화 모델 오류 · 카메라 시작 버튼으로 다시 시도해 주세요.';
      }
    };
    worker.postMessage({type:'load',url:asset(modelConfig.model),config:modelConfig});
  });
}

function explain(error) {
  if (error.name === 'NotAllowedError') return '카메라 권한이 필요합니다. 브라우저 설정에서 허용 후 다시 시도해 주세요.';
  if (error.name === 'NotFoundError' || error.name === 'OverconstrainedError') return '사용 가능한 카메라가 없습니다. 다른 카메라로 다시 시도해 주세요.';
  if (error.name === 'NotReadableError') return '다른 앱이 카메라를 사용 중인지 확인해 주세요.';
  return '카메라 또는 손 인식 모델을 준비하지 못했습니다. 네트워크 연결을 확인하고 다시 시도해 주세요.';
}

async function start() {
  stop();
  if (disposed) return;
  const token = generation;
  startButton.disabled = true;
  status.textContent = '카메라와 손 인식 모델을 준비하는 중…';
  try {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
      throw new Error('카메라는 HTTPS 또는 localhost에서 사용할 수 있습니다.');
    }
    const candidate = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: { facingMode: { ideal: front ? 'user' : 'environment' }, width: { ideal: 640 }, height: { ideal: 480 } }
    });
    if (token !== generation) { candidate.getTracks().forEach(track => track.stop()); return; }
    stream = candidate;
    for (const track of stream.getVideoTracks()) {
      track.addEventListener('ended', () => {
        if (token !== generation) return;
        stop();
        status.textContent = '카메라 연결이 종료되었습니다. 다시 시작해 주세요.';
      });
    }
    const actualFacing = stream.getVideoTracks()[0].getSettings().facingMode;
    const mirror = actualFacing ? actualFacing === 'user' : front;
    video.classList.toggle('front', mirror);
    overlay.classList.toggle('front', mirror);
    video.srcObject = stream;
    await video.play();
    if (token !== generation) return;
    const { FilesetResolver, HandLandmarker, PoseLandmarker } = await import(`${runtime}/vision_bundle.mjs`);
    const files = await FilesetResolver.forVisionTasks(`${runtime}/wasm`);
    if (token !== generation) return;
    const model = await HandLandmarker.createFromOptions(files, {
      baseOptions: { modelAssetPath: new URL('assets/assets/hand_landmarker.task', location.href).href, delegate: 'CPU' },
      runningMode: 'VIDEO', numHands: 2,
      minHandDetectionConfidence: 0.5, minHandPresenceConfidence: 0.5, minTrackingConfidence: 0.5
    });
    if (token !== generation) { model.close(); return; }
    detector = model;
    const poseModel = await PoseLandmarker.createFromOptions(files, {
      baseOptions: {modelAssetPath:asset('pose_landmarker_lite.task'),delegate:'CPU'},
      runningMode:'VIDEO',numPoses:1,
      minPoseDetectionConfidence:0.5,minPosePresenceConfidence:0.5,minTrackingConfidence:0.5
    });
    if(token!==generation) { poseModel.close(); return; }
    poseDetector=poseModel;
    translation.textContent='수화 모델을 불러오는 중…';
    labels=await loadLabels();
    if(token!==generation) return;
    await loadTranslator(token);
    if(token!==generation) return;
    translation.textContent='양손과 어깨가 보이도록 동작해 주세요';
    lastTime = -1;
    lastInference = -1;
    startButton.disabled = false;
    flipButton.disabled = false;
    status.textContent = '손을 카메라에 보여 주세요.';
    animation = requestAnimationFrame(draw);
  } catch (error) {
    if (token !== generation) return;
    stop();
    status.textContent = !window.isSecureContext ? '카메라는 HTTPS 또는 localhost에서 사용할 수 있습니다.' : explain(error);
    console.error('Hand camera:', error);
  }
}

function draw(timestamp) {
  if (!detector || !stream || disposed) return;
  try {
    // Limit inference to 15fps and skip repeated video frames.
    if (video.readyState >= 2 && video.currentTime !== lastTime && timestamp - lastInference >= 66) {
      lastTime = video.currentTime;
      lastInference = timestamp;
      overlay.width = video.videoWidth;
      overlay.height = video.videoHeight;
      const result = detector.detectForVideo(video, timestamp);
      const pose = poseDetector.detectForVideo(video, timestamp);
      if (!result.landmarks.length || !pose.landmarks.length) {
        // Invalidate outstanding predictions when the subject leaves the frame.
        sequence.missing(timestamp); epoch++;
        parent.postMessage({type:'signPrediction',display:''},location.origin);
        translation.textContent='양손과 어깨가 보이도록 동작해 주세요';
      } else {
        const features=extractFeatures(result.landmarks,result.handedness,pose.landmarks[0],video.videoWidth,video.videoHeight);
        // Keep collecting while one GRU request is running; never queue another.
        const input=sequence.add(features,timestamp);
        if(sequence.frames.length<30) translation.textContent=`동작을 모으는 중 · ${sequence.frames.length} / 30`;
        if(input && !workerBusy) {
          workerBusy=true;
          signWorker.postMessage({type:'predict',features:input,epoch},[input.buffer]);
        }
      }
      for (const hand of result.landmarks) {
        context.strokeStyle = '#42ebb6';
        context.lineWidth = 3;
        for (const [a, b] of edges) {
          context.beginPath();
          context.moveTo(hand[a].x * overlay.width, hand[a].y * overlay.height);
          context.lineTo(hand[b].x * overlay.width, hand[b].y * overlay.height);
          context.stroke();
        }
        context.fillStyle = '#fff';
        for (const point of hand) {
          context.beginPath();
          context.arc(point.x * overlay.width, point.y * overlay.height, 4, 0, Math.PI * 2);
          context.fill();
        }
      }
      const text = result.landmarks.length ? `손 ${result.landmarks.length}개 감지 · 손마다 관절점 21개 추적 중` : '손을 찾는 중 · 손을 화면 안에 보여 주세요.';
      if (status.textContent !== text) status.textContent = text;
    }
    animation = requestAnimationFrame(draw);
  } catch (error) {
    stop();
    status.textContent = '손 인식 중 오류가 발생했습니다. 다시 시도해 주세요.';
    console.error('Hand inference:', error);
  }
}

startButton.addEventListener('click', start);
flipButton.addEventListener('click', () => { front = !front; start(); });
document.addEventListener('visibilitychange', () => {
  if (document.hidden) { stop(); status.textContent = '카메라 일시 중지 · 시작 버튼을 눌러 주세요.'; }
});
window.addEventListener('pagehide', stop);
window.addEventListener('message', event => {
  if (event.origin === location.origin && event.source === parent && event.data === 'dispose') {
    disposed = true;
    stop();
  }
});
