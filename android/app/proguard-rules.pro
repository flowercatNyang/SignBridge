# Required by ONNX Runtime's Android R8 integration:
# https://onnxruntime.ai/docs/build/android.html
-keep class ai.onnxruntime.** { *; }

# MediaPipe uses protobuf-lite messages with field names stored in schema strings.
# R8 must preserve generated message fields (including platform_) for reflection.
# https://github.com/protocolbuffers/protobuf/blob/main/java/lite.md
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
