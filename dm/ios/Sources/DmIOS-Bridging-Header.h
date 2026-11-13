// The C and Objective-C functions Launcher.swift and InGameMenu.swift call (CloudSaves.h, the in-game menu's view of the front end and host in ingame.h, save_sync.h's report
// before Play). project.yml points SWIFT_OBJC_BRIDGING_HEADER here.
#import "CloudSaves.h"
#import "ingame.h"
#include "save_sync.h"
#include <stdbool.h>

bool dm_take_play_link(void);   // front_ios.m: the app was opened by aethernx-<title ID>://play and the game has not started yet (taken once)
