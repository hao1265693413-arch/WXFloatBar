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

    // ---- 看门狗 ----
    // 如果一秒内被调用超过 120 次，说明已经进入布局死循环。
    // 立刻停止干活，避免把主线程彻底拖死。
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

        // ================= 一次性 =================
        // 关键：这些 UIKit setter 内部会 setNeedsLayout。
        // 每轮布局都设一次，就会「设属性 → 重新布局 → 再设属性」无限循环 = 卡死。
        // 所以整个生命周期里只做一次。
        if (!objc_getAssociatedObject(tb, kWXStyledKey)) {
            objc_setAssociatedObject(tb, kWXStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            // iOS 15+ 上 backgroundImage / shadowImage 已经失效，
            // 必须用 UITabBarAppearance 才能真正清掉背景
            if (@available(iOS 13.0, *)) {
                UITabBarAppearance *ap = [UITabBarAppearance new];
                [ap configureWithTransparentBackground];
                ap.backgroundColor = UIColor.clearColor;
                ap.backgroundEffect = nil;
                ap.shadowColor = UIColor.clearColor;
                ap.shadowImage = [UIImage new];
                ap.backgroundImage = [UIImage new];
                tb.standardAppearance = ap;
                if (@available(iOS 15.0, *)) {
                    tb.scrollEdgeAppearance = ap;
                }
            }
            tb.backgroundImage = [UIImage new];
            tb.shadowImage = [UIImage new];
            tb.backgroundColor = UIColor.clearColor;
            if (!tb.translucent) tb.translucent = YES;
            tb.clipsToBounds = NO;

            tb.opaque = NO;
            tb.layer.backgroundColor = UIColor.clearColor.CGColor;
            tb.layer.cornerRadius = 0;
            tb.layer.masksToBounds = NO;
        }

        // 背景层可能在首次之后才创建，所以每轮都扫一次（隐藏不会触发布局）
        WXHideBackgrounds(tb);

        // ================= 每轮 =================
        // 只做不触发布局的操作：frame 值相同 UIKit 会自己跳过，zPosition 不影响布局

        WXGlassView *glass = objc_getAssociatedObject(tb, kWXGlassKey);
        if (!glass) {
            glass = [[WXGlassView alloc] initWithFrame:pill];
            glass.userInteractionEnabled = NO;
            glass.tag = 0x57584742;
            [tb insertSubview:glass atIndex:0];
            objc_setAssociatedObject(tb, kWXGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            glass.style = WXGlassStyleFrost;
            glass.tintColor = UIColor.whiteColor;
            glass.tintAlpha = WXPrefFloat(kWXPrefTintAlpha, 0.14);
            glass.edgeOpacity = 0.55;
            glass.sheen = 1.0;
            [glass refresh];
        }
        if (glass.superview != tb) {
            glass.layer.zPosition = -2;
            [tb insertSubview:glass atIndex:0];
        }
        if (!CGRectEqualToRect(glass.frame, pill)) {
            glass.frame = pill;
        }

        WXLiquidIndicatorView *ind = objc_getAssociatedObject(tb, kWXIndKey);
        CGFloat ih = MAX(26.0, pill.size.height - 10.0);
        CGFloat iy = pill.origin.y + (pill.size.height - ih) / 2.0;

        if (!ind) {
            ind = [[WXLiquidIndicatorView alloc] initWithFrame:CGRectMake(0, iy, 64, ih)];
            ind.tag = 0x57584743;
            ind.layer.zPosition = -1;
            [tb insertSubview:ind atIndex:0];
            objc_setAssociatedObject(tb, kWXIndKey, ind, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self updateIndicator:tb animated:NO];
        }
        if (ind.superview != tb) {
            ind.layer.zPosition = -1;
            [tb insertSubview:ind atIndex:0];
        }

        CGRect f = ind.frame;
        if (fabs(f.size.height - ih) > 0.5 || fabs(f.origin.y - iy) > 0.5) {
            f.size.height = ih;
            f.origin.y = iy;
            ind.frame = f;
            [ind applyStyle];
        }

        // 只在宽度变化（首次 / 旋转）时重新对齐，避免掐掉液态动画
        NSNumber *lw = objc_getAssociatedObject(tb, &kWXLastWKey);
        if (!lw || fabs(lw.doubleValue - tb.bounds.size.width) > 0.5) {
            objc_setAssociatedObject(tb, &kWXLastWKey, @(tb.bounds.size.width),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [self updateIndicator:tb animated:NO];
        }

        // 玻璃浓度跟随设置
        CGFloat ta = WXPrefFloat(kWXPrefTintAlpha, 0.14);
        if (fabs(glass.tintAlpha - ta) > 0.001) {
            glass.tintAlpha = ta;   // setter 内部会 refresh
        }

        // 文字显隐
        BOOL showLabels = WXPrefBool(kWXPrefShowLabels, YES);
        for (UIView *btn in WXTabButtons(tb)) {
            for (UIView *sub in btn.subviews) {
                if ([sub isKindOfClass:UILabel.class]) {
                    if (sub.hidden == showLabels) sub.hidden = !showLabels;
                }
            }
        }

        // 头像
        [self applyAvatarTo:tb];

        // 选中项轮询（保证指示器能动）
        [self startSelectionPolling:tb];
    } @catch (NSException *e) {
        NSLog(@"[WXFloatBar] style error: %@", e);
    }
    inStyling = NO;
}

#pragma mark 悬浮位置

/// 计算胶囊在 tab bar 内部的位置（不改变 tab bar 自身的 frame）
/// 这是关键：绝不能在布局回调里改 tab bar 的 frame，
/// UITabBarController 每轮布局都会重置它，会形成无限布局循环 -> 主线程卡死。
+ (CGRect)pillRectFor:(UITabBar *)tb {
    CGRect b = tb.bounds;
    if (b.size.width < 100) return CGRectZero;

    CGFloat margin = WXPrefFloat(kWXPrefMargin, 8.0);
    CGFloat wantH  = WXPrefFloat(kWXPrefHeight, 58.0);

    CGFloat safe = 0;
    if (@available(iOS 11.0, *)) safe = tb.safeAreaInsets.bottom;

    CGFloat available = b.size.height - safe;
    CGFloat h = MIN(wantH, available - 4.0);
    if (h < 30.0) h = MIN(wantH, b.size.height);

    CGFloat w = b.size.width - margin * 2.0;
    return CGRectMake(margin, 2.0, w, h);
}

#pragma mark 指示器

+ (void)applyAvatarTo:(UITabBar *)tb {
    NSString *path = WXPrefString(kWXPrefAvatar, nil);
    if (path.length == 0) return;
    UIImage *img = [UIImage imageWithContentsOfFile:path];
    if (!img) return;

    NSArray<UIView *> *btns = WXTabButtons(tb);
    if (btns.count < 4) return;
    UIView *meBtn = btns.lastObject;   // 微信「我」是第 4 个

    UIImageView *iv = nil;
    for (UIView *sub in meBtn.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) { iv = (UIImageView *)sub; break; }
    }
    if (!iv) return;

    UIImage *circle = WXCircularImage(img, 25.0);
    if (circle && iv.image != circle) {
        iv.image = circle;
        iv.contentMode = UIViewContentModeScaleAspectFit;
    }
}

+ (void)updateIndicator:(UITabBar *)tb animated:(BOOL)animated {
    if (!tb) return;
    WXLiquidIndicatorView *ind = objc_getAssociatedObject(tb, kWXIndKey);
    if (!ind) return;

    NSArray<UIView *> *btns = WXTabButtons(tb);
    if (btns.count == 0) return;

    NSInteger sel = 0;
    UITabBarItem *item = tb.selectedItem;
    if (item) {
        NSUInteger i = [tb.items indexOfObject:item];
        if (i != NSNotFound) sel = (NSInteger)i;
    }
    // 优先用 TabBarController 的 selectedIndex（更可靠）
    UIResponder *r = tb;
    while (r && ![r isKindOfClass:UITabBarController.class]) r = r.nextResponder;
    if ([r isKindOfClass:UITabBarController.class]) {
        sel = (NSInteger)((UITabBarController *)r).selectedIndex;
    }
    if (sel < 0 || sel >= (NSInteger)btns.count) sel = 0;

    UIView *btn = btns[sel];
    CGPoint c = [btn.superview convertPoint:btn.center toView:tb];
    CGFloat bw = MAX(56.0, btn.bounds.size.width * 0.86);

    [ind moveToCenterX:c.x width:bw animated:animated];
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
