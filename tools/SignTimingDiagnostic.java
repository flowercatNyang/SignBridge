package com.example.testsign;

import java.util.Arrays;
import java.util.Locale;

/** Synthetic timing audit of the production sequence builder, not an accuracy benchmark. */
public final class SignTimingDiagnostic {
    private static float[] window(int[] intervals, boolean usePhysicalTime) {
        SignSequence sequence = new SignSequence();
        long timestamp = 0;
        float[] result = null;
        for (int index = 0; index < 30; index++) {
            if (index > 0) timestamp += intervals[(index - 1) % intervals.length];
            float[] frame = new float[150];
            // One synthetic feature moves at 1 unit/s, or follows identical frame-index samples.
            frame[0] = usePhysicalTime ? timestamp / 1000f : index / 30f;
            result = sequence.add(frame, timestamp, true, true);
        }
        if (result == null || result.length != 30 * 452) throw new AssertionError("No full window");
        return result;
    }

    private static void describe(String name, int[] intervals) {
        float[] result = window(intervals, true);
        long span = 0;
        double velocity = 0, maxAcceleration = 0;
        for (int index = 1; index < 30; index++) {
            span += intervals[(index - 1) % intervals.length];
            velocity += result[index * 452 + 150];
            // Ignore the intentional initial zero-velocity boundary.
            if (index > 1) maxAcceleration = Math.max(maxAcceleration, Math.abs(result[index * 452 + 300]));
        }
        System.out.printf(Locale.US,
            "%s: span_ms=%d, mean_feature_delta=%.6f, max_delta_acceleration=%.6f%n",
            name, span, velocity / 29, maxAcceleration);
    }

    public static void main(String[] args) {
        describe("~15 fps", new int[]{67});
        describe("10 fps", new int[]{100});
        describe("5 fps", new int[]{200});
        describe("~0.83 fps", new int[]{1200});
        describe("jitter 67/67/400 ms", new int[]{67, 67, 400});
        boolean same = Arrays.equals(window(new int[]{67}, false), window(new int[]{200}, false));
        System.out.println("Identical samples with 67ms vs 200ms timestamps produce identical model tensors: " + same);
        if (!same) throw new AssertionError("Timing behavior changed; re-audit this diagnostic");
    }
}
