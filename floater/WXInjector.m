//
//  WXInjector.m —— 注入入口（rootless deb / TrollStore 输入器通用）
//
//  设计要点：
//  1. constructor 执行时 UIWindow 几乎肯定还不存在，所以「只挂一次」是错的。
//     这里把「已注入」和「已挂载」拆开，挂载失败就继续重试，直到成功。
//  2. 除了轮询，还监听 window 变化通知，微信换 window 时能自动重新挂上。
//  3. 首次挂载成功会弹一个 toast，用来确认 dylib 到底有没有被加载。
//

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "WXFloatBarManager.h"

static BOOL gObserversInstalled = NO;
static BOOL gAttached = NO;
static NSInteger gTries = 0;

// 前向声明（constructor 里要用到地址做重复加载判断）
__attribute__((visibility("default"))) void WXFBShow(void);
__attribute__((visibility("default"))) void WXFBHide(void);

/// 找一个真正用来显示内容的 window
/// （排除键盘 window、状态栏 window、以及 hidden / level 不为 Normal 的）
static UIWindow *WXFindWindow(void) {
    UIWindow *best = nil;
    CGFloat bestArea = 0;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.hidden) continue;
            if (w.alpha < 0.01) continue;
            if (w.windowLevel != UIWindowLevelNormal) continue;
            CGFloat area = w.bounds.size.width * w.bounds.size.height;
            if (area > bestArea) { bestArea = area; best = w; }
        }
    }

    if (!best) {
        UIWindow *kw = UIApplication.sharedApplication.keyWindow;
        if (kw && !kw.hidden && kw.windowLevel == UIWindowLevelNormal) best = kw;
    }
    return best;
}

static BOOL WXIsWeChat(void) {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"";
    if ([bundle hasPrefix:@"com.tencent.xin"]) return YES;
    if ([bundle isEqualToString:@"com.tencent.mm"]) return YES;
    return [NSProcessInfo.processInfo.environment[@"WXFB_FORCE"] boolValue];
}

/// 尝试挂载一次。返回是否成功。
static BOOL WXTryAttach(void) {
    if (!WXIsWeChat()) return NO;

    UIWindow *w = WXFindWindow();
    if (!w) return NO;

    WXFloatBarManager *m = [WXFloatBarManager shared];
    [m attachToWindow:w];
    [m show];

    if (!gAttached) {
        gAttached = YES;
        NSLog(@"[WXFloatBar] attached to window %@", w);
        [m flashConfirmToast];
    }
    return YES;
}

static void WXStartPolling(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:YES block:^(NSTimer *timer) {
            gTries++;
            if (WXTryAttach()) {
                [timer invalidate];
                return;
            }
            if (gTries > 25) {   // 10 秒还没挂上，放弃轮询，靠通知兜底
                [timer invalidate];
                NSLog(@"[WXFloatBar] 轮询超时，仍未找到 window（已尝试 %ld 次）", (long)gTries);
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });
}

__attribute__((constructor)) static void WXFBConstructor(void) {
    // 防重复加载：如果同符号已由另一个镜像提供，说明加载了两份，直接退出。
    // （ElleKit 与 Substrate 兼容目录同时被扫描时会出现这种情况）
    void *existing = dlsym(RTLD_DEFAULT, "WXFBShow");
    if (existing && existing != (void *)&WXFBShow) {
        NSLog(@"[WXFloatBar] duplicate image detected, skipping");
        return;
    }

    NSLog(@"[WXFloatBar] dylib loaded into %@", [NSBundle mainBundle].bundleIdentifier);

    // 立刻试一次（万一 window 已经在了）
    dispatch_async(dispatch_get_main_queue(), ^{ WXTryAttach(); });

    if (gObserversInstalled) return;
    gObserversInstalled = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    // App 启动完成 / 回到前台
    [nc addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { WXTryAttach(); }];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { WXTryAttach(); }];

    // window 出现 / 切换（微信会重建 window，必须重新挂，否则胶囊会消失）
    [nc addObserverForName:UIWindowDidBecomeKeyNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { WXTryAttach(); }];
    [nc addObserverForName:UIWindowDidBecomeVisibleNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { WXTryAttach(); }];

    WXStartPolling();
}

// 供其他 dylib / 输入器通过 dlsym 调用
__attribute__((visibility("default"))) void WXFBShow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[WXFloatBarManager shared] show]; });
}

__attribute__((visibility("default"))) void WXFBHide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[WXFloatBarManager shared] hide]; });
}
