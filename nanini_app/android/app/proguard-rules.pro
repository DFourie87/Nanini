# Google ML Kit text recognition (the capture app's timesheet reading) uses
# only the Latin recognizer; the plugin also refers to the Chinese,
# Devanagari, Japanese and Korean ones, which aren't included.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep ML Kit whole. The release build's shrinker (R8) otherwise strips what
# ML Kit reaches only by reflection (its protobuf messages, the barcode
# reader), and reading a timesheet or fridge sheet photo fails on the phone:
# "Attempt to invoke virtual method 'java.lang.Class java.lang.Object.getClass()'
# on a null object reference".
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_barcode_scanning.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }
-dontwarn com.google.protobuf.**
