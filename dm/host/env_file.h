// Which lines of a player's env.txt the apps take: Documents/env.txt on the iPhone and iPad (dm/ios/Sources/main.m), <Application Support>/HorizonNative/<title ID>/env.txt
// on the Mac (dm/mac/launcher.c). That file can come from anyone (a fix shared on a forum, a copied setup), so:
// - it sets only HorizonNative's own switches (DM_*) and Metal's (MTL_*): never the dynamic loader's (DYLD_INSERT_LIBRARIES would load a library into the Mac host) or
//   another process setting;
// - it never moves the app's own folders (the game files, saves, temporary storage, DLC, shader libraries, fonts, pipeline archive: the app sets them): DM_TEMP=save made the
//   game's clean of its temporary storage empty the saves;
// - its values name no path out of the folder the app runs in: a value with '/' or one of "." and ".." is refused, so the files a diagnostic switch writes (DM_FSLOG,
//   DM_WATCH_SAMPLE ...) stay there. The one exception is DM_SAVE_SYNC, the cloud saves folder (docs/frontends.md), whose files are written with exclusive staging (save_sync.c).
// The env.txt packed in the app (the NSP script's --env-file) is part of the signed build and is not filtered; nor is the launch environment (Xcode, devicectl, a shell).
#pragma once
#include <string.h>

static inline int dm_env_file_ok(const char *key, const char *value) {
    static const char *const layout[] = {"DM_ROOT", "DM_ROMFS", "DM_ROMFS_OVERLAY", "DM_SAVE", "DM_TEMP", "DM_AOC_DIR", "DM_MSL_DIR", "DM_FONT_DIR", "DM_NVN_SHMAP",
                                         "DM_PSO_BUNDLE", "DM_PSO_USER", "DM_SHARED_FONT", "DM_SHARED_FONT_EXT"};
    if (!key || !value) return 0;
    if (strncmp(key, "DM_", 3) && strncmp(key, "MTL_", 4)) return 0;
    for (const char *k = key; *k; k++) if (!((*k >= 'A' && *k <= 'Z') || (*k >= '0' && *k <= '9') || *k == '_')) return 0;
    for (unsigned i = 0; i < sizeof layout / sizeof *layout; i++) if (!strcmp(key, layout[i])) return 0;
    if (!strcmp(key, "DM_SAVE_SYNC")) return 1;
    if (strchr(value, '/') || !strcmp(value, ".") || !strcmp(value, "..")) return 0;
    return 1;
}
