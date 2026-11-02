//
//  WXTabBarStyler.m
//

#import "WXTabBarStyler.h"
#import "WXGlassView.h"
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
    CGFloat h = self.bounds.size.height;
    CGRect target = CGRectMake(x - w / 2.0, (self.superview.bounds.size.height - h) / 2.0, w, h);

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
    shine.frame = CGRectMake(-w * 0.5, 0, w * 0.5, h);
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
        WXSwizzle([UITabBar class], @selector(layoutSubviews), @selector(wx_layoutSubviews));
        WXSwizzle([UITabBarController class], @selector(viewDidLayoutSubviews), @selector(wx_viewDidLayoutSubviews));
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
        NSLog(@"[WXFloatBar] tab bar styler installed");
    });
}

+ (void)rescanInView:(UIView *)root {
    if (!root) return;
    if ([root isKindOfClass:UITabBar.class]) {
        [self styleTabBar:(UITabBar *)root];
        return;
    }
    for (UIView *s in root.subviews) [self rescanInView:s];
}

#pragma mark 外观

+ (void)styleTabBar:(UITabBar *)tb {
    if (!WXIsWeChat() || !tb) return;
    if (tb.bounds.size.width < 100) return;

    // 1. 抹掉系统背景与分割线
    @try {
        tb.backgroundImage = [UIImage new];
        tb.shadowImage = [UIImage new];
        tb.backgroundColor = UIColor.clearColor;
        tb.translucent = YES;
        if ([tb respondsToSelector:@selector(setBarStyle:)]) tb.barStyle = UIBarStyleDefault;
    } @catch (NSException *e) {}

    for (UIView *v in tb.subviews) {
        NSString *cn = NSStringFromClass(v.class);
        if ([cn containsString:@"BarBackground"] || [cn containsString:@"BackgroundView"]) {
            v.hidden = YES;
        }
    }

    // 2. 玻璃底层（只建一次，复用）
    WXGlassView *glass = objc_getAssociatedObject(tb, kWXGlassKey);
    if (!glass) {
        glass = [[WXGlassView alloc] initWithFrame:tb.bounds];
        glass.userInteractionEnabled = NO;
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        glass.tag = 0x57584742;
        [tb insertSubview:glass atIndex:0];
        objc_setAssociatedObject(tb, kWXGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        glass.style = WXGlassStyleFrost;
        glass.tintColor = UIColor.whiteColor;
        glass.tintAlpha = 0.14;
        glass.edgeOpacity = 0.55;
        glass.sheen = 1.0;
        [glass refresh];
    }
    glass.frame = tb.bounds;
    if (glass.superview != tb || [tb.subviews indexOfObject:glass] != 0) {
        [tb insertSubview:glass atIndex:0];
    }

    // 3. 圆角（椭圆/胶囊）
    tb.layer.cornerRadius = tb.bounds.size.height / 2.0;
    tb.layer.cornerCurve = kCACornerCurveContinuous;
    tb.layer.masksToBounds = NO;
    tb.clipsToBounds = NO;
    tb.layer.shadowColor = UIColor.blackColor.CGColor;
    tb.layer.shadowOpacity = 0.16;
    tb.layer.shadowRadius = 18;
    tb.layer.shadowOffset = CGSizeMake(0, 8);

    // 4. 液态指示器
    WXLiquidIndicatorView *ind = objc_getAssociatedObject(tb, kWXIndKey);
    if (!ind) {
        CGFloat ih = MAX(28.0, tb.bounds.size.height - 14.0);
        ind = [[WXLiquidIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 64, ih)];
        ind.tag = 0x57584743;
        [tb insertSubview:ind atIndex:1];
        objc_setAssociatedObject(tb, kWXIndKey, ind, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat ih = MAX(28.0, tb.bounds.size.height - 14.0);
    CGRect f = ind.frame;
    if (fabs(f.size.height - ih) > 0.5) {
        f.size.height = ih;
        f.origin.y = (tb.bounds.size.height - ih) / 2.0;
        ind.frame = f;
        [ind applyStyle];
    }
    if (ind.superview != tb) {
        [tb addSubview:ind];
    }
    NSUInteger idx = [tb.subviews indexOfObject:ind];
    if (idx != NSNotFound && idx > 1 && tb.subviews.count >= 2) {
        [tb insertSubview:ind atIndex:1];
    }

    // 只在首次 / 尺寸变化时对齐位置。每次布局都对齐会把液态动画直接掐掉。
    NSNumber *lw = objc_getAssociatedObject(tb, &kWXLastWKey);
    if (!lw || fabs(lw.doubleValue - tb.bounds.size.width) > 0.5) {
        objc_setAssociatedObject(tb, &kWXLastWKey, @(tb.bounds.size.width),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self updateIndicator:tb animated:NO];
    }
}

#pragma mark 悬浮位置

+ (void)floatTabBar:(UITabBar *)tb inController:(UITabBarController *)vc {
    if (!WXIsWeChat() || !tb || !vc) return;
    if (!gFloating) return;

    UIView *root = vc.view;
    CGRect b = root.bounds;
    if (b.size.width < 100 || b.size.height < 200) return;

    CGFloat safeBottom = root.safeAreaInsets.bottom;
    CGFloat h = gBarHeight;
    CGFloat w = b.size.width - gHMargin * 2.0;
    CGFloat x = gHMargin;
    CGFloat y = b.size.height - safeBottom - h - gBottomGap;

    CGRect target = CGRectMake(x, y, w, h);
    if (!CGRectEqualToRect(tb.frame, target)) {
        tb.frame = target;
    }
}

#pragma mark 指示器

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
- (void)wx_layoutSubviews;
- (void)wx_setSelectedItem:(UITabBarItem *)item;
@end

@implementation UITabBar (WXHook)

- (void)wx_layoutSubviews {
    [self wx_layoutSubviews];          // 原实现
    [WXTabBarStyler styleTabBar:self];
}

- (void)wx_setSelectedItem:(UITabBarItem *)item {
    [self wx_setSelectedItem:item];    // 原实现
    [WXTabBarStyler updateIndicator:self animated:YES];
}

@end

#pragma mark - Hook：UITabBarController

@interface UITabBarController (WXHook)
- (void)wx_viewDidLayoutSubviews;
- (void)wx_setSelectedIndex:(NSUInteger)index;
@end

@implementation UITabBarController (WXHook)

- (void)wx_viewDidLayoutSubviews {
    [self wx_viewDidLayoutSubviews];   // 原实现
    [WXTabBarStyler floatTabBar:self.tabBar inController:self];
}

- (void)wx_setSelectedIndex:(NSUInteger)index {
    [self wx_setSelectedIndex:index];  // 原实现
    [WXTabBarStyler updateIndicator:self.tabBar animated:YES];
}

@end
