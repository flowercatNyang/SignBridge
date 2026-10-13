package com.example.testsign;

import java.io.DataInputStream;
import java.io.FileInputStream;

public final class SignTemporalFeaturesCheck {
    public static void main(String[] args) throws Exception {
        try (DataInputStream input = new DataInputStream(new FileInputStream(args[0]))) {
            int cases = input.readInt();
            for (int n = 0; n < cases; n++) {
                float[][] frames = new float[30][150], masks = new float[30][2];
                for (float[] frame : frames) for (int c = 0; c < 150; c++) frame[c] = input.readFloat();
                for (float[] mask : masks) for (int c = 0; c < 2; c++) mask[c] = input.readFloat();
                float[] actual = SignTemporalFeatures.build(frames, masks);
                SignSequence sequence = new SignSequence();
                float[] window = null;
                for (int t = 0; t < 30; t++) window = sequence.add(frames[t], t * 67, masks[t][0] > .5f, masks[t][1] > .5f);
                for (int i = 0; i < actual.length; i++) {
                    float expected = input.readFloat();
                    if (Math.abs(actual[i] - expected) > 1e-6f || actual[i] != window[i]) {
                        throw new AssertionError("Temporal mismatch in case " + n + " at " + i);
                    }
                }
            }
            System.out.println("Java temporal/Python parity passed: " + cases + " windows");
        }
    }
}
