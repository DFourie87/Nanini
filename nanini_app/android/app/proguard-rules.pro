# Google ML Kit text recognition (the capture app's timesheet reading) uses
# only the Latin recognizer; the plugin also refers to the Chinese,
# Devanagari, Japanese and Korean ones, which aren't included.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
