//
//  WXPrefs.m
//

#import "WXPrefs.h"

NSString *const WXPrefDomain = @"com.hao.wxfloatbar";

NSString *const kWXPrefMargin     = @"WXFB_margin";
NSString *const kWXPrefHeight     = @"WXFB_height";
NSString *const kWXPrefTintAlpha  = @"WXFB_tintAlpha";
NSString *const kWXPrefBlur       = @"WXFB_blur";
NSString *const kWXPrefShowLabels = @"WXFB_showLabels";
NSString *const kWXPrefAvatar     = @"WXFB_avatarPath";

static NSUserDefaults *WXD(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [NSUserDefaults standardUserDefaults];
    });
    return d;
}

CGFloat WXPrefFloat(NSString *key, CGFloat def) {
    NSNumber *n = [WXD() objectForKey:key];
    return n ? n.floatValue : def;
}

BOOL WXPrefBool(NSString *key, BOOL def) {
    id v = [WXD() objectForKey:key];
    return v ? [v boolValue] : def;
}

NSString *WXPrefString(NSString *key, NSString *def) {
    id v = [WXD() objectForKey:key];
    return [v isKindOfClass:NSString.class] ? v : def;
}

void WXPrefSetFloat(NSString *key, CGFloat v) {
    [WXD() setFloat:v forKey:key];
    [WXD() synchronize];
}

void WXPrefSetBool(NSString *key, BOOL v) {
    [WXD() setBool:v forKey:key];
    [WXD() synchronize];
}

void WXPrefSetString(NSString *key, NSString *v) {
    if (v) [WXD() setObject:v forKey:key];
    else   [WXD() removeObjectForKey:key];
    [WXD() synchronize];
}

/// 优先写到 /var/mobile/Library/Preferences，失败则写沙盒 tmp
NSString *WXAvatarStorePath(void) {
    static NSString *cached = nil;
    if (cached) return cached;

    // 微信运行在沙盒里，优先用容器内 Library（一定可写、不会被系统清）
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                         NSUserDomainMask, YES) firstObject];
    NSMutableArray *candidates = [NSMutableArray array];
    [candidates addObject:@"/var/mobile/Library/Preferences/WXFloatBarAvatar.png"];
    if (lib.length) {
        [candidates addObject:[lib stringByAppendingPathComponent:@"WXFloatBarAvatar.png"]];
    }
    [candidates addObject:[NSTemporaryDirectory() stringByAppendingPathComponent:@"WXFloatBarAvatar.png"]];
    for (NSString *p in candidates) {
        NSString *dir = [p stringByDeletingLastPathComponent];
        if ([[NSFileManager defaultManager] isWritableFileAtPath:dir]) {
            cached = p;
            return cached;
        }
    }
    cached = candidates.lastObject;
    return cached;
}
