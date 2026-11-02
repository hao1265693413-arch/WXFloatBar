//
//  WXInjector.m —— 巨魔输入器注入入口
//
//  说明（重要）：
//  巨魔(TrollStore)的"输入器"本质上是往目标 App 进程里加载一个 dylib。
//  不同输入器（如 TrollFools、TrollStore 自带的注入、Silica 等）加载时机不同：
//  有的在 main() 之前，有的在 UIApplication 起来之后。
//  因此这里做的是「防御式挂载」：
//    1. +load 里注册通知，等 UIWindow 出现
//    2. 轮询兜底（最多 20 秒），防止 window 晚于通知出现
//    3. 通过环境变量 WXFB_AUTO / 偏好域 决定是否自动显示
//

#import <UIKit/UIKit.h>
#import "WXFloatBarManager.h"

static BOOL gWXFBStarted = NO;

static void WXFBStart(void) {
    if (gWXFBStarted) return;

    // 只对微信生效（注入器可能注入到任意 App）
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"";
    BOOL isWeChat = [bundle hasPrefix:@"com.tencent.xin"] || [bundle isEqualToString:@"com.tencent.mm"];
    BOOL force = [NSProcessInfo.processInfo.environment[@"WXFB_FORCE"] boolValue];
    if (!isWeChat && !force) return;

    gWXFBStarted = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        WXFloatBarManager *m = [WXFloatBarManager shared];
        [m reloadSettings];
        [m show];
    });
}

__attribute__((constructor)) static void WXFBConstructor(void) {
    NSLog(@"[WXFloatBar] injected into %@", [NSBundle mainBundle].bundleIdentifier);

    // 1. 立刻尝试（若 window 已存在）
    WXFBStart();

    // 2. 等 App 启动完成
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { WXFBStart(); }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { WXFBStart(); }];

    // 3. 轮询兜底（确保在主线程创建定时器）
    dispatch_async(dispatch_get_main_queue(), ^{
        __block NSInteger tries = 0;
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            tries++;
            UIWindow *w = nil;
            for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if ([s isKindOfClass:UIWindowScene.class]) {
                    for (UIWindow *win in ((UIWindowScene *)s).windows) {
                        if (!win.hidden) { w = win; break; }
                    }
                }
                if (w) break;
            }
            if (w) {
                [timer invalidate];
                WXFBStart();
            } else if (tries > 40) {
                [timer invalidate];
                NSLog(@"[WXFloatBar] 未找到可挂载的 window（主线程可能尚未就绪）");
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });
}

// 供其他 dylib / 输入器通过 dlsym 调用
__attribute__((visibility("default"))) void WXFBShow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[WXFloatBarManager shared] show]; });
}

__attribute__((visibility("default"))) void WXFBHide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[WXFloatBarManager shared] hide]; });
}
