package com.example.testsign;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Same threshold/re-arm semantics as Flutter, with a monotonic clock. */
final class BackgroundCommandGate {
    private static final Pattern DISPLAY = Pattern.compile("^(.*) · (\\d+)%$");
    private String lastCommand;
    private long absentSince = -1;

    void reset() { lastCommand = null; absentSince = -1; }
    String lastCommand() { return lastCommand; }
    void executed(String command) { lastCommand = command; absentSince = -1; }
    String accept(String display, boolean absent, long now) {
        if (absent) {
            if (absentSince < 0) absentSince = now;
            if (now - absentSince >= 800) reset();
            return null;
        }
        absentSince = -1;
        if (display == null) return null;
        Matcher match = DISPLAY.matcher(display);
        if (!match.matches()) return null;
        int confidence;
        try { confidence = Integer.parseInt(match.group(2)); }
        catch (NumberFormatException e) { return null; }
        if (confidence < 75 || confidence > 100) return null;
        String command;
        switch (match.group(1).trim()) {
            case "위": command = "volumeUp"; break;
            case "아래": command = "volumeDown"; break;
            case "회사": command = "company"; break;
            case "엄마": command = "mother"; break;
            case "아프다": command = "emergency"; break;
            default: return null;
        }
        if (command.equals(lastCommand)) return null;
        lastCommand = command;
        return command;
    }
}
