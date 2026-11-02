// The in-game menu's view of the front end and the host (InGameMenu.swift calls these through the bridging header).
// Picture options: nvn_mtl.m (dm_present_*); touch controls: DmGamepad.m (dm_pad_*); the rest: front_ios.m (front_*). All are called on the main thread.
#pragma once

// The present (nvn_mtl.m): each change shows on the next frame
void dm_present_set_upscale(int metalfx);   // MetalFX where the picture is shown larger than the game renders it (1), or bilinear (0)
int dm_present_upscale(void);
int dm_present_upscale_supported(void);     // 0: this GPU has no Metal 4 MetalFX spatial scaler
void dm_present_set_sharpen(float amount);  // 0 (off) to 1
float dm_present_sharpen(void);
void dm_present_set_nearest(int on);        // sharp pixels (1) or smooth (0)
int dm_present_nearest(void);
void dm_present_set_stretch(int on);        // the picture over the whole screen (1) or the game's aspect ratio (0)
int dm_present_stretch(void);

// The touch controls (DmGamepad.m), kept per game in NSUserDefaults
int dm_pad_layout(void);                    // 0 = 2D, 1 = 3D, 2 = Tap
void dm_pad_set_layout(int layout);
int dm_pad_tap_allowed(void);               // Tap is offered only while the game is in handheld mode
float dm_pad_opacity(void);                 // 0.2 to 1
void dm_pad_set_opacity(float opacity);
float dm_pad_scale(void);                   // 0.7 to 1.3
void dm_pad_set_scale(float scale);
int dm_pad_haptics(void);
void dm_pad_set_haptics(int on);
int dm_pad_visible(void);                   // 0: only the menu button is drawn, every other touch goes to the game
void dm_pad_set_visible(int on);
void dm_pad_reset_layout(void);             // positions, size, opacity and visibility back to the defaults
int dm_pad_controller_in_use(void);         // a physical controller is connected (the touch controls are hidden meanwhile)

// Physical controllers (DmGamepad.m), also the launcher's list; controller is a GCController pointer, player is 0..7.
int dm_pad_buttons(void);
void dm_pad_set_buttons(int label);
float dm_pad_deadzone(void);
void dm_pad_set_deadzone(float amount);
int dm_pad_controller_player(const void *controller);
int dm_pad_controller_move(const void *controller, int player);   // swaps both input / motion / rumble routes, 0 if unavailable or merged

// The front end (front_ios.m)
int front_fps_counter(void);
void front_set_fps_counter(int on);
int front_metal_hud(void);
void front_set_metal_hud(int on);
void front_set_stretch(int on);             // dm_present_set_stretch, and the game's view follows (the whole screen or 16:9)
void front_ingame_edit(void);               // after the menu is dismissed: the layout editor, the game still paused until its Done
