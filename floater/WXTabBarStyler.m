//
//  WXTabBarStyler.m
//

#import "WXTabBarStyler.h"
#import "WXGlassView.h"
#import "WXPrefs.h"
#import "WXSettingsController.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - 基础

static const void *kWXGlassKey  = &kWXGlassKey;
static const void *kWXIndKey    = &kWXIndKey;
static const void *kWXStyledKey = &kWXStyledKey;
static const void *kWXLastWKey  = &kWXLastWKey;
static const void *kWXCapsuleKey = &kWXCapsuleKey;
static const NSInteger kWXCapsuleTag = 0x57584745;

static BOOL WXIsWeChat(void) {
    NSString *b = [NSBundle mainBundle].bundleIdentifier ?: @"";
    if ([b hasPrefix:@"com.tencent.xin"] || [b isEqualToString:@"com.tencent.mm"]) return YES;
    return [NSProcessInfo.processInfo.environment[@"WXFB_FORCE"] boolValue];
}

static void WXSwizzle(Class cls, SEL origSel, SEL newSel) {
    Method orig = class_getInstanceMethod(cls, origSel);
    Method new  = class_getInstanceMethod(cls, newSel);
    if (!orig || !new) return;
    BOOL added = class_addMethod(cls, origSel,
                                 method_getImplementation(new),
                                 method_getTypeEncoding(new));
    if (added) {
        class_replaceMethod(cls, newSel,
                            method_getImplementation(orig),
                            method_getTypeEncoding(orig));
    } else {
        method_exchangeImplementations(orig, new);
    }
}

/// 递归收集 tab 按钮（不同 iOS 版本类名不同，用模糊匹配）
static void WXCollectTabButtons(UIView *v, NSMutableArray<UIView *> *out) {
    for (UIView *s in v.subviews) {
        NSString *cn = NSStringFromClass(s.class);
        BOOL isButton = [cn containsString:@"UITabBarButton"] ||
                        [cn containsString:@"TabBarItemView"] ||
                        [cn hasSuffix:@"TabBarButton"];
        if (isButton) {
            [out addObject:s];
        } else {
            WXCollectTabButtons(s, out);
        }
    }
}

/// 递归隐藏 tab bar 的所有背景层（跳过我们自己的玻璃/指示器）
static void WXHideBackgrounds(UIView *v) {
    for (UIView *s in v.subviews) {
        if (s.tag == 0x57584742 || s.tag == 0x57584743) continue;  // 我们的视图
        if (s.tag == 0x57584744) continue;
        NSString *cn = NSStringFromClass(s.class);

        BOOL isBg = [cn containsString:@"BarBackground"] ||
                    [cn containsString:@"BackgroundView"] ||
                    [cn containsString:@"Background"] ||
                    [cn containsString:@"Separator"] ||
                    [cn containsString:@"Shadow"];
        if (isBg) {
            if (!s.hidden) s.hidden = YES;
            s.backgroundColor = UIColor.clearColor;
            s.alpha = 0.0;
            s.layer.backgroundColor = UIColor.clearColor.CGColor;
        }
        WXHideBackgrounds(s);
    }
}

static UIImage *WXCircularImage(UIImage *img, CGFloat size) {
    if (!img) return nil;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextAddEllipseInRect(ctx, CGRectMake(0, 0, size, size));
    CGContextClip(ctx);
    [img drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [out imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static NSArray<UIView *> *WXTabButtons(UITabBar *tb) {
    NSMutableArray *arr = [NSMutableArray array];
    WXCollectTabButtons(tb, arr);
    [arr sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGPoint ca = [a.superview convertPoint:a.center toView:tb];
        CGPoint cb = [b.superview convertPoint:b.center toView:tb];
        if (ca.x < cb.x) return NSOrderedAscending;
        if (ca.x > cb.x) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return arr;
}

#pragma mark - 液态指示器

@interface WXLiquidIndicatorView : UIView
@property (nonatomic, strong) UIVisualEffectView *blur;
- (void)moveToCenterX:(CGFloat)x width:(CGFloat)w animated:(BOOL)animated;
- (void)applyStyle;
@end

@implementation WXLiquidIndicatorView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;

        _blur = [[UIVisualEffectView alloc] initWithEffect:
                 [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
        _blur.userInteractionEnabled = NO;
        _blur.clipsToBounds = YES;
        [self addSubview:_blur];

        self.layer.masksToBounds = NO;
        [self applyStyle];
    }
    return self;
}

- (void)applyStyle {
    CGFloat r = self.bounds.size.height / 2.0;
    self.layer.cornerRadius = r;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
    _blur.frame = self.bounds;
    _blur.layer.cornerRadius = r;
    _blur.layer.cornerCurve = kCACornerCurveContinuous;

    self.layer.borderWidth = 0.8;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.65].CGColor;

    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.10;
    self.layer.shadowRadius = 8;
    self.layer.shadowOffset = CGSizeMake(0, 2);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyStyle];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                       cornerRadius:self.bounds.size.height / 2].CGPath;
}

- (void)moveToCenterX:(CGFloat)x width:(CGFloat)w animated:(BOOL)animated {
    CGRect cur = self.frame;
    CGRect target = CGRectMake(x - w / 2.0, cur.origin.y, w, cur.size.height);

    if (!animated) {
        self.frame = target;
        [self applyStyle];
        return;
    }

    // 位置：弹簧
    [UIView animateWithDuration:0.42 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.frame = target;
    } completion:nil];

    // 挤压：横拉长 + 纵向压扁，回来时反向，这是"液态"的关键
    CAKeyframeAnimation *sx = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    sx.values = @[@1.0, @1.26, @0.94, @1.0];
    sx.keyTimes = @[@0.0, @0.32, @0.68, @1.0];

    CAKeyframeAnimation *sy = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.y"];
    sy.values = @[@1.0, @0.90, @1.04, @1.0];
    sy.keyTimes = @[@0.0, @0.32, @0.68, @1.0];

    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[sx, sy];
    g.duration = 0.42;
    g.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    g.removedOnCompletion = YES;
    [self.layer addAnimation:g forKey:@"wx.liquid"];

    // 高光扫过
    CALayer *shine = [CALayer layer];
    shine.frame = CGRectMake(-w * 0.5, 0, w * 0.5, cur.size.height);
    shine.backgroundColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    shine.opacity = 0;
    [self.layer addSublayer:shine];

    CABasicAnimation *mv = [CABasicAnimation animationWithKeyPath:@"position.x"];
    mv.fromValue = @(-w * 0.25);
    mv.toValue   = @(w * 1.25);
    CABasicAnimation *op = [CABasicAnimation animationWithKeyPath:@"opacity"];
    op.fromValue = @0.0;
    op.toValue   = @0.9;
    CAAnimationGroup *sg = [CAAnimationGroup animation];
    sg.animations = @[mv, op];
    sg.duration = 0.40;
    [shine addAnimation:sg forKey:@"shine"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [shine removeFromSuperlayer]; });
}

@end

//
//  WXTabBarStyler.m （续）
//


#pragma mark - 参数

static BOOL    gFloating   = YES;
static CGFloat gBarHeight  = 58.0;
static CGFloat gHMargin    = 14.0;
static CGFloat gBottomGap  = 8.0;

#pragma mark - Styler

@interface WXTabBarStyler ()
+ (CGRect)pillRectFor:(UITabBar *)tb;
+ (void)updateIndicator:(UITabBar *)tb animated:(BOOL)animated;
+ (void)selectIndex:(NSInteger)idx inTabBar:(UITabBar *)tb;
+ (NSInteger)selectedIndexFor:(UITabBar *)tb;
+ (void)applyAvatarTo:(UITabBar *)tb;
+ (void)startSelectionPolling:(UITabBar *)tb;
+ (void)rescanInView:(UIView *)root;
@end

@implementation WXTabBarStyler

+ (void)setFloating:(BOOL)floating        { gFloating = floating; }
+ (void)setBarHeight:(CGFloat)height      { gBarHeight = height; }
+ (void)setHorizontalMargin:(CGFloat)m    { gHMargin = m; }
+ (void)setBottomGap:(CGFloat)gap         { gBottomGap = gap; }

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        WXSwizzle([UITabBarController class], @selector(setSelectedIndex:), @selector(wx_setSelectedIndex:));
        WXSwizzle([UITabBar class], @selector(setSelectedItem:), @selector(wx_setSelectedItem:));

        // 系统切换深浅色时刷新
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *n) {
            if (!WXIsWeChat()) return;
            UIWindow *w = UIApplication.sharedApplication.keyWindow;
            [self rescanInView:w];
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                          object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self rescan]; });
        }];
        // 前 40 秒持续维护：微信可能在启动后才创建背景层或底栏
        __block NSInteger ticks = 0;
        NSTimer *m = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
            ticks++;
            [self rescan];
            if (ticks > 26) [t invalidate];
        }];
        [[NSRunLoop mainRunLoop] addTimer:m forMode:NSRunLoopCommonModes];

        NSLog(@"[WXFloatBar] tab bar styler installed");
    });
}

#pragma mark 选中项轮询

static UITabBar *gPollBar = nil;
static UITabBarItem *gPollLast = nil;

/// 微信切 tab 不一定走 setSelectedIndex: / setSelectedItem:，
/// 那两个 hook 可能根本不触发，所以这里用轮询兜底（0.15s 读一次属性，开销可忽略）
+ (void)startSelectionPolling:(UITabBar *)tb {
    if (!tb) return;
    gPollBar = tb;
    gPollLast = tb.selectedItem;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
            UITabBar *bar = gPollBar;
            if (!bar) return;
            UITabBarItem *cur = bar.selectedItem;
            if (cur != gPollLast) {
                gPollLast = cur;
                [WXTabBarStyler updateIndicator:bar animated:YES];
            }
        }];
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    });
}

+ (void)rescan {
    if (!WXIsWeChat()) return;
    UIWindow *w = UIApplication.sharedApplication.keyWindow;
    if (!w) {
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if (![sc isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *win in ((UIWindowScene *)sc).windows) {
                if (!win.hidden) { w = win; break; }
            }
            if (w) break;
        }
    }
    [self rescanInView:w];
}

+ (void)rescanInView:(UIView *)root {
    if (!root) return;
    if ([root isKindOfClass:UITabBar.class]) {
        [self styleTabBar:(UITabBar *)root];
        [WXSettingsController installLongPressOnView:root];
        return;
    }
    for (UIView *s in root.subviews) [self rescanInView:s];
}

#pragma mark 外观

+ (void)styleTabBar:(UITabBar *)tb {
    if (!WXIsWeChat() || !tb) return;
    if (tb.bounds.size.width < 100) return;

    // 看门狗：一秒内超过 120 次说明进了布局循环，立刻停手
    static NSTimeInterval windowStart = 0;
    static NSInteger callCount = 0;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - windowStart > 1.0) { windowStart = now; callCount = 0; }
    if (++callCount > 120) return;

    static BOOL inStyling = NO;
    if (inStyling) return;
    inStyling = YES;

    @try {
        CGRect pill = [self pillRectFor:tb];

        // ---------- 一次性：抹掉系统背景 ----------
        if (!objc_getAssociatedObject(tb, kWXStyledKey)) {
            objc_setAssociatedObject(tb, kWXStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // iOS 15+ 只有 UITabBarAppearance 有效
            if (@available(iOS 13.0, *)) {
                UITabBarAppearance *ap = [UITabBarAppearance new];
                [ap configureWithTransparentBackground];
                ap.backgroundColor = UIColor.clearColor;
                ap.backgroundEffect = nil;
                ap.shadowColor = UIColor.clearColor;
                ap.shadowImage = [UIImage new];
                ap.backgroundImage = [UIImage new];
                tb.standardAppearance = ap;
                if (@available(iOS 15.0, *)) tb.scrollEdgeAppearance = ap;
            }
            tb.backgroundImage = [UIImage new];
            tb.shadowImage = [UIImage new];
            tb.backgroundColor = UIColor.clearColor;
            tb.opaque = NO;
            tb.layer.backgroundColor = UIColor.clearColor.CGColor;
            tb.clipsToBounds = NO;
        }

        // ---------- 每轮：隐藏微信自己的全部子视图 ----------
        // 原生按钮按整条 tab bar（含底部安全区）排版，图标会落在胶囊里、
        // 文字却掉到胶囊外面，所以干脆全部隐藏，自己在胶囊里画一套。
        for (UIView *v in tb.subviews) {
            if (v.tag == kWXCapsuleTag) continue;
            if (!v.hidden) v.hidden = YES;
            if (v.alpha > 0.01) v.alpha = 0.0;
        }

        // ---------- 自绘胶囊 ----------
        WXCapsuleBar *cap = objc_getAssociatedObject(tb, kWXCapsuleKey);
        if (!cap) {
            NSArray *items = @[
                @{@"icon": @"message.fill",                    @"title": @"微信"},
                @{@"icon": @"person.text.rectangle.fill",      @"title": @"通讯录"},
                @{@"icon": @"safari.fill",                     @"title": @"发现"},
                @{@"icon": @"person.fill",                     @"title": @"我"},
            ];
            cap = [[WXCapsuleBar alloc] initWithItems:items size:pill.size];
            cap.tag = kWXCapsuleTag;
            cap.layer.zPosition = 10;
            cap.backgroundColor = UIColor.clearColor;

            __weak UITabBar *weakTB = tb;
            cap.onTap = ^(NSInteger idx, UIButton *b) {
                [WXTabBarStyler selectIndex:idx inTabBar:weakTB];
            };
            [tb addSubview:cap];
            objc_setAssociatedObject(tb, kWXCapsuleKey, cap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            cap.glass.style = WXGlassStyleFrost;
            cap.glass.tintColor = UIColor.whiteColor;
            cap.glass.tintAlpha = WXPrefFloat(kWXPrefTintAlpha, 0.14);
            cap.glass.edgeOpacity = 0.60;
            cap.glass.sheen = 1.0;
            [cap.glass refresh];

            // 选中指示器：放在胶囊里，玻璃之上、按钮之下
            WXLiquidIndicatorView *ind =
                [[WXLiquidIndicatorView alloc] initWithFrame:CGRectMake(0, 4, 64, pill.size.height - 8)];
            ind.tag = 0x57584743;
            [cap insertSubview:ind atIndex:1];
            objc_setAssociatedObject(tb, kWXIndKey, ind, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [self updateIndicator:tb animated:NO];
        }

        if (cap.superview != tb) {
            cap.layer.zPosition = 10;
            [tb addSubview:cap];
        }
        if (!CGRectEqualToRect(cap.frame, pill)) {
            cap.frame = pill;
        }

        // 玻璃浓度跟随设置
        CGFloat ta = WXPrefFloat(kWXPrefTintAlpha, 0.14);
        if (fabs(cap.glass.tintAlpha - ta) > 0.001) {
            cap.glass.tintAlpha = ta;
        }

        // 文字显隐
        [cap setShowsTitles:WXPrefBool(kWXPrefShowLabels, YES)];

        // 头像
        [self applyAvatarTo:tb];

        // 选中项轮询
        [self startSelectionPolling:tb];

    } @catch (NSException *e) {
        NSLog(@"[WXFloatBar] style error: %@", e);
    }
    inStyling = NO;
}

#pragma mark 切换 tab

+ (NSInteger)selectedIndexFor:(UITabBar *)tb {
    UIResponder *r = tb;
    while (r && ![r isKindOfClass:UITabBarController.class]) r = r.nextResponder;
    if ([r isKindOfClass:UITabBarController.class]) {
        return (NSInteger)((UITabBarController *)r).selectedIndex;
    }
    UITabBarItem *item = tb.selectedItem;
    if (item) {
        NSUInteger i = [tb.items indexOfObject:item];
        if (i != NSNotFound) return (NSInteger)i;
    }
    return 0;
}

+ (void)selectIndex:(NSInteger)idx inTabBar:(UITabBar *)tb {
    if (!tb || idx < 0) return;

    @try {
        // 首选：直接触发微信原生按钮的点击事件。
        // 这是最接近真实点击的路径，不会绕过微信自己的切换逻辑。
        // 原生按钮只是被隐藏了，仍然在视图层级里，事件照常可发。
        NSArray<UIView *> *native = WXTabButtons(tb);
        if (idx < (NSInteger)native.count) {
            UIView *btn = native[idx];
            if ([btn isKindOfClass:UIControl.class] && btn.window) {
                [(UIControl *)btn sendActionsForControlEvents:UIControlEventTouchUpInside];
                // 延后按真实状态刷新，避免切换失败时指示器"假装"移动
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [WXTabBarStyler updateIndicator:tb animated:YES];
                });
                return;
            }
        }

        // 兜底：不调 delegate（微信的 delegate 不是标准实现，硬调会崩）
        if (idx < (NSInteger)tb.items.count) {
            UITabBarItem *item = tb.items[idx];
            if (tb.selectedItem != item) tb.selectedItem = item;
        }

        UIResponder *r = tb;
        while (r && ![r isKindOfClass:UITabBarController.class]) r = r.nextResponder;
        if ([r isKindOfClass:UITabBarController.class]) {
            UITabBarController *tbc = (UITabBarController *)r;
            if (tbc.selectedIndex != (NSUInteger)idx && idx < (NSInteger)tbc.viewControllers.count) {
                tbc.selectedIndex = (NSUInteger)idx;
            }
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [WXTabBarStyler updateIndicator:tb animated:YES];
        });
    } @catch (NSException *e) {
        NSLog(@"[WXFloatBar] selectIndex error: %@", e);
    }
}

+ (void)applyAvatarTo:(UITabBar *)tb {
    NSString *path = WXPrefString(kWXPrefAvatar, nil);
    if (path.length == 0) return;
    UIImage *img = [UIImage imageWithContentsOfFile:path];
    if (!img) return;

    WXCapsuleBar *cap = objc_getAssociatedObject(tb, kWXCapsuleKey);
    if (!cap) return;
    NSArray<UIButton *> *btns = cap.buttons;
    if (btns.count < 4) return;

    UIImage *circle = WXCircularImage(img, 24.0);
    if (!circle) return;

    UIButton *me = btns.lastObject;
    if (me.currentImage != circle) {
        [me setImage:circle forState:UIControlStateNormal];
    }
}

+ (void)updateIndicator:(UITabBar *)tb animated:(BOOL)animated {
    if (!tb) return;
    WXLiquidIndicatorView *ind = objc_getAssociatedObject(tb, kWXIndKey);
    WXCapsuleBar *cap = objc_getAssociatedObject(tb, kWXCapsuleKey);
    if (!ind || !cap) return;

    NSArray<UIButton *> *btns = cap.buttons;
    if (btns.count == 0) return;

    NSInteger sel = [self selectedIndexFor:tb];
    if (sel < 0 || sel >= (NSInteger)btns.count) sel = 0;

    UIButton *btn = btns[sel];

    CGFloat ih = MAX(26.0, cap.bounds.size.height - 8.0);
    CGFloat iy = (cap.bounds.size.height - ih) / 2.0;
    CGRect f = ind.frame;
    if (fabs(f.size.height - ih) > 0.5 || fabs(f.origin.y - iy) > 0.5) {
        f.size.height = ih;
        f.origin.y = iy;
        ind.frame = f;
        [ind applyStyle];
    }

    // 用 bounds 直接算位置，不依赖按钮是否已完成布局
    CGFloat n = (CGFloat)btns.count;
    CGFloat slot = (cap.bounds.size.width - 8.0) / n;
    CGFloat cx = 4.0 + slot * ((CGFloat)sel + 0.5);
    CGFloat bw = MAX(52.0, slot * 0.84);
    [ind moveToCenterX:cx width:bw animated:animated];
}

@end

#pragma mark - Hook：UITabBar

@interface UITabBar (WXHook)
- (void)wx_setSelectedItem:(UITabBarItem *)item;
@end

@implementation UITabBar (WXHook)

- (void)wx_setSelectedItem:(UITabBarItem *)item {
    [self wx_setSelectedItem:item];    // 原实现
    [WXTabBarStyler updateIndicator:self animated:YES];
}

@end

#pragma mark - Hook：UITabBarController

@interface UITabBarController (WXHook)
- (void)wx_setSelectedIndex:(NSUInteger)index;
@end

@implementation UITabBarController (WXHook)

- (void)wx_setSelectedIndex:(NSUInteger)index {
    [self wx_setSelectedIndex:index];  // 原实现
    [WXTabBarStyler updateIndicator:self.tabBar animated:YES];
}

@end
