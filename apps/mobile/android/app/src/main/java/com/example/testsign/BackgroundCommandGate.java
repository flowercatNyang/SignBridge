package com.example.testsign;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Recognition tokens only; never returns an executable phone command. */
final class BackgroundCommandGate {
    private static final Pattern DISPLAY = Pattern.compile("^(.*) · (\\d+)%$");
    private String lastCommand;
    private long absentSince = -1;
    private String candidate;
    private int observations;

    void reset() { lastCommand = null; absentSince = -1; candidate = null; observations = 0; }
    String lastCommand() { return lastCommand; }
    void executed(String command) { lastCommand = command; absentSince = -1; }
    String accept(String display, boolean absent, long now) {
        if (absent) {
            candidate = null; observations = 0;
            if (absentSince < 0) absentSince = now;
            if (now - absentSince >= 800) reset();
            return null;
        }
        absentSince = -1;
        if (lastCommand != null) return null;
        if (display == null) { candidate = null; observations = 0; return null; }
        Matcher match = DISPLAY.matcher(display);
        if (!match.matches()) { candidate = null; observations = 0; return null; }
        int confidence;
        try { confidence = Integer.parseInt(match.group(2)); }
        catch (NumberFormatException e) { candidate = null; observations = 0; return null; }
        if (confidence < 85 || confidence > 100) { candidate = null; observations = 0; return null; }
        String token = match.group(1).trim();
        if (token.isEmpty()) return null;
        if (!token.equals(candidate)) { candidate = token; observations = 0; }
        if (++observations < 3) return null;
        lastCommand = token;
        return token;
    }
}
