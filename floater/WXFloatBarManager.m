//
//  WXFloatBarManager.m
//

#import "WXFloatBarManager.h"
#import <objc/runtime.h>

static NSString *const kPosX = @"WXFB_posX";
static NSString *const kPosY = @"WXFB_posY";
static NSString *const kTheme = @"WXFB_theme";          // 偏好域：com.hao.wxfloatbar

/// 用于跨镜像去重（防止 substrate 与 ElleKit 同时加载导致两条胶囊）
static const NSInteger kWXFloatBarTag = 0x57584642; // 'WXFB'

static inline NSString *WXP(NSString *key) {
    return [@"com.hao.wxfloatbar." stringByAppendingString:key];
}

static CGFloat WXPrefFloat(NSString *key, CGFloat def) {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:WXP(key)];
    return n ? n.floatValue : def;
}

static BOOL WXPrefBool(NSString *key, BOOL def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:WXP(key)];
    return v ? [v boolValue] : def;
}

#pragma mark - 悬浮容器

@interface WXFloatBarContainer : UIView
@end

@implementation WXFloatBarContainer
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    // 只让胶囊本身可点，透传其余触摸
    return v == self ? nil : v;
}
@end

#pragma mark - Manager

@interface WXFloatBarManager () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) WXFloatBarContainer *container;
@property (nonatomic, strong, readwrite) WXCapsuleBar *bar;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) BOOL didLayoutOnce;
@property (nonatomic, assign) CGPoint lastPosition;

@end

@implementation WXFloatBarManager

+ (instancetype)shared {
    static WXFloatBarManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [WXFloatBarManager new]; });
    return m;
}

- (instancetype)init {
    if ((self = [super init])) {
        _barSize = CGSizeMake(320, 58);
        _snapToEdges = YES;
        _showTitles = YES;
        _autoHideOnHome = YES;
        [self buildItems];
    }
    return self;
}

- (void)buildItems {
    _items = @[
        @{@"icon": @"square.and.arrow.up", @"title": @"分享"},
        @{@"icon": @"square.and.arrow.down", @"title": @"保存"},
        @{@"icon": @"doc.on.doc", @"title": @"复制"},
        @{@"icon": @"bolt.horizontal.circle", @"title": @"快捷"},
    ];
}

#pragma mark 生命周期

- (UIWindow *)targetWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow && !w.hidden) return w;
        }
    }
    return UIApplication.sharedApplication.keyWindow;
}

- (void)attachToWindow:(UIWindow *)window {
    if (!window) return;

    // 已有一个活的胶囊就复用，避免重复注入出现两条
    for (UIView *v in window.subviews) {
        if (v.tag == kWXFloatBarTag && v != self.container) {
            self.container = (WXFloatBarContainer *)v;
            if (!self.bar) {
                for (UIView *sub in v.subviews) {
                    if ([sub isKindOfClass:WXCapsuleBar.class]) {
                        self.bar = (WXCapsuleBar *)sub;
                        break;
                    }
                }
            }
            self.didLayoutOnce = YES;
            self.container.hidden = NO;
            return;
        }
    }

    self.didLayoutOnce = NO;

    if (!self.container) {
        self.container = [[WXFloatBarContainer alloc] initWithFrame:window.bounds];
        self.container.tag = kWXFloatBarTag;
        self.container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.container.backgroundColor = UIColor.clearColor;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self.container addGestureRecognizer:pan];
    }
    if (self.container.superview != window) {
        [self.container removeFromSuperview];
        [window addSubview:self.container];
        [window bringSubviewToFront:self.container];
    }
    self.container.frame = window.bounds;
    [self reloadSettings];
}

- (void)show {
    [self attachToWindow:[self targetWindow]];
    [self layoutBarIfNeeded];
    self.container.hidden = NO;
}

- (void)hide { self.container.hidden = YES; }

- (void)toggle {
    if ([self isVisible]) [self hide];
    else [self show];
}
- (BOOL)isVisible { return self.container && !self.container.hidden && self.container.window != nil; }

- (void)layoutBarIfNeeded {
    if (self.didLayoutOnce || !self.container) return;
    self.didLayoutOnce = YES;
    // 首次：底部居中，贴近微信输入栏上方
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    CGFloat x = [d objectForKey:kPosX] ? [d floatForKey:kPosX] : CGFLOAT_MAX;
    CGFloat y = [d objectForKey:kPosY] ? [d floatForKey:kPosY] : CGFLOAT_MAX;
    if (x == CGFLOAT_MAX) x = (self.container.bounds.size.width - self.barSize.width) / 2;
    if (y == CGFLOAT_MAX) y = self.container.bounds.size.height - self.barSize.height - 96;
    [self moveBarTo:CGPointMake(x, y) animated:NO];
}

#pragma mark 外观

- (void)reloadSettings {
    WXGlassStyle style = (WXGlassStyle)WXPrefFloat(@"style", 0);
    BOOL showTitles = WXPrefBool(@"showTitles", YES);

    // 只在没有胶囊时才创建，避免刷新设置时位置跳动
    if (!self.bar) {
        self.bar = [[WXCapsuleBar alloc] initWithItems:self.items size:self.barSize];
        __weak typeof(self) weakSelf = self;
        self.bar.onTap = ^(NSInteger idx, UIButton *sender) {
            [weakSelf handleActionAtIndex:idx];
        };
        [self.container addSubview:self.bar];
    }

    WXGlassView *g = self.bar.glass;
    g.style = style;
    g.tintAlpha = WXPrefFloat(@"tintAlpha", 0.10);
    g.edgeOpacity = WXPrefFloat(@"edgeOpacity", 0.55);
    g.sheen = WXPrefFloat(@"sheen", 1.0);
    g.blurRadius = WXPrefFloat(@"blur", 22);
    g.tintColor = (style == WXGlassStyleTint)
        ? [UIColor colorWithRed:0.04 green:0.75 blue:0.28 alpha:1]
        : UIColor.whiteColor;
    [g refresh];

    [self.bar setShowsTitles:showTitles];

    [self.container bringSubviewToFront:self.bar];

    if (self.didLayoutOnce) {
        [self moveBarTo:self.lastPosition animated:NO];
    }
}

#pragma mark 拖动 / 吸附

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (!self.bar) return;
    CGPoint t = [g translationInView:self.container];
    CGRect f = self.bar.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;
    [g setTranslation:CGPointZero inView:self.container];

    // 边界限制
    CGFloat pad = 6;
    CGFloat maxX = self.container.bounds.size.width - f.size.width - pad;
    CGFloat maxY = self.container.bounds.size.height - f.size.height - 8;
    f.origin.x = MAX(pad, MIN(maxX, f.origin.x));
    f.origin.y = MAX(70, MIN(maxY, f.origin.y));
    self.bar.frame = f;

    // 液态高光跟随手指
    CGPoint touch = [g locationInView:self.bar];
    [self.bar driveLiquidWithPoint:touch];

    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            self.dragging = YES;
            [UIView animateWithDuration:0.16 animations:^{
                self.bar.transform = CGAffineTransformMakeScale(1.04, 1.04);
            }];
            break;
        case UIGestureRecognizerStateChanged: {
            // 拖动时轻微倾斜，增加液态手感
            CGFloat v = [g velocityInView:self.container].x;
            CGFloat a = MAX(-0.06, MIN(0.06, v / 6000.0));
            self.bar.transform = CGAffineTransformMakeRotation(a);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            self.dragging = NO;
            [UIView animateWithDuration:0.24 animations:^{ self.bar.transform = CGAffineTransformIdentity; }];
            [self snap:self.bar.frame.origin];
            break;
        }
        default: break;
    }
}

- (void)snap:(CGPoint)p {
    CGFloat pad = 6;
    CGFloat w = self.container.bounds.size.width;
    CGFloat x = p.x;
    if (self.snapToEdges) {
        CGFloat leftDist  = p.x;
        CGFloat rightDist = w - (p.x + self.barSize.width);
        if (leftDist < 60)        x = pad;
        else if (rightDist < 60)  x = w - self.barSize.width - pad;
    }
    [self moveBarTo:CGPointMake(x, p.y) animated:YES];
}

- (void)moveBarTo:(CGPoint)p animated:(BOOL)animated {
    if (!self.bar) return;
    CGRect f = CGRectMake(p.x, p.y, self.barSize.width, self.barSize.height);
    if (animated) {
        [UIView animateWithDuration:0.34 delay:0
             usingSpringWithDamping:0.78 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ self.bar.frame = f; } completion:nil];
    } else {
        self.bar.frame = f;
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setFloat:p.x forKey:kPosX];
    [d setFloat:p.y forKey:kPosY];
    self.lastPosition = p;
}

#pragma mark 点击动作

- (void)handleActionAtIndex:(NSInteger)idx {
    UIButton *b = self.bar.buttons[idx];
    NSString *title = [b titleForState:UIControlStateNormal] ?: @"";

    switch (idx) {
        case 0: [self actionShare]; break;
        case 1: [self actionSave];  break;
        case 2: [self actionCopy];  break;
        default: [self actionShortcut]; break;
    }
    NSLog(@"[WXFloatBar] tap %@", title);
}

- (void)actionShare {
    UIViewController *vc = [self topViewController];
    if (!vc) return;
    UIActivityViewController *a = [[UIActivityViewController alloc] initWithActivityItems:@[] applicationActivities:nil];
    [vc presentViewController:a animated:YES completion:nil];
}

- (void)actionSave { [self toast:@"保存：选择一个元素"]; }
- (void)actionCopy { [self toast:@"复制：选择一个元素"]; }
- (void)actionShortcut { [self toast:@"快捷：选择一个动作"]; }

- (UIViewController *)topViewController {
    UIViewController *vc = [self targetWindow].rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

- (void)toast:(NSString *)t {
    UIWindow *w = [self targetWindow];
    if (!w) return;
    UILabel *l = [UILabel new];
    l.text = t;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    l.layer.cornerRadius = 12;
    l.layer.masksToBounds = YES;
    CGSize s = [t sizeWithAttributes:@{NSFontAttributeName: l.font}];
    CGFloat wd = MIN(s.width + 40, w.bounds.size.width - 60);
    l.frame = CGRectMake((w.bounds.size.width - wd) / 2, w.bounds.size.height - 170, wd, 40);
    [w addSubview:l];
    [UIView animateWithDuration:0.3 delay:1.2 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL f) {
        [l removeFromSuperview];
    }];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    // 只响应落在胶囊上的拖动
    if (!self.bar) return NO;
    CGPoint p = [touch locationInView:self.bar];
    return [self.bar pointInside:p withEvent:nil];
}

@end
