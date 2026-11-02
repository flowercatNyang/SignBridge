package com.example.testsign;

public final class BackgroundCommandGateCheck {
    private static void expect(Object expected, Object actual) {
        if (!java.util.Objects.equals(expected, actual)) {
            throw new AssertionError("Expected " + expected + ", got " + actual);
        }
    }
    public static void main(String[] args) {
        BackgroundCommandGate gate = new BackgroundCommandGate();
        expect(null, gate.accept("위 · 74%", false, 0));
        expect("volumeUp", gate.accept("위 · 75%", false, 100));
        expect(null, gate.accept("위 · 99%", false, 10000));
        expect("volumeDown", gate.accept("아래 · 99%", false, 10100));
        gate.accept(null, true, 10200);
        gate.accept(null, true, 10999);
        expect(null, gate.accept("아래 · 99%", false, 11000));
        gate.accept(null, true, 11100);
        gate.accept(null, true, 11900);
        expect("volumeDown", gate.accept("아래 · 99%", false, 12000));
        // A foreground action must not repeat when the same sign is held entering PiP.
        gate.executed("mother");
        expect(null, gate.accept("엄마 · 98%", false, 13000));
        expect("company", gate.accept("회사 · 90%", false, 13100));
        expect("emergency", gate.accept("아프다 · 90%", false, 13200));
        expect(null, gate.accept("동작을 모으는 중 · 12 / 30", false, 13300));
        expect(null, gate.accept("위 · 101%", false, 13400));
        expect(null, gate.accept("위 · 999999999999999999999%", false, 13500));
        gate.reset();
        expect("volumeUp", gate.accept("위 · 99%", false, 14000));
        // Intermittent detections break the continuous absence interval.
        gate.accept(null, true, 14100);
        gate.accept(null, false, 14500);
        gate.accept(null, true, 15000);
        expect(null, gate.accept("위 · 99%", false, 15100));
        System.out.println("Background command threshold, re-arm and handoff checks passed.");
    }
}
