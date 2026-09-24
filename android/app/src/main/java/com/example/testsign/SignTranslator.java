package com.example.testsign;

import android.content.res.AssetManager;
import ai.onnxruntime.*;
import org.json.JSONObject;
import java.io.*;
import java.nio.FloatBuffer;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Owned by the camera worker thread; keeps only a 30-frame rolling window. */
final class SignTranslator implements AutoCloseable {
    private final OrtEnvironment environment = OrtEnvironment.getEnvironment();
    private final OrtSession session;
    private final String[] labels;
    private final String inputName;
    private final String outputName;
    private final SignSequence sequence = new SignSequence();

    SignTranslator(AssetManager assets) throws Exception {
        JSONObject config = new JSONObject(new String(read(assets,"models/sign_model.json"),StandardCharsets.UTF_8));
        if (config.getInt("frames") != 30 || config.getInt("features") != 150 ||
            !config.getString("featureSchema").equals("ksl-shoulder-normalized-150-v1")) throw new IOException("Unsupported feature schema");
        inputName = config.getString("input");
        outputName = config.getString("output");
        JSONObject map = new JSONObject(new String(read(assets,config.getString("labels")),StandardCharsets.UTF_8));
        JSONObject dictionary = new JSONObject(new String(read(assets,config.getString("dictionary")),StandardCharsets.UTF_8));
        if (map.length()==0) throw new IOException("Empty labels");
        labels = new String[map.length()];
        Iterator<String> keys=map.keys();
        while(keys.hasNext()) {
            String key=keys.next(); int i=map.getInt(key);
            if(i<0 || i>=labels.length || labels[i]!=null) throw new IOException("Invalid label index");
            labels[i]=dictionary.getString(key);
            JSONObject overrides = config.optJSONObject("labelOverrides");
            if (overrides != null && overrides.has(key)) labels[i] = overrides.getString(key);
            if(labels[i].isEmpty()) throw new IOException("Empty label");
        }
        try (OrtSession.SessionOptions options=new OrtSession.SessionOptions()) {
            options.setIntraOpNumThreads(1);
            session=environment.createSession(read(assets,config.getString("model")),options);
        }
    }

    static byte[] read(AssetManager assets,String path) throws IOException {
        try(InputStream input=assets.open("flutter_assets/assets/"+path);
            ByteArrayOutputStream output=new ByteArrayOutputStream()) {
            byte[] buffer=new byte[8192]; int count;
            while((count=input.read(buffer))!=-1) output.write(buffer,0,count);
            return output.toByteArray();
        }
    }
    void reset() { sequence.reset(); }
    void missing(long timestamp) { sequence.missing(timestamp); }

    String add(float[] features,long timestamp) throws OrtException {
        float[] featuresWindow=sequence.add(features,timestamp);
        if(sequence.size()<30) return "동작을 모으는 중 · "+sequence.size()+" / 30";
        if(featuresWindow==null) return null;
        FloatBuffer buffer=FloatBuffer.wrap(featuresWindow);
        try(OnnxTensor input=OnnxTensor.createTensor(environment,buffer,new long[]{1,30,150});
            OrtSession.Result result=session.run(Collections.singletonMap(inputName,input))) {
            float[] logits=((float[][])result.get(outputName).orElseThrow(() -> new IllegalStateException("Missing model output")).getValue())[0];
            if(logits.length!=labels.length) throw new IllegalStateException("Invalid output shape");
            int best=0;
            for(int i=0;i<logits.length;i++) {
                if(!Float.isFinite(logits[i])) throw new IllegalStateException("Non-finite logits");
                if(logits[i]>logits[best]) best=i;
            }
            double sum=0;
            for(float value:logits) sum+=Math.exp(value-logits[best]);
            double confidence=1/sum;
            return labels[best]+" · "+Math.round(confidence*100)+"%";
        }
    }
    @Override public void close() throws OrtException { reset(); session.close(); }
}
