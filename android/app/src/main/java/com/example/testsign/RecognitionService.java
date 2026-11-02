package com.example.testsign;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.media.AudioManager;
import android.os.*;
import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.Map;

/** Keeps the application-owned pipeline alive when no Flutter view is visible. */
public final class RecognitionService extends Service {
    public interface Ready { void complete(String error); }
    private static final String CHANNEL = "signbridge_recognition";
    private static final String ACTIONS = "signbridge_commands";
    private static final int ONGOING = 7101, COMMAND = 7102;
    private static RecognitionService running;
    private static Ready pending;
    private static WeakReference<MainActivity> host = new WeakReference<>(null);
    private static boolean foreground;
    private static String pendingCommand, pendingCommandToken;
    private static long commandCreated;
    private static final BackgroundCommandGate gate = new BackgroundCommandGate();
    private CameraPipeline pipeline;
    private String lastAction = "수어를 보여 주세요.";

    public static boolean isEnabled() { return running != null; }
    public static boolean handlesPredictions() { return running != null && !foreground; }
    public static void attach(MainActivity activity, boolean resumed) {
        host = new WeakReference<>(activity);
        foreground = resumed;
    }
    public static void detached(MainActivity activity) {
        if (host.get() == activity) { host.clear(); foreground = false; }
    }
    public static void recordCommand(String command) { gate.executed(command); }
    public static void resetGate() { gate.reset(); }
    public static String consumeCommand(String token) {
        // MainActivity is exported for the launcher. Do not trust arbitrary intent extras.
        if (token == null || !token.equals(pendingCommandToken) ||
            SystemClock.elapsedRealtime() - commandCreated > 120000) return null;
        String command = pendingCommand;
        pendingCommand = null;
        pendingCommandToken = null;
        return command;
    }
    public static Map<String,Object> state(Context context) {
        Map<String,Object> value = new HashMap<>();
        value.put("enabled", isEnabled());
        value.put("lastCommand", gate.lastCommand());
        value.put("pipEnabled", context.getSharedPreferences("signbridge", MODE_PRIVATE).getBoolean("backgroundPip", true));
        value.put("status", running == null ? "백그라운드 인식 꺼짐" : running.lastAction);
        return value;
    }
    private static void changed() {
        MainActivity activity = host.get();
        if (activity != null) activity.backgroundStateChanged();
    }
    public static void enable(Activity activity, Ready ready) {
        if (running != null) { ready.complete(null); return; }
        if (pending != null) { ready.complete("백그라운드 인식을 시작하는 중입니다."); return; }
        pending = ready;
        try {
            Intent intent = new Intent(activity, RecognitionService.class);
            if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(intent);
            else activity.startService(intent);
        } catch (Exception e) { finishStart(e.getLocalizedMessage()); }
    }
    private static void finishStart(String error) {
        Ready callback = pending;
        pending = null;
        if (callback != null) callback.complete(error);
    }
    public static void disable(Context context) {
        pendingCommand = null;
        pendingCommandToken = null;
        context.getSystemService(NotificationManager.class).cancel(COMMAND);
        if (running != null) running.shutdown();
        context.stopService(new Intent(context, RecognitionService.class));
    }
    public static void cameraFailed(String message) {
        if (running == null) return;
        RecognitionService service = running;
        service.notifyCommand("카메라 중지", message + " 앱에서 다시 시작해 주세요.", null);
        service.shutdown();
        service.stopSelf();
    }
    public static void prediction(String display, boolean absent, long timestamp) {
        // Observe absence even in the foreground, but only execute here when Flutter is inactive.
        if (foreground) {
            gate.accept(null, absent, timestamp);
            return;
        }
        if (running == null) return;
        String command = gate.accept(display, absent, timestamp);
        if (command != null) running.execute(command, display);
    }

    @Override public void onCreate() {
        super.onCreate();
        pipeline = CameraPipeline.get(this);
        prepareNotifications(this);
    }
    public static void prepareNotifications(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(new NotificationChannel(CHANNEL, "수어 백그라운드 인식", NotificationManager.IMPORTANCE_LOW));
            manager.createNotificationChannel(new NotificationChannel(ACTIONS, "인식한 기능 실행", NotificationManager.IMPORTANCE_DEFAULT));
        }
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && "stop".equals(intent.getAction())) {
            pendingCommand = null;
            pendingCommandToken = null;
            getSystemService(NotificationManager.class).cancel(COMMAND);
            shutdown();
            stopSelf();
            return START_NOT_STICKY;
        }
        try {
            Notification notification = ongoing();
            if (Build.VERSION.SDK_INT >= 30) startForeground(ONGOING, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA);
            else startForeground(ONGOING, notification);
            running = this;
            pipeline.start();
            changed();
            finishStart(null);
        } catch (Exception e) {
            finishStart("백그라운드 카메라 시작 실패: " + e.getLocalizedMessage());
            shutdown();
            stopSelf();
        }
        // A killed camera service must be started again by the user while the app is visible.
        return START_NOT_STICKY;
    }
    private Notification.Builder builder(String channel) {
        return Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, channel) : new Notification.Builder(this);
    }
    private PendingIntent open(String command) {
        Intent intent = new Intent(this, MainActivity.class)
            .setAction(command == null ? "signbridge.open" : "signbridge.command." + command)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        if (command != null) {
            pendingCommand = command;
            pendingCommandToken = java.util.UUID.randomUUID().toString();
            commandCreated = SystemClock.elapsedRealtime();
            intent.putExtra("backgroundCommandToken", pendingCommandToken);
        }
        return PendingIntent.getActivity(this, command == null ? 0 : command.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private Notification ongoing() {
        PendingIntent stop = PendingIntent.getService(this, 1,
            new Intent(this, RecognitionService.class).setAction("stop"),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return builder(CHANNEL).setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentTitle("수어 백그라운드 인식 켜짐")
            .setContentText("PiP 창이 없어도 카메라를 사용합니다. · " + lastAction)
            .setContentIntent(open(null)).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(new Notification.Action.Builder(null, "인식 중지", stop).build()).build();
    }
    private void notifyCommand(String title, String message, String command) {
        getSystemService(NotificationManager.class).notify(COMMAND,
            builder(ACTIONS).setSmallIcon(android.R.drawable.ic_menu_view)
                .setContentTitle(title).setContentText(message)
                .setContentIntent(open(command)).setAutoCancel(true).build());
    }
    private void execute(String command, String display) {
        try {
            if (command.equals("volumeUp") || command.equals("volumeDown")) {
                AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
                if (audio.isVolumeFixed()) throw new IllegalStateException("이 기기는 볼륨 조절을 지원하지 않습니다.");
                audio.adjustStreamVolume(AudioManager.STREAM_MUSIC,
                    command.equals("volumeUp") ? AudioManager.ADJUST_RAISE : AudioManager.ADJUST_LOWER, 0);
                lastAction = display + " · 볼륨 " + audio.getStreamVolume(AudioManager.STREAM_MUSIC);
            } else {
                MainActivity activity = host.get();
                if (activity != null && activity.executePipCommand(command)) {
                    lastAction = display + " · 기능 실행 요청";
                } else {
                    // A camera foreground service does not grant background activity-launch rights.
                    lastAction = display + " · 알림을 눌러 실행";
                    notifyCommand(display, "인식했습니다. 눌러서 기능을 실행하세요.", command);
                }
            }
        } catch (Exception e) {
            lastAction = "실행 실패: " + e.getLocalizedMessage();
            notifyCommand("수어 기능 실행 실패", lastAction, null);
        }
        getSystemService(NotificationManager.class).notify(ONGOING, ongoing());
        changed();
    }
    private void shutdown() {
        if (running == this) running = null;
        stopForeground(true);
        if (pipeline != null && pipeline.running() && (!foreground || !pipeline.hasListeners())) pipeline.stop();
        changed();
    }
    @Override public void onDestroy() { shutdown(); super.onDestroy(); }
    @Override public IBinder onBind(Intent intent) { return null; }
}
