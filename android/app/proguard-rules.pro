# Librebus uses reflection for Gson model persistence. Keep model fields in
# release builds so cached data remains forward-compatible.
-keep class com.filiplopes.librebus.model.** { *; }
