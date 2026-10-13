package com.example.testsign;

import java.util.ArrayDeque;

/** Processing latency must not be mistaken for a subject leaving the camera. */
final class SignSequence {
    private final ArrayDeque<float[]> frames = new ArrayDeque<>();
    private final ArrayDeque<float[]> masks = new ArrayDeque<>();
    private long missingSince = -1, lastPrediction = -1;

    void reset() { frames.clear(); masks.clear(); missingSince=-1; lastPrediction=-1; }
    int size() { return frames.size(); }

    void missing(long timestamp) {
        if (missingSince<0) missingSince=timestamp;
        if (timestamp-missingSince>=1500) {
            frames.clear();
            masks.clear();
            lastPrediction=-1;
        }
    }

    float[] add(float[] features,long timestamp,boolean rightDetected,boolean leftDetected) {
        if (missingSince>=0 && timestamp-missingSince>=1500) reset();
        missingSince=-1;
        frames.add(features.clone());
        masks.add(new float[]{rightDetected ? 1 : 0,leftDetected ? 1 : 0});
        if (frames.size()>30) { frames.removeFirst(); masks.removeFirst(); }
        if (frames.size()<30 || (lastPrediction>=0 && timestamp-lastPrediction<500)) return null;
        lastPrediction=timestamp;
        return SignTemporalFeatures.build(frames.toArray(new float[0][]),masks.toArray(new float[0][]));
    }
}
