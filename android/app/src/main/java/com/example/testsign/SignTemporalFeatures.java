package com.example.testsign;

/** Matches build_temporal_features in assets/modules/features.py for 30 frames. */
final class SignTemporalFeatures {
    static final int FRAMES = 30, BASE = 150, FEATURES = 452;

    static float[] build(float[][] frames, float[][] masks) {
        if (frames.length != FRAMES || masks.length != FRAMES) {
            throw new IllegalArgumentException("Expected 30 frames and masks");
        }
        float[][] base = new float[FRAMES][];
        for (int t = 0; t < FRAMES; t++) {
            if (frames[t].length != BASE || masks[t].length != 2) {
                throw new IllegalArgumentException("Invalid frame or mask dimensions");
            }
            base[t] = frames[t].clone();
        }
        for (int hand = 0; hand < 2; hand++) {
            int first = -1;
            for (int t = 0; t < FRAMES; t++) {
                if (masks[t][hand] > .5f) { first = t; break; }
            }
            if (first < 0) continue;
            int previous = first;
            for (int t = 0; t < FRAMES; t++) {
                if (masks[t][hand] > .5f) { previous = t; continue; }
                int next = t + 1;
                while (next < FRAMES && masks[next][hand] <= .5f) next++;
                if (next == FRAMES) next = previous;
                double ratio = next == previous ? 0 : (double)(t - previous) / (next - previous);
                for (int c = hand * 63; c < (hand + 1) * 63; c++) {
                    base[t][c] = (float)(base[previous][c] + ratio * ((double)base[next][c] - base[previous][c]));
                }
            }
        }
        float[] result = new float[FRAMES * FEATURES];
        float[] previousVelocity = new float[BASE];
        for (int t = 0; t < FRAMES; t++) {
            int offset = t * FEATURES;
            for (int c = 0; c < BASE; c++) {
                float velocity = t == 0 ? 0 : base[t][c] - base[t - 1][c];
                result[offset + c] = base[t][c];
                result[offset + BASE + c] = velocity;
                result[offset + 2 * BASE + c] = velocity - previousVelocity[c];
                previousVelocity[c] = velocity;
            }
            result[offset + 450] = masks[t][0];
            result[offset + 451] = masks[t][1];
        }
        return result;
    }
}
