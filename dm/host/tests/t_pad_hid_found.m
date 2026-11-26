// Raw HID gamepads beside GameController's (pad_hid_mac.h, source issue 637), with fake IOKit entries and fake GameController controllers as t_pad_hid_mac.m has them:
// which devices hidpad_found reads, which it leaves to GameController and which it makes wait, so that no controller is read twice (docs/reference/services.md,
// "A controller GameController does not list gets no input"). A button goes through the value callback a read device registered, so a device that is not read delivers nothing.
// The front end's side is recorded, not run: hidpad_attach / hidpad_detach / hidpad_read here only count, so the player slots (front_mac.m: a raw HID pad is a player from its
// first button press) are not covered. Neither are that entry's two open cases, in which one controller holds two player slots: they are run and printed as a note, not checked.
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <GameController/GameController.h>
#import <GameController/GCSyntheticDeviceKeys.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "../dm_input.h"

@interface TestEl : NSObject
@property uint32_t page, usage; @property long max;
@end
@implementation TestEl
@end
@interface TestVal : NSObject
@property TestEl *el; @property long value;
@end
@implementation TestVal
@end
@interface TestDev : NSObject
@property NSString *name; @property int vid, pid, hint, synthetic; @property long loc; @property uint64_t entry; @property NSArray<TestEl *> *els;
@property IOHIDValueCallback valueCallback; @property void *valueContext;   // the callback it registered: set while it is read
@property int attached, detached, reads; @property uint64_t buttons;        // what the front end was told of it
@end
@implementation TestDev
@end
@interface TestGC : NSObject
@property NSString *productCategory, *vendorName; @property id extendedGamepad;
@end
@implementation TestGC
static NSMutableArray<TestGC *> *g_gc;
+ (NSArray *)controllers { return g_gc; }
+ (BOOL)supportsHIDDevice:(IOHIDDeviceRef)d { return ((__bridge TestDev *)d).hint != 0; }
@end

static CFTypeRef test_property(IOHIDDeviceRef device, CFStringRef key) {
    TestDev *d = (__bridge id)device;
    if (CFEqual(key, CFSTR(kIOHIDProductKey))) return (__bridge CFTypeRef)d.name;
    if (CFEqual(key, CFSTR(kIOHIDVendorIDKey))) return (__bridge CFTypeRef)@(d.vid);
    if (CFEqual(key, CFSTR(kIOHIDProductIDKey))) return (__bridge CFTypeRef)@(d.pid);
    if (CFEqual(key, CFSTR(kIOHIDLocationIDKey))) return (__bridge CFTypeRef)@(d.loc);
    if (CFEqual(key, CFSTR(kIOHIDTransportKey))) return (__bridge CFTypeRef)@"Bluetooth";
    if (CFEqual(key, CFSTR(kIOHIDGCSyntheticDeviceKey))) return d.synthetic ? kCFBooleanTrue : NULL;
    return NULL;
}
static void test_report_cb(IOHIDDeviceRef device, uint8_t *buffer, CFIndex len, IOHIDReportCallback callback, void *ctx) { (void)device; (void)buffer; (void)len; (void)callback; (void)ctx; }
static void test_value_cb(IOHIDDeviceRef device, IOHIDValueCallback callback, void *ctx) { TestDev *d = (__bridge id)device; d.valueCallback = callback; d.valueContext = ctx; }
static CFArrayRef test_elements(IOHIDDeviceRef device, CFDictionaryRef match, IOOptionBits o) { (void)match; (void)o; return CFBridgingRetain(((__bridge TestDev *)device).els ?: @[]); }
static io_service_t test_service(IOHIDDeviceRef device) { return (io_service_t)((__bridge TestDev *)device).entry; }
static kern_return_t test_entry_id(io_registry_entry_t e, uint64_t *id) { *id = e; return KERN_SUCCESS; }
static IOReturn test_set_report(IOHIDDeviceRef d, IOHIDReportType t, CFIndex id, const uint8_t *r, CFIndex n) { (void)d; (void)t; (void)id; (void)r; (void)n; return kIOReturnSuccess; }
static IOHIDElementRef test_value_element(IOHIDValueRef v) { return (__bridge IOHIDElementRef)((__bridge TestVal *)v).el; }
static CFIndex test_value_integer(IOHIDValueRef v) { return ((__bridge TestVal *)v).value; }
static uint32_t test_element_page(IOHIDElementRef e) { return ((__bridge TestEl *)e).page; }
static uint32_t test_element_usage(IOHIDElementRef e) { return ((__bridge TestEl *)e).usage; }
static CFIndex test_element_min(IOHIDElementRef e) { (void)e; return 0; }
static CFIndex test_element_max(IOHIDElementRef e) { return ((__bridge TestEl *)e).max; }

static char g_log[16384];   // every line the header logs, to find the ones a case expects
__attribute__((format(printf, 1, 2))) static void test_log(const char *fmt, ...) {
    char line[512]; va_list ap; va_start(ap, fmt); vsnprintf(line, sizeof line, fmt, ap); va_end(ap);
    printf("    log: %s\n", line);
    size_t n = strlen(g_log); snprintf(g_log + n, sizeof g_log - n, "%s\n", line);
}
static int logged(const char *text) { return strstr(g_log, text) != NULL; }

uint64_t now_ns(void) { return 1000000000; }
#define LOG(...) test_log(__VA_ARGS__)
#define IOHIDDeviceGetProperty test_property
#define IOHIDDeviceRegisterInputReportCallback test_report_cb
#define IOHIDDeviceRegisterInputValueCallback test_value_cb
#define IOHIDDeviceCopyMatchingElements test_elements
#define IOHIDDeviceGetService test_service
#define IORegistryEntryGetRegistryEntryID test_entry_id
#define IOHIDDeviceSetReport test_set_report
#define IOHIDValueGetElement test_value_element
#define IOHIDValueGetIntegerValue test_value_integer
#define IOHIDElementGetUsagePage test_element_page
#define IOHIDElementGetUsage test_element_usage
#define IOHIDElementGetLogicalMin test_element_min
#define IOHIDElementGetLogicalMax test_element_max
#define GCController TestGC
#include "../pad_hid_mac.h"

// The front end's side (front_mac.m defines these with its player slots): only what it is told is kept
static void hidpad_attach(hid_pad *d) { ((__bridge TestDev *)d->hid).attached++; }
static void hidpad_detach(hid_pad *d) { ((__bridge TestDev *)d->hid).detached++; }
static void hidpad_read(hid_pad *d) { TestDev *t = (__bridge TestDev *)d->hid; t.reads++; t.buttons = pad_hid_buttons(&d->st); }
static void hidpad_motion(hid_pad *d, const pro_motion_sample *s, int n) { (void)d; (void)s; (void)n; }
static void hidpad_models_changed(void) { hidpad_twins_eval(nil); hidpad_twins_release(); hidpad_twins_take(nil); }   // front_mac.m's pads_changed, without its slots

static int checks, fails, told;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); } } while (0)
static void done(const char *what) { printf("%s %s\n", fails == told ? "ok  " : "FAIL", what); told = fails; }

static IOHIDDeviceRef ref(TestDev *d) { return (__bridge IOHIDDeviceRef)d; }
static TestEl *element(uint32_t page, uint32_t usage, long max) { TestEl *e = [TestEl new]; e.page = page; e.usage = usage; e.max = max; return e; }
static TestDev *dev(NSString *name, int vid, int pid, int hint, uint64_t entry) {
    TestDev *d = [TestDev new]; d.name = name; d.vid = vid; d.pid = pid; d.hint = hint; d.entry = entry; d.loc = (long)entry << 20;
    d.els = @[element(kHIDPage_GenericDesktop, kHIDUsage_GD_X, 255), element(kHIDPage_GenericDesktop, kHIDUsage_GD_Y, 255)];
    return d;
}
static TestGC *listed(NSString *vendorName) { TestGC *c = [TestGC new]; c.vendorName = vendorName; c.productCategory = @"MFi"; c.extendedGamepad = @1; [g_gc addObject:c]; return c; }
static void found(TestDev *d) { hidpad_found(NULL, kIOReturnSuccess, NULL, ref(d)); }
static void removed(TestDev *d) { hidpad_removed(NULL, kIOReturnSuccess, NULL, ref(d)); }
static hid_pad *in(hid_pad *list, TestDev *t) { for (hid_pad *d = list; d; d = d->next) if (d->hid == ref(t)) return d; return NULL; }
static int count(const hid_pad *list) { int n = 0; for (; list; list = list->next) n++; return n; }
// A button element's value, as IOKit hands it to the callback the device registered; a device that registered none (not read) delivers nothing
static void button(TestDev *t, uint32_t usage, long down) {
    if (!t.valueCallback) return;
    TestVal *v = [TestVal new]; v.el = element(kHIDPage_Button, usage, 1); v.value = down;
    t.valueCallback(t.valueContext, kIOReturnSuccess, NULL, (__bridge IOHIDValueRef)v);
}
static void spin(double s) {   // the main queue's blocks, the wait's among them
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + s;
    while (CFAbsoluteTimeGetCurrent() < end) if (CFRunLoopRunInMode(kCFRunLoopDefaultMode, end - CFAbsoluteTimeGetCurrent(), false) == kCFRunLoopRunFinished) usleep(2000);
}

int main(void) { @autoreleasepool {
    g_gc = [NSMutableArray new];
    setvbuf(stdout, NULL, _IONBF, 0);

    // A pad GameController does not know (the hint says NO) is read at once, and its buttons reach the front end
    TestDev *gen = dev(@"USB Gamepad", 0x0079, 0x0006, 0, 31); found(gen);
    hid_pad *g = in(g_hidpads, gen);
    CHECK(g && gen.attached == 1 && gen.valueCallback && !g_hidpads_waiting && !g_hidpads_gc);
    CHECK(g && g->st.has[PH_X] && g->st.has[PH_Y] && !g->st.has[PH_Z]);        // the axes its elements declare
    CHECK(logged("controller 'USB Gamepad' (HID, 0079:0006): buttons use 8BitDo's numbering"));
    CHECK(gen.reads == 0);                                                      // nothing pressed yet: the front end has no button to make it a player with
    button(gen, 2, 1); CHECK(gen.reads == 1 && gen.buttons == DM_BTN_A);        // usage 2 is A in the default map
    button(gen, 2, 0); CHECK(gen.reads == 2 && gen.buttons == 0);
    done("a pad the hint says NO for is read at once; its first press reaches the front end");

    // IOHIDManager hands one device over once per matching dictionary, each time as a new reference to the same registry entry: it stays one pad
    TestDev *again = dev(@"USB Gamepad", 0x0079, 0x0006, 0, 31); found(again);
    CHECK(count(g_hidpads) == 1 && !in(g_hidpads, again) && again.attached == 0 && !again.valueCallback);
    TestDev *synthetic = dev(@"Synthetic", 0x1234, 0x0020, 0, 41); synthetic.synthetic = 1; found(synthetic);
    TestDev *failed = dev(@"Failed", 0x1234, 0x0021, 0, 42); hidpad_found(NULL, kIOReturnError, NULL, ref(failed));
    CHECK(count(g_hidpads) == 1 && synthetic.attached == 0 && failed.attached == 0);   // GameController's own synthetic device and a failed match are skipped
    done("a device handed over twice is one pad; a synthetic device is skipped");

    // Microsoft's, Sony's and Nintendo's pads are left to GameController without a wait, whatever name it lists them under
    TestGC *xbox_gc = listed(@"Xbox Wireless Controller"); (void)xbox_gc;
    TestDev *xbox = dev(@"Xbox Wireless Controller", 0x045e, 0x0b13, 1, 33); found(xbox);
    TestDev *ds4 = dev(@"Wireless Controller", 0x054c, 0x09cc, 1, 34); found(ds4);       // listed as "DUALSHOCK 4 Wireless Controller": the name cannot vouch for it
    CHECK(in(g_hidpads_gc, xbox) && in(g_hidpads_gc, ds4) && xbox.attached == 0 && ds4.attached == 0 && !xbox.valueCallback && !ds4.valueCallback);
    button(xbox, 2, 1); CHECK(xbox.reads == 0);
    // Another vendor's pad that GameController lists under its HID product name is left to it at once too
    listed(@"Acme MFi Pad");
    TestDev *mfi = dev(@"Acme MFi Pad", 0x1234, 0x0010, 1, 35); found(mfi);
    CHECK(in(g_hidpads_gc, mfi) && mfi.attached == 0 && !mfi.valueCallback && !g_hidpads_waiting);
    done("an Xbox, PlayStation or listed pad is left to GameController and never read here");

    // A receiver that declares two gamepad collections (two registry entries) with one pad behind it: both are read, and only the one that presses tells the front end so
    TestDev *r1 = dev(@"2.4G Receiver", 0x1234, 0x0003, 0, 39), *r2 = dev(@"2.4G Receiver", 0x1234, 0x0003, 0, 40); found(r1); found(r2);
    button(r1, 2, 1);
    CHECK(in(g_hidpads, r1) && in(g_hidpads, r2) && r1.reads == 1 && r1.buttons == DM_BTN_A && r2.reads == 0);
    done("a receiver's silent second collection sends the front end nothing");

    // The hint says YES: the device waits HIDPAD_GC_WAIT for a GameController controller of its name
    TestDev *u2c = dev(@"8BitDo Ultimate 2C Wireless", 0x2dc8, 0x301b, 1, 32); found(u2c);   // the report's pad: GameController never lists it
    TestDev *u2c_again = dev(@"8BitDo Ultimate 2C Wireless", 0x2dc8, 0x301b, 1, 32); found(u2c_again);
    TestDev *late = dev(@"Acme Pad", 0x1234, 0x0001, 1, 36); found(late);                      // listed only after the wait
    TestDev *soon = dev(@"Acme Soon", 0x1234, 0x0002, 1, 37); found(soon);                     // listed during the wait
    TestDev *gone = dev(@"Acme Gone", 0x1234, 0x0004, 1, 38); found(gone);                     // unplugged during the wait
    TestDev *other = dev(@"Acme Wireless Pad", 0x1234, 0x0005, 1, 43); found(other);           // open case: listed under another name
    CHECK(count(g_hidpads_waiting) == 5 && in(g_hidpads_waiting, u2c) && !in(g_hidpads_waiting, u2c_again));
    CHECK(u2c.attached == 0 && !u2c.valueCallback && late.attached == 0 && soon.attached == 0);
    button(u2c, 2, 1); CHECK(u2c.reads == 0);                                   // a press during the wait reaches nothing
    TestGC *soon_gc = listed(@"Acme Soon"); hidpad_gc_connected(soon_gc);
    listed(@"Acme Controller");
    removed(gone); CHECK(count(g_hidpads_waiting) == 4);
    spin(HIDPAD_GC_WAIT + 0.3);
    CHECK(!g_hidpads_waiting);
    CHECK(in(g_hidpads, u2c) && u2c.attached == 1 && u2c.valueCallback && u2c_again.attached == 0);
    CHECK(logged("controller '8BitDo Ultimate 2C Wireless' (HID, 2dc8:301b): GameController says it lists it but has not after 2 s, so it is read as HID"));
    CHECK(!logged("controller '8BitDo Ultimate 2C Wireless' (HID, 2dc8:301b): buttons use"));   // 8BitDo's numbering is the default map
    button(u2c, 2, 1); CHECK(u2c.reads == 1 && u2c.buttons == DM_BTN_A);
    CHECK(in(g_hidpads_gc, xbox) && xbox.attached == 0 && xbox.reads == 0);     // beside it the Xbox pad is still GameController's alone
    done("the report's pad (2dc8:301b) is read after the wait, alone and beside an Xbox pad");

    CHECK(in(g_hidpads_gc, soon) && soon.attached == 0 && !soon.valueCallback);
    CHECK(!in(g_hidpads, gone) && !in(g_hidpads_gc, gone) && gone.attached == 0);
    done("a pad listed during the wait stays GameController's; one unplugged during it is dropped");

    CHECK(in(g_hidpads, late) && late.attached == 1 && late.detached == 0);
    button(late, 2, 1); button(late, 2, 0); CHECK(late.reads == 2);
    TestGC *late_gc = listed(@"Acme Pad"); hidpad_gc_connected(late_gc);        // front_mac.m calls it when a controller connects, before its slots change
    CHECK(in(g_hidpads_gc, late) && !in(g_hidpads, late) && late.detached == 1 && !late.valueCallback);
    CHECK(logged("controller 'Acme Pad' (HID) is now a GameController controller: read through it"));
    button(late, 2, 1); CHECK(late.reads == 2);
    CHECK(in(g_hidpads, u2c) && u2c.detached == 0);                             // another model's pads are not touched
    done("a pad GameController lists late is given back to it");

    // The two open cases of the reference entry, run and printed, not checked: the outcome is the defect it describes
    TestDev *denied = dev(@"Acme Other Pad", 0x1234, 0x0006, 0, 44); listed(@"Acme Other Pad"); found(denied);
    printf("note: open, not checked (docs/reference/services.md, \"A controller GameController does not list gets no input\"): a pad GameController lists under another name is %s; "
           "a pad it lists though the hint says NO is %s\n", in(g_hidpads, other) ? "read as HID too" : "left to GameController", in(g_hidpads, denied) ? "read as HID too" : "left to GameController");

    // Unplugged: the front end is told once for a pad that was read, and nothing is kept
    removed(gen);
    CHECK(gen.detached == 1 && !gen.valueCallback && !in(g_hidpads, gen));
    removed(xbox); CHECK(xbox.detached == 0 && !in(g_hidpads_gc, xbox));        // one GameController read: the front end was never told of it
    for (TestDev *d in @[ds4, mfi, r1, r2, u2c, late, soon, other, denied]) removed(d);
    CHECK(!g_hidpads && !g_hidpads_waiting && !g_hidpads_gc);
    done("an unplugged pad is dropped from every list");

    setenv("DM_HID_PADS", "0", 1); hidpad_start(); unsetenv("DM_HID_PADS");
    CHECK(!g_hidpad_manager);
    done("DM_HID_PADS=0 starts no HID manager");

    printf("t_pad_hid_found: %d checks, %d failed\n", checks, fails);
    return fails != 0;
} }
