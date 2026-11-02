//
//  WXGlassView.m
//  液态玻璃实现：
//  1. 真实背景模糊（UIVisualEffectView）
//  2. 渐变折射层：CAGradientLayer + 极薄边缘亮线，模拟玻璃高光
//  3. 液态追踪层：滑动时一个高光团跟着手指移动（"液态"感）
//  4. 点击波纹：CABasicAnimation 缩放 + 透明度扩散
//

#import "WXGlassView.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - 液态高光层

@interface WXSheenLayer : CALayer
@property (nonatomic, assign) CGFloat sheenAmount;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) CAGradientLayer *edge;
@property (nonatomic, strong) CALayer *specular;      // 顶部高光条
@property (nonatomic, strong) CAShapeLayer *liquid;    // 液态追踪高光

- (void)setLiquidCenterX:(CGFloat)x;
- (void)flashLiquid;
- (void)rippleAt:(CGPoint)point;
@end

@implementation WXSheenLayer

- (instancetype)init {
    if ((self = [super init])) {
        self.masksToBounds = YES;

        _gradient = [CAGradientLayer layer];
        _gradient.startPoint = CGPointMake(0.5, 0.0);
        _gradient.endPoint   = CGPointMake(0.5, 1.0);
        _gradient.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.30].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.00].CGColor,
        ];
        _gradient.locations = @[@0.0, @0.45, @1.0];
        [self addSublayer:_gradient];

        // 顶部一条 1px 亮线，是"玻璃感"最关键的细节
        _specular = [CALayer layer];
        _specular.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85].CGColor;
        _specular.opacity = 0.9;
        [self addSublayer:_specular];

        // 液态追踪团
        _liquid = [CAShapeLayer layer];
        _liquid.fillColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
        _liquid.opacity = 0;
        [self addSublayer:_liquid];

        // 边缘描边
        _edge = [CAGradientLayer layer];
        _edge.colors = @[
            (id)[UIColor colorWithWhite:1 alpha:0.95].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.18].CGColor,
            (id)[UIColor colorWithWhite:1 alpha:0.65].CGColor,
        ];
        _edge.startPoint = CGPointMake(0, 0);
        _edge.endPoint   = CGPointMake(1, 1);
        [self addSublayer:_edge];
    }
    return self;
}

- (void)setSheenAmount:(CGFloat)sheenAmount {
    _sheenAmount = sheenAmount;
    [self setNeedsLayout];
}

- (void)layoutSublayers {
    [super layoutSublayers];

    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat r = MIN(w, h) / 2.0;
    self.cornerRadius = r;
    self.cornerCurve = kCACornerCurveContinuous;

    _gradient.frame = self.bounds;
    _gradient.cornerRadius = r;

    _specular.frame = CGRectMake(w * 0.18, 0.7, w * 0.64, 0.8);
    _specular.cornerRadius = 0.4;

    CGFloat outerR = r - 0.5;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 0.5, 0.5)
                                                    cornerRadius:outerR];
    _edge.frame = self.bounds;
    _edge.cornerRadius = r;
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.path = path.CGPath;
    mask.fillColor = UIColor.clearColor.CGColor;
    mask.strokeColor = UIColor.blackColor.CGColor;
    mask.lineWidth = 1.0;
    _edge.mask = mask;

    // 液态团半径随高度
    CGFloat lr = h * 0.85;
    _liquid.bounds = CGRectMake(0, 0, lr * 2, lr * 2);
    _liquid.position = CGPointMake(_liquid.position.x ?: w / 2, h / 2);
    _liquid.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, lr * 2, lr * 2)].CGPath;
}

- (void)setLiquidCenterX:(CGFloat)x {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.32];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithControlPoints:0.22 :1.0 :0.36 :1.0]];
    _liquid.position = CGPointMake(x, self.bounds.size.height / 2);
    [CATransaction commit];
}

- (void)flashLiquid {
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.0;
    fade.toValue   = @1.0;
    fade.duration  = 0.18;
    fade.autoreverses = YES;
    _liquid.opacity = 1.0;
    [_liquid addAnimation:fade forKey:@"liquidFlash"];
    _liquid.opacity = 0.0;
}

- (void)rippleAt:(CGPoint)point {
    CAShapeLayer *ring = [CAShapeLayer layer];
    CGFloat d = self.bounds.size.height;
    ring.frame = CGRectMake(0, 0, d, d);
    ring.position = point;
    ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, d, d)].CGPath;
    ring.fillColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
    ring.opacity = 0;
    [self addSublayer:ring];

    CABasicAnimation *s = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    s.fromValue = @0.25; s.toValue = @2.4;
    CABasicAnimation *o = [CABasicAnimation animationWithKeyPath:@"opacity"];
    o.fromValue = @0.85; o.toValue = @0.0;
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[s, o];
    g.duration = 0.52;
    g.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    g.removedOnCompletion = NO;
    g.fillMode = kCAFillModeForwards;
    [ring addAnimation:g forKey:@"ripple"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [ring removeFromSuperlayer]; });
}

@end

#pragma mark - WXGlassView

@interface WXGlassView ()
@property (nonatomic, strong) UIVisualEffectView *blur;
@property (nonatomic, strong) WXSheenLayer *sheenLayer;
@property (nonatomic, strong) CAGradientLayer *tintLayer;
- (void)rippleAtPoint:(CGPoint)p;
- (void)slideLiquidToX:(CGFloat)x;
@end


@implementation WXGlassView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _blurRadius = 22;
    _tintAlpha = 0.10;
    _edgeOpacity = 0.55;
    _sheen = 1.0;
    _style = WXGlassStyleClear;
    _tintColor = [UIColor colorWithRed:0.04 green:0.75 blue:0.28 alpha:1];

    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = NO;
    self.backgroundColor = UIColor.clearColor;

    _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight]];
    _blur.clipsToBounds = YES;
    _blur.userInteractionEnabled = NO;
    [self addSubview:_blur];

    _tintLayer = [CAGradientLayer layer];
    _tintLayer.startPoint = CGPointMake(0, 0);
    _tintLayer.endPoint   = CGPointMake(1, 1);
    [self.layer addSublayer:_tintLayer];

    _sheenLayer = [WXSheenLayer layer];
    [self.layer addSublayer:_sheenLayer];

    // 注意：这里不挂 pan。拖动由 WXFloatBarManager 的容器手势统一驱动，
    // 否则两个 UIPanGestureRecognizer 会互相抢手势，导致胶囊拖不动。

    [self refresh];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat r = MIN(self.bounds.size.width, self.bounds.size.height) / 2.0;
    self.layer.cornerRadius = r;
    _blur.frame = self.bounds;
    _blur.layer.cornerRadius = r;
    _blur.layer.cornerCurve = kCACornerCurveContinuous;
    _tintLayer.frame = self.bounds;
    _tintLayer.cornerRadius = r;
    _sheenLayer.frame = self.bounds;
    [self applyShadow];
}

- (void)applyShadow {
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = 0.18;
    self.layer.shadowRadius = 16;
    self.layer.shadowOffset = CGSizeMake(0, 8);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                     cornerRadius:self.bounds.size.height / 2].CGPath;
}

- (void)refresh {
    CGFloat a = self.tintAlpha;
    switch (self.style) {
        case WXGlassStyleClear: a = MAX(0.02, self.tintAlpha * 0.5); break;
        case WXGlassStyleFrost: a = MAX(0.16, self.tintAlpha);       break;
        case WXGlassStyleTint:  a = MAX(0.12, self.tintAlpha);       break;
    }
    _tintLayer.colors = @[
        (id)[self.tintColor colorWithAlphaComponent:a * 0.7].CGColor,
        (id)[self.tintColor colorWithAlphaComponent:a * 0.25].CGColor,
        (id)[UIColor colorWithWhite:1 alpha:a * 0.35].CGColor,
    ];

    UIBlurEffectStyle s = (self.style == WXGlassStyleClear)
        ? UIBlurEffectStyleSystemUltraThinMaterialLight
        : (self.style == WXGlassStyleFrost
           ? UIBlurEffectStyleSystemThinMaterialLight
           : UIBlurEffectStyleSystemMaterialLight);
    _blur.effect = [UIBlurEffect effectWithStyle:s];

    _sheenLayer.sheenAmount = self.sheen;
    _sheenLayer.edge.opacity = self.edgeOpacity;
}

- (void)setStyle:(WXGlassStyle)style {
    _style = style;
    [self refresh];
}

- (void)setTintAlpha:(CGFloat)tintAlpha {
    _tintAlpha = tintAlpha;
    [self refresh];
}

- (void)setEdgeOpacity:(CGFloat)edgeOpacity {
    _edgeOpacity = edgeOpacity;
    _sheenLayer.edge.opacity = edgeOpacity;
}

#pragma mark 液态滑动

- (void)rippleAtPoint:(CGPoint)p {
    [_sheenLayer rippleAt:p];
}

- (void)slideLiquidToX:(CGFloat)x {
    [_sheenLayer setLiquidCenterX:x];
    [_sheenLayer flashLiquid];
}

@end

#pragma mark - WXCapsuleBar

@interface WXCapsuleBar ()
@property (nonatomic, strong) WXGlassView *glass;
@property (nonatomic, strong) NSMutableArray<UIButton *> *btns;
@property (nonatomic, strong) NSArray<NSDictionary *> *defs;
@property (nonatomic, assign) BOOL showsTitles;
@property (nonatomic, strong) UIVisualEffectView *sep;
@end

@implementation WXCapsuleBar

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items size:(CGSize)size {
    if ((self = [super initWithFrame:CGRectMake(0, 0, size.width, size.height)])) {
        self.backgroundColor = UIColor.clearColor;
        _defs = items;
        _showsTitles = YES;

        _glass = [[WXGlassView alloc] initWithFrame:self.bounds];
        _glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_glass];

        _btns = [NSMutableArray array];
        NSUInteger n = MAX(items.count, 1);
        CGFloat w = (size.width - 8.0) / n;
        CGFloat h = size.height - 8.0;

        for (NSUInteger i = 0; i < items.count; i++) {
            NSDictionary *it = items[i];
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(4.0 + w * i, 4.0, w, h);
            b.tag = i;
            b.adjustsImageWhenHighlighted = NO;
            b.layer.cornerRadius = h / 2;
            b.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];

            NSString *symbol = it[@"icon"];
            NSString *title  = it[@"title"];
            if (![title isKindOfClass:NSString.class] || title.length == 0) title = @"";

            UIImage *img = nil;
            if (@available(iOS 13.0, *)) {
                img = [UIImage systemImageNamed:symbol ?: @""];
            }
            [b setImage:img forState:UIControlStateNormal];
            b.tintColor = [UIColor colorWithWhite:0.12 alpha:0.92];
            [b setTitle:title forState:UIControlStateNormal];
            [b setTitleColor:[UIColor colorWithWhite:0.12 alpha:0.92] forState:UIControlStateNormal];

            // 图标在上、文字在下（用垂直布局）
            b.imageEdgeInsets = UIEdgeInsetsMake(-9, 0, 0, 0);
            b.titleEdgeInsets = UIEdgeInsetsMake(13, -img.size.width, 0, 0);

            [b addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:b];
            [_btns addObject:b];
        }
    }
    return self;
}

- (NSArray<UIButton *> *)buttons { return _btns.copy; }

- (void)tap:(UIButton *)b {
    CGPoint c = [self convertPoint:b.center toView:self];
    [_glass rippleAtPoint:c];
    if (self.onTap) self.onTap(b.tag, b);
}

- (void)pulseAtButtonIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_btns.count) return;
    [_glass rippleAtPoint:_btns[index].center];
    [_glass slideLiquidToX:_btns[index].center.x];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _glass.frame = self.bounds;

    // 尺寸变化时按比例重排按钮（胶囊被拉伸/压缩时要跟着变）
    NSUInteger n = MAX(_btns.count, 1);
    CGFloat w = (self.bounds.size.width - 8.0) / n;
    CGFloat h = self.bounds.size.height - 8.0;
    for (NSUInteger i = 0; i < _btns.count; i++) {
        UIButton *b = _btns[i];
        b.frame = CGRectMake(4.0 + w * i, 4.0, w, h);
        b.layer.cornerRadius = h / 2.0;
    }
}

/// 拖动时由管理器驱动液态高光
- (void)driveLiquidWithPoint:(CGPoint)pointInSelf {
    CGPoint p = [self convertPoint:pointInSelf toView:_glass];
    [_glass slideLiquidToX:p.x];
}

- (void)setShowsTitles:(BOOL)show {
    _showsTitles = show;
    for (NSUInteger i = 0; i < _btns.count; i++) {
        UIButton *b = _btns[i];
        NSString *title = @"";
        if (show && i < _defs.count) {
            id t = _defs[i][@"title"];
            if ([t isKindOfClass:NSString.class]) title = t;
        }
        [b setTitle:title forState:UIControlStateNormal];
        if (show) {
            CGSize is = b.currentImage.size;
            b.imageEdgeInsets = UIEdgeInsetsMake(-9, 0, 0, 0);
            b.titleEdgeInsets = UIEdgeInsetsMake(13, -is.width, 0, 0);
        } else {
            b.imageEdgeInsets = UIEdgeInsetsZero;
            b.titleEdgeInsets = UIEdgeInsetsZero;
        }
    }
}

@end
