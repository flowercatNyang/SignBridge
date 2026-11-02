package com.example.testsign;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.*;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import java.lang.ref.WeakReference;
import java.util.List;
import java.util.HashMap;
import java.util.Map;

/** Native camera presentation; inference survives view disposal in CameraPipeline. */
public final class HandCameraView implements PlatformView, Application.ActivityLifecycleCallbacks {
    public static final class Factory extends PlatformViewFactory {
        private final Activity activity;
        private final BinaryMessenger messenger;
        public Factory(Activity activity, BinaryMessenger messenger) { super(StandardMessageCodec.INSTANCE); this.activity = activity; this.messenger = messenger; }
        @Override public PlatformView create(Context context, int id, Object args) {
            return new HandCameraView(activity, new MethodChannel(messenger, "signbridge/predictions/" + id));
        }
    }
    private static WeakReference<HandCameraView> active = new WeakReference<>(null);
    public static boolean isCameraReady() {
        HandCameraView view = active.get();
        return view != null && !view.disposed && !view.paused && view.pipeline.ready();
    }
    public static void setCompact(boolean compact) {
        HandCameraView view = active.get();
        if (view == null || view.disposed) return;
        for (int i = 0; i < view.root.getChildCount(); i++) {
            View child = view.root.getChildAt(i);
            if (child != view.preview && child != view.translation) child.setVisibility(compact ? View.GONE : View.VISIBLE);
        }
        view.translation.setTextSize(compact ? 11 : 18);
        view.translation.setPadding(8, compact ? 2 : 12, 8, compact ? 2 : 12);
    }
    public static void permissionChanged() {
        HandCameraView view = active.get();
        if (view != null && !view.disposed) {
            if (view.activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) view.start();
            else view.status.setText("카메라 권한이 필요합니다. 권한 허용 후 다시 시도해 주세요.");
        }
    }
    private final Activity activity;
    private final MethodChannel predictions;
    private final LinearLayout root;
    private final FrameView preview;
    private final TextView status;
    private final TextView translation;
    private final CameraPipeline pipeline;
    private boolean disposed, paused;
    private String lastDisplay = "단어 — · 신뢰도 —";
    private final CameraPipeline.Listener listener = new CameraPipeline.Listener() {
        @Override public void frame(Bitmap frame, HandLandmarkerResult hands, boolean mirror,
                                    String display, boolean absent, double fps, boolean handledByService) {
            if (disposed) return;
            preview.frame = frame;
            preview.result = hands;
            preview.mirror = mirror;
            preview.invalidate();
            if (display != null) lastDisplay = display;
            if (absent) lastDisplay = "단어 — · 신뢰도 —";
            String metrics = lastDisplay + String.format(java.util.Locale.US, "  |  %.1f FPS", fps);
            if (!translation.getText().toString().equals(metrics)) translation.setText(metrics);
            String tracking = absent ? "손을 화면 안에 보여 주세요." : "손 " + hands.landmarks().size() + "개 추적 중";
            if (!status.getText().toString().equals(tracking)) status.setText(tracking);
            if (display != null || absent) {
                Map<String,Object> message = new HashMap<>();
                message.put("display", display);
                message.put("handsAbsent", absent);
                message.put("handledByService", handledByService);
                predictions.invokeMethod("prediction", message);
            }
        }
        @Override public void status(String message) {
            preview.frame = null;
            preview.result = null;
            preview.invalidate();
            translation.setText(message + "  |  0.0 FPS");
            status.setText(message);
        }
    };
    private HandCameraView(Activity activity, MethodChannel predictions) {
        this.activity = activity;
        this.predictions = predictions;
        active = new WeakReference<>(this);
        pipeline = CameraPipeline.get(activity);
        root = new LinearLayout(activity);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(18, 25, 42));
        translation = new TextView(activity);
        translation.setTextColor(Color.rgb(66, 235, 182));
        translation.setTextSize(18);
        translation.setMaxLines(2);
        translation.setEllipsize(android.text.TextUtils.TruncateAt.END);
        translation.setPadding(16, 12, 16, 12);
        translation.setText("수화 번역\n카메라를 준비하는 중…");
        translation.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        root.addView(translation);
        preview = new FrameView(activity);
        root.addView(preview, new LinearLayout.LayoutParams(-1, 0, 1));
        status = new TextView(activity);
        status.setTextColor(Color.WHITE);
        status.setPadding(16, 12, 16, 12);
        status.setText("카메라와 손 인식 모델을 준비합니다.");
        status.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        root.addView(status);
        LinearLayout buttons = new LinearLayout(activity);
        Button retry = new Button(activity);
        retry.setText("카메라 시작 / 재시도");
        retry.setOnClickListener(v -> start());
        buttons.addView(retry, new LinearLayout.LayoutParams(0, -2, 1));
        Button flip = new Button(activity);
        flip.setText("카메라 전환");
        flip.setOnClickListener(v -> { pipeline.flip(); });
        buttons.addView(flip, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(buttons);
        activity.getApplication().registerActivityLifecycleCallbacks(this);
        pipeline.attach(listener);
        new Handler(Looper.getMainLooper()).post(this::start);
        setCompact(((MainActivity) activity).keepCameraInPip());
    }

    private void start() {
        if (disposed || paused) return;
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(new String[]{Manifest.permission.CAMERA}, 4102);
            return;
        }
        pipeline.attach(listener);
        pipeline.start();
    }
    private void suspend() {
        paused = true;
        pipeline.detach(listener);
        preview.frame = null;
        preview.result = null;
        preview.invalidate();
        if (!RecognitionService.isEnabled() && !pipeline.hasListeners()) pipeline.stop();
    }
    @Override public View getView() { return root; }
    @Override public void dispose() {
        if (disposed) return;
        disposed = true;
        suspend();
        activity.getApplication().unregisterActivityLifecycleCallbacks(this);
        if (active.get() == this) active.clear();
    }
    @Override public void onActivityPaused(Activity a) {
        if (a == activity && !((MainActivity) activity).keepCameraInPip()) suspend();
    }
    @Override public void onActivityResumed(Activity a) {
        if (a != activity || disposed) return;
        paused = false;
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) start();
    }
    @Override public void onActivityDestroyed(Activity a) { if (a == activity) dispose(); }
    @Override public void onActivityCreated(Activity a, Bundle b) { }
    @Override public void onActivityStarted(Activity a) {
        if (a == activity && ((MainActivity) activity).keepCameraInPip()) { paused = false; start(); }
    }
    @Override public void onActivityStopped(Activity a) { if (a == activity && !disposed) suspend(); }
    @Override public void onActivitySaveInstanceState(Activity a, Bundle b) { }

    private static final class FrameView extends View {
        private Bitmap frame;
        private HandLandmarkerResult result;
        private boolean mirror;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        private static final int[][] EDGES = {{0,1},{1,2},{2,3},{3,4},{0,5},{5,6},{6,7},{7,8},{5,9},{9,10},{10,11},{11,12},{9,13},{13,14},{14,15},{15,16},{13,17},{0,17},{17,18},{18,19},{19,20}};
        FrameView(Context context) { super(context); setContentDescription("카메라 영상 및 손 관절점"); }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (frame == null) return;
            int save = canvas.save();
            if (mirror) canvas.scale(-1,1,getWidth()/2f,getHeight()/2f);
            float scale = Math.min((float)getWidth() / frame.getWidth(), (float)getHeight() / frame.getHeight());
            float w = frame.getWidth() * scale, h = frame.getHeight() * scale;
            float x = (getWidth() - w) / 2, y = (getHeight() - h) / 2;
            canvas.drawBitmap(frame, null, new RectF(x, y, x + w, y + h), paint);
            if (result == null) { canvas.restoreToCount(save); return; }
            paint.setStrokeWidth(3 * getResources().getDisplayMetrics().density);
            for (List<NormalizedLandmark> hand : result.landmarks()) {
                paint.setColor(Color.rgb(66, 235, 182));
                for (int[] edge : EDGES) {
                    NormalizedLandmark a = hand.get(edge[0]), b = hand.get(edge[1]);
                    canvas.drawLine(x + a.x()*w, y + a.y()*h, x + b.x()*w, y + b.y()*h, paint);
                }
                paint.setColor(Color.WHITE);
                for (NormalizedLandmark point : hand) canvas.drawCircle(x + point.x()*w, y + point.y()*h, 4 * getResources().getDisplayMetrics().density, paint);
            }
            canvas.restoreToCount(save);
        }
    }
}
