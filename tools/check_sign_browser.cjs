// Run after flutter build web; requires Playwright and installed Chrome.
const {chromium}=require('../.model-tools/browser/node_modules/playwright');
const fs=require('fs');
const path=require('path');
const http=require('http');
const assert=require('assert/strict');
const root=path.resolve(__dirname,'../build/web');
const fixture=require('../test/fixtures/sign_features.json')[1];
const reference=require('../test/fixtures/sign_inference.json');
const mime={'.html':'text/html','.js':'application/javascript','.mjs':'application/javascript','.json':'application/json','.wasm':'application/wasm'};

(async()=> {
  const server=http.createServer((req,res)=> {
    const file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
    if(!file.startsWith(root+path.sep)) { res.writeHead(403);res.end();return; }
    fs.readFile(file,(error,data)=> {
      res.writeHead(error?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});
      res.end(error?'Not found':data);
    });
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    browser=await chromium.launch({channel:'chrome',headless:true});
    const page=await browser.newPage({viewport:{width:390,height:500}});
    const errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    const url=`http://127.0.0.1:${server.address().port}/hand_camera.html`;
    // Deterministic camera/landmarks; the exported GRU and ONNX WASM are real.
    await page.addInitScript(()=> {
      window.landmarksVisible=true;
      navigator.mediaDevices.getUserMedia=async()=> {
        if(window.denyCamera) throw new DOMException('Denied','NotAllowedError');
        const canvas=document.createElement('canvas'); canvas.width=640;canvas.height=480;
        const context=canvas.getContext('2d');
        const timer=setInterval(()=>{context.fillStyle='#243247';context.fillRect(0,0,640,480);},33);
        const stream=canvas.captureStream(30);
        const track=stream.getTracks()[0],stop=track.stop.bind(track);
        track.stop=()=>{clearInterval(timer);stop();};
        window.cameraStream=stream;
        return stream;
      };
    });
    await page.route('**/vision_bundle.mjs',route=>route.fulfill({contentType:'application/javascript',body:`
      const f=${JSON.stringify(fixture)};
      export const FilesetResolver={forVisionTasks:async()=>({})};
      export const HandLandmarker={createFromOptions:async()=>({close(){},detectForVideo(){
        const start=performance.now();
        while(performance.now()-start<${Number(process.env.SIGN_TEST_FRAME_DELAY_MS)||0}) {}
        return {
        landmarks:window.landmarksVisible?[f.right,f.left]:[],
        handedness:[[{categoryName:'Right'}],[{categoryName:'Left'}]]};}})};
      export const PoseLandmarker={createFromOptions:async()=>({close(){},detectForVideo(){return {landmarks:[f.pose]};}})};
    `}));
    await page.goto(url);
    await page.locator('#start').click();
    await page.waitForFunction(()=>/수화 모델|동작을 모으는|%/.test(document.querySelector('#translation').textContent));
    await page.waitForFunction(()=>/%/.test(document.querySelector('#translation').textContent),{},{timeout:60000});
    const result=await page.locator('#translation').textContent();
    console.log('Camera pipeline result:',result);
    assert.match(result,/[가-힣]+ · \d+%/);
    const box=await page.locator('.translation').boundingBox(),cameraBox=await page.locator('.preview').boundingBox();
    assert.ok(box.y+box.height<=cameraBox.y+1,'Translation must sit above camera');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    fs.mkdirSync(path.resolve(__dirname,'../build/sign-tests'),{recursive:true});
    await page.screenshot({path:path.resolve(__dirname,'../build/sign-tests/translation.png')});
    const actual=await page.evaluate(async reference=> {
      const worker=new Worker('sign_worker.js');
      try {
        return await new Promise((resolve,reject)=> {
          const timer=setTimeout(()=>reject(new Error('WASM timeout')),45000);
          worker.onerror=e=>{clearTimeout(timer);reject(new Error(e.message));};
          worker.onmessage=({data})=> {
            if(data.type==='ready') {
              const features=new Float32Array(4500);
              for(let i=0;i<30;i++) features.set(reference.frame,i*150);
              worker.postMessage({type:'predict',features,epoch:0});
            } else if(data.type==='prediction') {clearTimeout(timer);resolve(data.logits);}
            else if(data.type==='error') {clearTimeout(timer);reject(new Error(data.message));}
          };
          worker.postMessage({type:'load',url:new URL('assets/assets/models/sign_language_gru.onnx',location.href).href});
        });
      } finally {worker.terminate();}
    },reference);
    const maxError=Math.max(...actual.map((v,i)=>Math.abs(v-reference.logits[i])));
    assert.ok(maxError<1e-4,`WASM/PyTorch mismatch: ${maxError}`);
    console.log('Actual ONNX WASM/PyTorch max error:',maxError);
    await page.evaluate(()=>window.landmarksVisible=false);
    await page.waitForFunction(()=>document.querySelector('#translation').textContent.includes('어깨'));
    await page.locator('#flip').click();
    await page.waitForFunction(()=>!document.querySelector('#flip').disabled,{},{timeout:60000});
    assert.match(await page.locator('#translation').textContent(),/어깨/);
    await page.evaluate(()=>{window.denyCamera=true;});
    await page.locator('#start').click();
    await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('권한'));
    assert.equal(await page.evaluate(()=>window.cameraStream.getTracks().every(t=>t.readyState==='ended')),true);
    await page.evaluate(()=>{window.denyCamera=false;window.landmarksVisible=true;});
    await page.locator('#start').click();
    await page.waitForFunction(()=>!document.querySelector('#flip').disabled,{},{timeout:60000});
    await page.evaluate(()=>window.postMessage('dispose',location.origin));
    await page.waitForFunction(()=>window.cameraStream.getTracks().every(t=>t.readyState==='ended'));
    assert.equal(await page.locator('#flip').isDisabled(),true);
    assert.deepEqual(errors,[]);
    console.log('PASS: translation placement, real inference, missing hands, flip, permission retry, dispose');
  } finally {if(browser) await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
