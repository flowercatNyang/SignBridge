// GRU inference runs off the rendering thread. stop() terminates this worker.
importScripts('https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/ort.min.js');
ort.env.wasm.wasmPaths='https://cdn.jsdelivr.net/npm/onnxruntime-web@1.20.1/dist/';
ort.env.wasm.numThreads=1;
let session, config;
self.onmessage=async ({data})=> {
  try {
    if (data.type==='load') {
      config=data.config;
      session=await ort.InferenceSession.create(data.url,{executionProviders:['wasm']});
      self.postMessage({type:'ready'});
    } else if (data.type==='predict') {
      const input=new ort.Tensor('float32',data.features,[1,30,150]);
      let result;
      try {
        result=await session.run({[config.input]:input});
        self.postMessage({type:'prediction',epoch:data.epoch,logits:Array.from(result[config.output].data)});
      } finally {
        input.dispose();
        if(result) Object.values(result).forEach(tensor=>tensor.dispose());
      }
    }
  } catch(error) { self.postMessage({type:'error',message:String(error)}); }
};
