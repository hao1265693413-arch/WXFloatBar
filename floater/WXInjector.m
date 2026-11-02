//
//  WXInjector.m —— 注入入口（rootless deb / TrollStore 输入器通用）
//
//  只做三件事：
//   1. 确认自己跑在微信里
//   2. 安装 TabBar 改造（swizzle，纯 objc runtime，不依赖 substrate）
//   3. 兜底：如果注入时机晚于微信首次布局，主动触发几次重新布局
//

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "WXTabBarStyler.h"

static BOOL gInstalled = NO;
static NSInteger gNudges = 0;

__attribute__((visibility("default"))) void WXFBShow(void);
__attribute__((visibility("default"))) void WXFBHide(void);

static BOOL WXIsWeChat(void) {
    NSString *b = [NSBundle mainBundle].bundleIdentifier ?: @"";
    if ([b hasPrefix:@"com.tencent.xin"] || [b isEqualToString:@"com.tencent.mm"]) return YES;
    return [NSProcessInfo.processInfo.environment[@"WXFB_FORCE"] boolValue];
}

static UITabBarController *WXFindTBC(UIViewController *vc);

/// 找当前的 UITabBarController（微信根控制器通常是它或它被嵌套）
static UITabBarController *WXFindTabBarController(void) {
    UIWindow *win = UIApplication.sharedApplication.keyWindow;
    if (!win) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (!w.hidden && w.windowLevel == UIWindowLevelNormal) { win = w; break; }
            }
            if (win) break;
        }
    }
    UIViewController *vc = win.rootViewController;
    return WXFindTBC(vc);
}

static UITabBarController *WXFindTBC(UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:UITabBarController.class]) return (UITabBarController *)vc;

    if ([vc isKindOfClass:UINavigationController.class]) {
        UITabBarController *r = WXFindTBC(((UINavigationController *)vc).viewControllers.firstObject);
        if (r) return r;
    }
    if ([vc isKindOfClass:UITabBarController.class]) return (UITabBarController *)vc;

    for (UIViewController *child in vc.childViewControllers) {
        UITabBarController *r = WXFindTBC(child);
        if (r) return r;
    }
    UIViewController *p = vc.presentedViewController;
    if (p) return WXFindTBC(p);
    return nil;
}

/// 先强制一次布局让 bounds 有效，再主动扫描上样式
/// （不依赖 layoutSubviews 钩子，从根上避免布局死循环）
static void WXNudge(void) {
    UITabBarController *tbc = WXFindTabBarController();
    if (tbc) {
        [tbc.view setNeedsLayout];
        [tbc.view layoutIfNeeded];
    }
    [WXTabBarStyler rescan];
}

/// 加载确认提示（用来判断 dylib 到底有没有被加载）
static void WXConfirmToast(void) {
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (!w) return;
    UILabel *l = [UILabel new];
    l.text = @"WXFloatBar 已加载";
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    l.layer.cornerRadius = 12;
    l.layer.masksToBounds = YES;
    l.frame = CGRectMake((w.bounds.size.width - 190) / 2, w.bounds.size.height - 180, 190, 38);
    l.alpha = 0;
    [w addSubview:l];
    [UIView animateWithDuration:0.25 animations:^{ l.alpha = 1; } completion:^(BOOL f) {
        [UIView animateWithDuration:0.4 delay:1.4 options:0 animations:^{ l.alpha = 0; }
                         completion:^(BOOL done) { [l removeFromSuperview]; }];
    }];
}

__attribute__((constructor)) static void WXFBConstructor(void) {
    // 防重复加载（ElleKit 与 Substrate 兼容目录同时被扫描时会出现两份）
    void *existing = dlsym(RTLD_DEFAULT, "WXFBShow");
    if (existing && existing != (void *)&WXFBShow) {
        NSLog(@"[WXFloatBar] duplicate image, skip");
        return;
    }

    NSLog(@"[WXFloatBar] loaded into %@", [NSBundle mainBundle].bundleIdentifier);
    if (!WXIsWeChat()) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gInstalled) return;
        gInstalled = YES;

        [WXTabBarStyler install];
        WXNudge();

        // 注入时机可能晚于微信首次布局，前几秒多推几次
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(NSTimer *timer) {
            gNudges++;
            WXNudge();
            if (gNudges == 1) WXConfirmToast();
            if (gNudges > 6) [timer invalidate];
        }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { WXNudge(); }];
    [nc addObserverForName:UIWindowDidBecomeKeyNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { WXNudge(); }];
}

__attribute__((visibility("default"))) void WXFBShow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ WXNudge(); });
}

__attribute__((visibility("default"))) void WXFBHide(void) {
    // 目前不做隐藏，保留接口供 dlsym 使用
    NSLog(@"[WXFloatBar] WXFBHide called");
}
