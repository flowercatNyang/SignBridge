package com.example.testsign;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Recognition tokens only; never returns an executable phone command. */
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
        if (lastCommand != null) return null;
        if (display == null) return null;
        Matcher match = DISPLAY.matcher(display);
        if (!match.matches()) return null;
        int confidence;
        try { confidence = Integer.parseInt(match.group(2)); }
        catch (NumberFormatException e) { return null; }
        if (confidence < 85 || confidence > 100) return null;
        String token = match.group(1).trim();
        if (token.isEmpty()) return null;
        lastCommand = token;
        return token;
    }
}
