package com.example.testsign;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.hardware.Camera;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult;
import java.io.ByteArrayOutputStream;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/** Application-owned camera; the foreground service retains it without a view. */
@SuppressWarnings("deprecation")
final class CameraPipeline {
    interface Listener {
        void frame(Bitmap frame, HandLandmarkerResult hands, boolean mirror, String display,
                   boolean handsAbsent, double fps, boolean handledByService);
        void status(String message);
    }
    private static CameraPipeline instance;
    static CameraPipeline get(Context context) {
        if (instance == null) instance = new CameraPipeline(context.getApplicationContext());
        return instance;
    }
    private final Context activity;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy = new AtomicBoolean();
    private final java.util.Set<Listener> listeners = new java.util.HashSet<>();
    private Camera camera;
    private SurfaceTexture texture;
    private HandLandmarker landmarker;
    private PoseLandmarker poseLandmarker;
    private SignTranslator translator;
    private boolean front = true, starting;
    private volatile int generation;
    private long lastFrame, fpsSince;
    private int completedFrames;
    private double fps;
    private String lastStatus = "카메라를 준비합니다.";
    private CameraPipeline(Context context) { activity = context; }
    void attach(Listener listener) { listeners.add(listener); listener.status(lastStatus); }
    void detach(Listener listener) { listeners.remove(listener); }
    boolean hasListeners() { return !listeners.isEmpty(); }
    boolean ready() { return camera != null; }
    boolean running() { return camera != null || starting; }
    void flip() { front = !front; stop(); start(); }
    private void status(String message) {
        lastStatus = message;
        for (Listener listener : new java.util.ArrayList<>(listeners)) listener.status(message);
    }
    void start() {
        if (camera != null || starting) return;
        if (activity.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            status("카메라 권한을 허용해 주세요.");
            return;
        }
        starting = true;
        int token = generation;
        status("손 인식 모델을 불러오는 중…");
        worker.execute(() -> {
            String loadingStage = "손 추적 모델";
            try {
                landmarker = HandLandmarker.createFromOptions(activity,
                    HandLandmarker.HandLandmarkerOptions.builder()
                        .setBaseOptions(BaseOptions.builder()
                            .setModelAssetPath("flutter_assets/assets/hand_landmarker.task").build())
                        .setRunningMode(RunningMode.VIDEO).setNumHands(2)
                        .setMinHandDetectionConfidence(0.5f)
                        .setMinHandPresenceConfidence(0.5f)
                        .setMinTrackingConfidence(0.5f).build());
                loadingStage = "자세 추적 모델";
                poseLandmarker = PoseLandmarker.createFromOptions(activity,
                    PoseLandmarker.PoseLandmarkerOptions.builder()
                        .setBaseOptions(BaseOptions.builder()
                            .setModelAssetPath("flutter_assets/assets/pose_landmarker_lite.task").build())
                        .setRunningMode(RunningMode.VIDEO).setNumPoses(1)
                        .setMinPoseDetectionConfidence(0.5f)
                        .setMinPosePresenceConfidence(0.5f)
                        .setMinTrackingConfidence(0.5f).build());
                loadingStage = "기본 수어 모델 (GRU)";
                translator = new SignTranslator(activity.getAssets());
                main.post(() -> {
                    if (valid(token)) {
                        status("수어 모델 로딩 완료\n동작을 보여 주세요.");
                        openCamera(token);
                    }
                });
            } catch (Exception | LinkageError e) {
                fail(token, loadingStage + " 로딩 실패. 다시 시도해 주세요.", e);
            }
        });
    }

    private boolean valid(int token) { return token == generation; }

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
                int display = ((android.view.WindowManager) activity.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRotation() * 90;
                final int rotation = mirror ? (sensorOrientation + display) % 360 : (sensorOrientation - display + 360) % 360;
                worker.execute(() -> process(frame, width, height, rotation, mirror, token, now));
            });
            camera.startPreview();
            starting = false;
            fpsSince = SystemClock.uptimeMillis();
            status("손을 카메라에 보여 주세요.");
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
            boolean handsAbsent;
            try {
                result = landmarker.detectForVideo(image, timestamp);
                PoseLandmarkerResult pose = poseLandmarker.detectForVideo(image, timestamp);
                handsAbsent = result.landmarks().isEmpty();
                if (handsAbsent || pose.landmarks().isEmpty()) {
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
                        coordinates(pose.landmarks().get(0)),frame.getWidth(),frame.getHeight()),timestamp,right!=null,left!=null);
                }
            }
            finally { image.close(); }
            main.post(() -> {
                if (!valid(token)) { frame.recycle(); return; }
                long finished = SystemClock.uptimeMillis();
                completedFrames++;
                if (finished - fpsSince >= 1000) {
                    fps = completedFrames * 1000.0 / (finished - fpsSince);
                    completedFrames = 0;
                    fpsSince = finished;
                }
                boolean handledByService = RecognitionService.handlesPredictions();
                RecognitionService.prediction(translated, handsAbsent, finished);
                if (listeners.isEmpty()) frame.recycle();
                else for (Listener listener : new java.util.ArrayList<>(listeners)) {
                    listener.frame(frame, result, mirror, translated, handsAbsent, fps, handledByService);
                }
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

    private void fail(int token, String message, Throwable error) {
        android.util.Log.e("HandCamera", message, error);
        String detail = error.getClass().getSimpleName() + ": " + String.valueOf(error.getMessage());
        main.post(() -> { if (valid(token)) { stop(); status(message + "\n" + detail); RecognitionService.cameraFailed(message); } });
    }

    void stop() {
        generation++;
        starting = false;
        lastFrame = 0;
        completedFrames = 0;
        fps = 0;
        if (camera != null) {
            try {
                camera.setPreviewCallback(null);
                camera.stopPreview();
            } catch (RuntimeException error) {
                android.util.Log.w("HandCamera", "Camera already disconnected", error);
            } finally {
                camera.release();
                camera = null;
            }
        }
        if (texture != null) { texture.release(); texture = null; }
        status("수화 번역\n카메라 시작 후 동작을 보여 주세요");
        worker.execute(() -> {
            if (landmarker != null) { landmarker.close(); landmarker = null; }
            if (poseLandmarker != null) { poseLandmarker.close(); poseLandmarker = null; }
            if (translator != null) {
                try { translator.close(); } catch (Exception e) { android.util.Log.e("HandCamera", "Close translator", e); }
                translator = null;
            }
        });
    }

}
