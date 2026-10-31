"""Saved diagnostics are filtered only for the opt-in player IPA; a player's env.txt sets only what dm/host/env_file.h allows, in every build."""
import pathlib
import subprocess
import tempfile
import unittest


class PlayerEnvironment(unittest.TestCase):
    def test_overlays_and_player_options_survive(self):
        header = pathlib.Path(__file__).resolve().parents[2] / 'ios/Sources/player_env.h'
        source = r'''
#include <assert.h>
#include "player_env.h"
int main(void) {
 const char *drop[]={"DM_NVN_CPUPROF","DM_NVN_TSV","DM_NVN_PASSDUMP_ALL",
   "DM_NVN_GEOMETRY_PACK","DM_NVN_SHMAP","DM_NVN_ZBLOCK","DM_NVN_ENC_THREAD_PROBE","DM_CTL",
   "DM_TEST_UP_LOST","MTL_DEBUG_LAYER","MTL_SHADER_VALIDATION","DM_MSL_DIR"};
 const char *keep[]={"DM_SHOW_FPS","DM_METAL_HUD","MTL_HUD_ENABLED",
   "DM_FPS_TARGET","DM_DYNAMIC_RESOLUTION","DM_OPMODE","DM_RENDER_SCALE","DM_LANG","DM_RT",
   "DM_TOUCH_HAPTICS","DM_RUMBLE","DM_SAVE","DM_ROMFS","DM_NVN_ENC_THREAD"};
 for(unsigned i=0;i<sizeof drop/sizeof *drop;i++)assert(dm_player_diagnostic_key(drop[i]));
 for(unsigned i=0;i<sizeof keep/sizeof *keep;i++)assert(!dm_player_diagnostic_key(keep[i]));
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            c = pathlib.Path(tmp) / 'test.c'
            exe = pathlib.Path(tmp) / 'test'
            c.write_text(source)
            subprocess.run(['cc', '-Wall', '-Werror', '-I', str(header.parent), str(c), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


class PlayerEnvFile(unittest.TestCase):
    def test_only_safe_settings_are_taken(self):
        header = pathlib.Path(__file__).resolve().parents[2] / 'host/env_file.h'
        source = r'''
#include <assert.h>
#include "env_file.h"
int main(void) {
 assert(dm_env_file_ok("DM_FPS_TARGET","30") && dm_env_file_ok("MTL_HUD_ENABLED","1") && dm_env_file_ok("DM_FSLOG","fs.log") && dm_env_file_ok("DM_LANG",""));
 assert(dm_env_file_ok("DM_SAVE_SYNC","/Users/x/Library/Mobile Documents/HorizonNative") && dm_env_file_ok("DM_SAVE_SYNC","icloud"));
 const char *bad_keys[]={"DYLD_INSERT_LIBRARIES","DYLD_LIBRARY_PATH","PATH","HOME","dm_lower","DM_A B","DM_TEMP","DM_SAVE","DM_ROMFS","DM_AOC_DIR","DM_MSL_DIR","DM_ROOT","DM_PSO_BUNDLE"};
 for(unsigned i=0;i<sizeof bad_keys/sizeof *bad_keys;i++)assert(!dm_env_file_ok(bad_keys[i],"x"));
 const char *bad_values[]={"/Users/x/Documents/thesis.docx","save/0/data","../Library/x",".","..","a/b"};
 for(unsigned i=0;i<sizeof bad_values/sizeof *bad_values;i++)assert(!dm_env_file_ok("DM_FSLOG",bad_values[i]));
 assert(!dm_env_file_ok(0,"x") && !dm_env_file_ok("DM_X",0));
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            c = pathlib.Path(tmp) / 'test.c'; exe = pathlib.Path(tmp) / 'test'
            c.write_text(source)
            subprocess.run(['cc', '-Wall', '-Werror', '-I', str(header.parent), str(c), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)

    def test_both_apps_filter_the_players_file(self):
        repo = pathlib.Path(__file__).resolve().parents[3]
        mac = (repo / 'dm/mac/launcher.c').read_text(); ios = (repo / 'dm/ios/Sources/main.m').read_text()
        self.assertIn('if (player && !dm_env_file_ok(k, eq + 1))', mac); self.assertIn('env_file(p, 1);   // the player', mac)
        self.assertIn('ef == player_env && !dm_env_file_ok(k.UTF8String, v.UTF8String)', ios)
