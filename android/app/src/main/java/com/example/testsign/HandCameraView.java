package com.example.testsign;

import android.Manifest;
import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.hardware.Camera;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.View;
import android.widget.*;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import java.io.ByteArrayOutputStream;
import java.lang.ref.WeakReference;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Native, bounded-frame camera pipeline; inference never runs on the UI thread. */
@SuppressWarnings("deprecation")
public final class HandCameraView implements PlatformView, Application.ActivityLifecycleCallbacks {
    public static final class Factory extends PlatformViewFactory {
        private final Activity activity;
        public Factory(Activity activity) { super(StandardMessageCodec.INSTANCE); this.activity = activity; }
        @Override public PlatformView create(Context context, int id, Object args) {
            return new HandCameraView(activity);
        }
    }
    private static WeakReference<HandCameraView> active = new WeakReference<>(null);
    public static void permissionChanged() {
        HandCameraView view = active.get();
        if (view != null && !view.disposed) {
            if (view.activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) view.start();
            else view.status.setText("카메라 권한이 필요합니다. 권한 허용 후 다시 시도해 주세요.");
        }
    }
    private final Activity activity;
    private final LinearLayout root;
    private final FrameView preview;
    private final TextView status;
    private final TextView translation;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy = new AtomicBoolean();
    private Camera camera;
    private SurfaceTexture texture;
    // Only touched on worker, including close; queued cleanup follows pending inference.
    private HandLandmarker landmarker;
    private PoseLandmarker poseLandmarker;
    private SignTranslator translator;
    private boolean front = true;
    private boolean disposed;
    private boolean paused;
    private int generation;
    private long lastFrame;

    private HandCameraView(Activity activity) {
        this.activity = activity;
        active = new WeakReference<>(this);
        root = new LinearLayout(activity);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(18, 25, 42));
        translation = new TextView(activity);
        translation.setTextColor(Color.rgb(66, 235, 182));
        translation.setTextSize(18);
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
        flip.setOnClickListener(v -> { front = !front; start(); });
        buttons.addView(flip, new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(buttons);
        activity.getApplication().registerActivityLifecycleCallbacks(this);
        main.post(this::start);
    }

    private void start() {
        if (disposed || paused) return;
        stop();
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            status.setText("카메라 권한을 허용해 주세요.");
            activity.requestPermissions(new String[]{Manifest.permission.CAMERA}, 4102);
            return;
        }
        int token = generation;
        status.setText("손 인식 모델을 불러오는 중…");
        worker.execute(() -> {
            try {
                landmarker = HandLandmarker.createFromOptions(activity,
                    HandLandmarker.HandLandmarkerOptions.builder()
                        .setBaseOptions(BaseOptions.builder()
                            .setModelAssetPath("flutter_assets/assets/hand_landmarker.task").build())
                        .setRunningMode(RunningMode.VIDEO).setNumHands(2)
                        .setMinHandDetectionConfidence(0.5f)
                        .setMinHandPresenceConfidence(0.5f)
                        .setMinTrackingConfidence(0.5f).build());
                poseLandmarker = PoseLandmarker.createFromOptions(activity,
                    PoseLandmarker.PoseLandmarkerOptions.builder()
                        .setBaseOptions(BaseOptions.builder()
                            .setModelAssetPath("flutter_assets/assets/pose_landmarker_lite.task").build())
                        .setRunningMode(RunningMode.VIDEO).setNumPoses(1)
                        .setMinPoseDetectionConfidence(0.5f)
                        .setMinPosePresenceConfidence(0.5f)
                        .setMinTrackingConfidence(0.5f).build());
                translator = new SignTranslator(activity.getAssets());
                main.post(() -> { if (valid(token)) openCamera(token); });
            } catch (Exception e) { fail(token, "손·자세·수화 모델을 불러오지 못했습니다. 다시 시도해 주세요.", e); }
        });
    }

    private boolean valid(int token) { return !disposed && !paused && token == generation; }

    private void openCamera(int token) {
        try {
            int selected = -1;
            Camera.CameraInfo info = new Camera.CameraInfo();
            for (int id = 0; id < Camera.getNumberOfCameras(); id++) {
                Camera.getCameraInfo(id, info);
                if (info.facing == (front ? Camera.CameraInfo.CAMERA_FACING_FRONT : Camera.CameraInfo.CAMERA_FACING_BACK)) { selected = id; break; }
            }
            if (selected < 0) throw new IllegalStateException("Requested camera unavailable");
            Camera.getCameraInfo(selected, info);
            final boolean mirror = info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT;
            final int sensorOrientation = info.orientation;
            camera = Camera.open(selected);
            camera.setErrorCallback((code, source) -> fail(token,
                "카메라 연결이 종료되었습니다. 다시 시도해 주세요.",
                new IllegalStateException("Camera error " + code)));
            Camera.Parameters parameters = camera.getParameters();
            Camera.Size size = parameters.getSupportedPreviewSizes().get(0);
            for (Camera.Size candidate : parameters.getSupportedPreviewSizes()) {
                if (Math.abs(candidate.width * candidate.height - 640 * 480) < Math.abs(size.width * size.height - 640 * 480)) size = candidate;
            }
            final int width = size.width, height = size.height;
            parameters.setPreviewSize(width, height);
            parameters.setPreviewFormat(ImageFormat.NV21);
            List<String> focus = parameters.getSupportedFocusModes();
            if (focus != null && focus.contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO)) parameters.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
            camera.setParameters(parameters);
            texture = new SurfaceTexture(0);
            camera.setPreviewTexture(texture);
            camera.setPreviewCallback((bytes, source) -> {
                long now = SystemClock.uptimeMillis();
                if (!valid(token) || now - lastFrame < 66 || !busy.compareAndSet(false, true)) return;
                lastFrame = now;
                byte[] frame = bytes.clone();
                int display = activity.getWindowManager().getDefaultDisplay().getRotation() * 90;
                final int rotation = mirror ? (sensorOrientation + display) % 360 : (sensorOrientation - display + 360) % 360;
                worker.execute(() -> process(frame, width, height, rotation, mirror, token, now));
            });
            camera.startPreview();
            status.setText("손을 카메라에 보여 주세요.");
        } catch (Exception e) { fail(token, "카메라를 열 수 없습니다. 권한과 다른 앱의 카메라 사용을 확인해 주세요.", e); }
    }

    private void process(byte[] bytes, int width, int height, int rotation, boolean mirror, int token, long timestamp) {
        try {
            // Infer on the unmirrored image, matching the supplied Python pipeline.
            ByteArrayOutputStream jpeg = new ByteArrayOutputStream();
            new YuvImage(bytes, ImageFormat.NV21, width, height, null)
                .compressToJpeg(new Rect(0, 0, width, height), 85, jpeg);
            byte[] encoded = jpeg.toByteArray();
            Bitmap raw = BitmapFactory.decodeByteArray(encoded, 0, encoded.length);
            Matrix transform = new Matrix();
            transform.postRotate(rotation);
            Bitmap frame = Bitmap.createBitmap(raw, 0, 0, width, height, transform, true);
            if (frame != raw) raw.recycle();
            // MPImage.close() recycles its bitmap. Keep the displayed frame independently owned.
            MPImage image = new BitmapImageBuilder(frame.copy(Bitmap.Config.ARGB_8888, false)).build();
            HandLandmarkerResult result;
            String translated;
            try {
                result = landmarker.detectForVideo(image, timestamp);
                PoseLandmarkerResult pose = poseLandmarker.detectForVideo(image, timestamp);
                if (result.landmarks().isEmpty() || pose.landmarks().isEmpty()) {
                    translator.missing(timestamp);
                    translated = "양손과 어깨가 보이도록 동작해 주세요";
                } else {
                    float[][] right = null, left = null;
                    for (int i=0;i<result.landmarks().size();i++) {
                        String side = result.handedness().get(i).get(0).categoryName();
                        if ("Right".equals(side)) right = coordinates(result.landmarks().get(i));
                        if ("Left".equals(side)) left = coordinates(result.landmarks().get(i));
                    }
                    translated = translator.add(SignFeatures.extract(right,left,
                        coordinates(pose.landmarks().get(0)),frame.getWidth(),frame.getHeight()),timestamp);
                }
            }
            finally { image.close(); }
            main.post(() -> {
                if (!valid(token)) { frame.recycle(); return; }
                preview.frame = frame;
                preview.result = result;
                preview.mirror = mirror;
                preview.invalidate();
                if (translated != null) {
                    String content = "수화 번역\n" + translated;
                    if (!translation.getText().toString().equals(content)) translation.setText(content);
                }
                int count = result.landmarks().size();
                String text = count == 0 ? "손을 찾는 중 · 손을 화면 안에 보여 주세요." : "손 " + count + "개 감지 · 손마다 관절점 21개 추적 중";
                if (!status.getText().toString().equals(text)) status.setText(text);
            });
        } catch (Exception e) { fail(token, "손 인식 중 오류가 발생했습니다. 다시 시도해 주세요.", e); }
        finally { busy.set(false); }
    }

    private static float[][] coordinates(List<NormalizedLandmark> points) {
        float[][] values = new float[points.size()][3];
        for (int i=0;i<points.size();i++) {
            NormalizedLandmark p=points.get(i);
            values[i]=new float[]{p.x(),p.y(),p.z()};
        }
        return values;
    }

    private void fail(int token, String message, Exception error) {
        android.util.Log.e("HandCamera", message, error);
        main.post(() -> { if (valid(token)) { stop(); status.setText(message); } });
    }

    private void stop() {
        generation++;
        if (camera != null) {
            camera.setPreviewCallback(null);
            camera.stopPreview();
            camera.release();
            camera = null;
        }
        if (texture != null) { texture.release(); texture = null; }
        preview.frame = null;
        preview.result = null;
        preview.invalidate();
        translation.setText("수화 번역\n카메라 시작 후 동작을 보여 주세요");
        worker.execute(() -> {
            if (landmarker != null) { landmarker.close(); landmarker = null; }
            if (poseLandmarker != null) { poseLandmarker.close(); poseLandmarker = null; }
            if (translator != null) {
                try { translator.close(); } catch (Exception e) { android.util.Log.e("HandCamera", "Close translator", e); }
                translator = null;
            }
        });
    }

    @Override public View getView() { return root; }
    @Override public void dispose() {
        if (disposed) return;
        disposed = true;
        stop();
        worker.shutdown();
        activity.getApplication().unregisterActivityLifecycleCallbacks(this);
        if (active.get() == this) active.clear();
    }
    @Override public void onActivityPaused(Activity a) { if (a == activity) { paused = true; stop(); status.setText("카메라 일시 중지"); } }
    @Override public void onActivityResumed(Activity a) {
        if (a != activity || disposed) return;
        paused = false;
        // Returning from a denied permission dialog must not immediately request it again.
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) start();
        else status.setText("카메라 권한을 허용한 뒤 시작 버튼을 눌러 주세요.");
    }
    @Override public void onActivityDestroyed(Activity a) { if (a == activity) dispose(); }
    @Override public void onActivityCreated(Activity a, Bundle b) { }
    @Override public void onActivityStarted(Activity a) { }
    @Override public void onActivityStopped(Activity a) { }
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
