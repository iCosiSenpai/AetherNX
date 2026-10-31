// Cloud saves on the iPhone (dm/host/save_sync.h): the iCloud Drive folder the player picked in the
// launcher's Cloud saves section (Launcher.swift), remembered across launches. The Mac app chooses the
// same folder in its settings window. The host brings the save in from there when the game starts and
// sends it there after each save.
//
// iOS does not let an app remember a path outside its sandbox. It lets it keep a bookmark: the document
// picker grants access to the folder, and the bookmark resolves to it again after a relaunch. The
// bookmark is bound to the app's signing identity, so a re-signed build cannot resolve it, and the
// launcher asks the player to pick the folder again.

#import <Foundation/Foundation.h>

/// The picked folder, or nil when there is none or it no longer resolves. `stale` (optional) is set
/// when a bookmark exists but cannot be used under this signature.
NSString *dm_cloud_saves_path(BOOL *stale);

/// Store a bookmark for the folder the player just picked. Returns NO when the system refuses to make one.
BOOL dm_store_cloud_saves(NSURL *url);

/// Forget it: cloud saves off.
void dm_clear_cloud_saves(void);

/// Puts the picked folder into DM_SAVE_SYNC before the game starts (front_ios.m, at Play), its
/// security scope held for the session; without a pick, the app's iCloud container (below) while
/// automatic iCloud is on. A DM_SAVE_SYNC from an env file or the launch environment wins. Turning
/// cloud saves off in the launcher clears the one this set.
void dm_cloud_saves_env(void);

/// Automatic iCloud: a build signed with an iCloud container (DM_ICLOUD_CONTAINER, the maintainer's
/// team) syncs through that container's Documents folder without a pick. iCloud Drive shows it as
/// "HorizonNative" (Info.plist NSUbiquitousContainers), holding <title ID>/save.dmsync as a picked
/// folder does, so the Mac app can choose iCloud Drive › HorizonNative. Resolved once at launch, off
/// the main thread (the system may take a while): main.m calls dm_cloud_container_resolve, and the
/// notification DMCloudContainerResolved follows on the main queue.
void dm_cloud_container_resolve(void);
/// The container's Documents folder, or nil: not signed with a container, no iCloud account, iCloud
/// Drive off for this app, or not resolved yet.
NSString *dm_cloud_container_path(void);
/// Whether automatic iCloud is on (the default); the launcher's Turn Off sets it off, Use iCloud on.
BOOL dm_cloud_auto(void);
void dm_cloud_set_auto(BOOL on);
