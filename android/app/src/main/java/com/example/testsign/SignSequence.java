package com.example.testsign;

import java.util.ArrayDeque;

/** Processing latency must not be mistaken for a subject leaving the camera. */
final class SignSequence {
    private final ArrayDeque<float[]> frames = new ArrayDeque<>();
    private long missingSince = -1, lastPrediction = -1;

    void reset() { frames.clear(); missingSince=-1; lastPrediction=-1; }
    int size() { return frames.size(); }

    void missing(long timestamp) {
        if (missingSince<0) missingSince=timestamp;
        if (timestamp-missingSince>=1500) {
            frames.clear();
            lastPrediction=-1;
        }
    }

    float[] add(float[] features,long timestamp) {
        if (missingSince>=0 && timestamp-missingSince>=1500) reset();
        missingSince=-1;
        frames.add(features);
        if (frames.size()>30) frames.removeFirst();
        if (frames.size()<30 || (lastPrediction>=0 && timestamp-lastPrediction<1000)) return null;
        lastPrediction=timestamp;
        float[] input=new float[30*150];
        int offset=0;
        for (float[] frame:frames) {
            System.arraycopy(frame,0,input,offset,150);
            offset+=150;
        }
        return input;
    }
}
