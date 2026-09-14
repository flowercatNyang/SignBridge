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
    private final String[] labels = new String[112];
    private final SignSequence sequence = new SignSequence();

    SignTranslator(AssetManager assets) throws Exception {
        JSONObject map = new JSONObject(new String(read(assets,"data/core_label_map.json"),StandardCharsets.UTF_8));
        JSONObject dictionary = new JSONObject(new String(read(assets,"data/core_ksl_word_dictionary.json"),StandardCharsets.UTF_8));
        if (map.length()!=112) throw new IOException("Expected 112 labels");
        Iterator<String> keys=map.keys();
        while(keys.hasNext()) {
            String key=keys.next(); int i=map.getInt(key);
            if(i<0 || i>=112 || labels[i]!=null) throw new IOException("Invalid label index");
            labels[i]=dictionary.getString(key);
            if(labels[i].isEmpty()) throw new IOException("Empty label");
        }
        try (OrtSession.SessionOptions options=new OrtSession.SessionOptions()) {
            options.setIntraOpNumThreads(1);
            session=environment.createSession(read(assets,"models/sign_language_gru.onnx"),options);
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
            OrtSession.Result result=session.run(Collections.singletonMap("features",input))) {
            float[] logits=((float[][])result.get(0).getValue())[0];
            if(logits.length!=112) throw new IllegalStateException("Invalid output shape");
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
