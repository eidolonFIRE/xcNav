# Room instantiates generated *_Impl databases by reflection. Room 2.5.0 (pulled in by Datadog via
# androidx.work 2.8.1) only keeps the class, not its constructor, so R8 full mode (AGP 9) strips it and
# WorkManager crashes at app startup with "Failed to create an instance of class ...WorkDatabase".
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
