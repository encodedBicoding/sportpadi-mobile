# R8 keep rules for SportPadi release builds.
#
# Debug builds never run R8, so anything missing here shows up ONLY in a
# release/App Bundle install — as a crash on launch with a class name R8
# has renamed to two letters. Keep this list short and each entry explained.

# androidx.work (a dependency of the Google Mobile Ads SDK) opens its Room
# database by reflection: Room looks up "<DatabaseClass>_Impl" by name and
# calls its no-arg constructor. R8 in full mode sees no reference to that
# class and strips it, and WorkManager's ContentProvider then dies at
# startup with "Failed to create an instance of androidx.work.impl.WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.WorkDatabase { *; }

# Room's generated DAOs and the rest of WorkManager's internals are reached
# the same way; keeping the package is cheap (it's small) and closes the
# door on the next variant of the same crash.
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
