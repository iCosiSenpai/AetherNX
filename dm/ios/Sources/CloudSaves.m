// See CloudSaves.h.

#import "CloudSaves.h"

static NSString *const kCloudSaves = @"cloudSavesBookmark";

// The folder whose security scope this process holds (startAccessingSecurityScopedResource answered
// YES), from the first resolve on: the host writes there after every save. Each start is balanced: a
// different folder chosen before Play releases the one before it, and so does turning cloud saves off.
// Unbalanced starts each keep a kernel resource until the app exits, and enough of them stop access
// to any further scoped folder. The scope of the folder in use is kept until the process exits.
static NSURL *opened = nil;

static void hold_scope(NSURL *url) {
    if (opened && [opened.path isEqualToString:url.path]) return;
    if (opened) { [opened stopAccessingSecurityScopedResource]; opened = nil; }
    if ([url startAccessingSecurityScopedResource]) opened = url;
}

static void release_scope(void) {
    if (opened) { [opened stopAccessingSecurityScopedResource]; opened = nil; }
}

static NSData *fresh_bookmark(NSURL *url) {
    // The picker grants a security scope that lasts while it is held: the bookmark is written with
    // the scope on. One written without it reads back on this run and resolves to nothing from the
    // next launch on.
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *bookmark = [url bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
    if (scoped) [url stopAccessingSecurityScopedResource];
    return bookmark;
}

NSString *dm_cloud_saves_path(BOOL *stale) {
    if (stale) *stale = NO;
    NSData *bookmark = [NSUserDefaults.standardUserDefaults dataForKey:kCloudSaves];
    if (bookmark.length == 0) return nil;
    BOOL isStale = NO;
    NSError *error = nil;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&isStale error:&error];
    if (!url) {
        // A re-signed build gets a bookmark the system will not resolve for it. Keep the data, the
        // player may install the same signature again, and let the launcher ask for a new pick.
        fprintf(stderr, "boot: the picked cloud-save folder bookmark does not resolve (%s)\n", error.localizedDescription.UTF8String ?: "no reason given");
        if (stale) *stale = YES;
        return nil;
    }
    hold_scope(url);   // held for the session (see opened)
    if (isStale) {
        // The system still resolves it but asks for a rewrite. Same signature, so a fresh bookmark sticks.
        NSData *again = fresh_bookmark(url);
        if (again) [NSUserDefaults.standardUserDefaults setObject:again forKey:kCloudSaves];
        if (stale) *stale = YES;
    }
    return url.path;
}

BOOL dm_store_cloud_saves(NSURL *url) {
    NSData *bookmark = fresh_bookmark(url);
    NSError *error = nil;
    NSURL *back = nil;
    if (bookmark) back = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:nil error:&error];
    if (!bookmark || !back) {
        // A bookmark that cannot come back is not saved as if it were good.
        fprintf(stderr, "[RED] could not bookmark %s: %s\n", url.path.UTF8String ?: "?",
                error.localizedDescription.UTF8String ?: (bookmark ? "the bookmark does not resolve again" : "no bookmark data"));
        return NO;
    }
    [NSUserDefaults.standardUserDefaults setObject:bookmark forKey:kCloudSaves];
    fprintf(stderr, "launcher: cloud-save folder set to %s\n", url.path.UTF8String ?: "?");
    return YES;
}

void dm_clear_cloud_saves(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kCloudSaves];
    release_scope();
}

static NSString *const kCloudAutoOff = @"cloudSavesAutoOff";
#import <os/lock.h>
// The container's Documents folder, set from the resolving thread under g_clk; g_resolving is left when the resolution has finished either way, so Play (dm_cloud_saves_env)
// can wait for one still under way instead of starting a whole session without cloud saves
static NSString *g_container; static os_unfair_lock g_clk = OS_UNFAIR_LOCK_INIT; static dispatch_group_t g_resolving;
static NSString *container_get(void) { os_unfair_lock_lock(&g_clk); NSString *c = g_container; os_unfair_lock_unlock(&g_clk); return c; }

void dm_cloud_container_resolve(void) {
    if (g_resolving) return;
    g_resolving = dispatch_group_create(); dispatch_group_enter(g_resolving);
    dispatch_group_t group = g_resolving;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSFileManager *fm = [NSFileManager new];
            NSURL *root = fm.ubiquityIdentityToken ? [fm URLForUbiquityContainerIdentifier:nil] : nil;   // the first container the app is signed with; nil without one
            NSURL *docs = [root URLByAppendingPathComponent:@"Documents" isDirectory:YES]; NSError *e = nil;
            if (!fm.ubiquityIdentityToken) fprintf(stderr, "boot: no iCloud account, or iCloud Drive is off for this app: automatic cloud saves are off\n");
            else if (!root) fprintf(stderr, "boot: this build has no iCloud container (DM_ICLOUD_CONTAINER): cloud saves need a folder chosen in the launcher\n");
            else if (![fm createDirectoryAtURL:docs withIntermediateDirectories:YES attributes:nil error:&e])
                fprintf(stderr, "[RED] boot: the iCloud container's Documents folder cannot be made (%s)\n", e.localizedDescription.UTF8String ?: "?");
            else {
                NSString *path = docs.path;
                os_unfair_lock_lock(&g_clk); g_container = path; os_unfair_lock_unlock(&g_clk);
                fprintf(stderr, "boot: iCloud container %s\n", path.fileSystemRepresentation);
                dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:@"DMCloudContainerResolved" object:nil]; });
            }
        }
        dispatch_group_leave(group);
    });
}
NSString *dm_cloud_container_path(void) { return container_get(); }
BOOL dm_cloud_auto(void) { return ![NSUserDefaults.standardUserDefaults boolForKey:kCloudAutoOff]; }
void dm_cloud_set_auto(BOOL on) { [NSUserDefaults.standardUserDefaults setBool:!on forKey:kCloudAutoOff]; }

void dm_cloud_saves_env(void) {
    static BOOL fromPick;   // DM_SAVE_SYNC is the one this set, not an env file's
    if (getenv("DM_SAVE_SYNC") && !fromPick) return;
    BOOL stale = NO;
    NSString *folder = dm_cloud_saves_path(&stale);
    if (stale && !folder) fprintf(stderr, "boot: the cloud-save folder needs to be chosen again (the app is signed differently now); cloud saves are off\n");
    const char *how = "the picked folder";
    if (!folder.length && dm_cloud_auto()) {
        NSString *c = container_get();
        if (!c && g_resolving && dispatch_group_wait(g_resolving, dispatch_time(DISPATCH_TIME_NOW, 3 * (int64_t)NSEC_PER_SEC)) == 0) c = container_get();   // Play pressed while it is resolving
        else if (!c && g_resolving) fprintf(stderr, "boot: the iCloud container took more than 3 s to resolve; cloud saves are off for this start\n");
        if (c.length) { folder = c; how = "automatic iCloud"; }
    }
    if (folder.length) {
        setenv("DM_SAVE_SYNC", folder.fileSystemRepresentation, 1); fromPick = YES;
        fprintf(stderr, "boot: cloud saves through %s (%s)\n", folder.fileSystemRepresentation, how);
    } else if (fromPick) { unsetenv("DM_SAVE_SYNC"); fromPick = NO; }
}
