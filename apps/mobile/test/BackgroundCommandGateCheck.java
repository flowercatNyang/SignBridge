package com.example.testsign;

public final class BackgroundCommandGateCheck {
    private static void expect(Object expected, Object actual) {
        if (!java.util.Objects.equals(expected, actual)) {
            throw new AssertionError("Expected " + expected + ", got " + actual);
        }
    }
    private static String stable(BackgroundCommandGate gate, String display, long now) {
        expect(null, gate.accept(display, false, now));
        expect(null, gate.accept(display, false, now + 1));
        return gate.accept(display, false, now + 2);
    }
    private static void release(BackgroundCommandGate gate, long now) {
        gate.accept(null, true, now);
        gate.accept(null, true, now + 800);
    }
    public static void main(String[] args) {
        BackgroundCommandGate gate = new BackgroundCommandGate();
        expect(null, gate.accept("엄마 · 84%", false, 0));
        expect("엄마", stable(gate, "엄마 · 99%", 10));
        expect(null, gate.accept("엄마 · 99%", false, 100));
        expect(null, gate.accept("아프다 · 99%", false, 101));
        release(gate, 200);
        // The organ is a label, not a volume command.
        expect("위(내장)", stable(gate, "위(내장) · 99%", 1100));
        release(gate, 1200);
        expect("위(방향)", stable(gate, "위(방향) · 99%", 2100));
        release(gate, 2200);
        expect("0", stable(gate, "0 · 99%", 3100));
        release(gate, 3200);
        expect("0", stable(gate, "0 · 99%", 4100));
        release(gate, 4200);
        expect(null, gate.accept("아래 · 101%", false, 5100));
        expect(null, gate.accept("아래 · 999999999999999999999%", false, 5101));
        expect(null, gate.accept("동작을 모으는 중 · 12 / 30", false, 5102));
        gate.accept("아래 · 99%", false, 5103);
        gate.accept("아래 · 99%", false, 5104);
        expect(null, gate.accept("아래 · 50%", false, 5105));
        expect("아래", stable(gate, "아래 · 99%", 5110));
        System.out.println("Background input consensus, release and label separation checks passed.");
    }
}
