//
//  WXSettingsController.m
//

#import "WXSettingsController.h"
#import "WXPrefs.h"
#import "WXTabBarStyler.h"
#import <PhotosUI/PhotosUI.h>
#import <objc/runtime.h>

static const void *kWXLongPressKey = &kWXLongPressKey;
static const void *kWXSliderBlock  = &kWXSliderBlock;
static const void *kWXSliderValue  = &kWXSliderValue;
static const void *kWXSliderUnit   = &kWXSliderUnit;
static const void *kWXSwitchBlock  = &kWXSwitchBlock;

#pragma mark - 面板

@interface WXSettingsController () <PHPickerViewControllerDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIStackView *stack;
@end

@implementation WXSettingsController

#pragma mark 长按安装

+ (void)installLongPressOnView:(UIView *)view {
    if (!view) return;
    if (objc_getAssociatedObject(view, kWXLongPressKey)) return;

    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.6;
    lp.cancelsTouchesInView = NO;   // 不影响正常点击切 tab
    lp.delaysTouchesEnded = NO;
    [view addGestureRecognizer:lp];
    objc_setAssociatedObject(view, kWXLongPressKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    [self present];
}

+ (UIViewController *)topViewController {
    UIWindow *w = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *win in ((UIWindowScene *)sc).windows) {
            if (win.isKeyWindow && !win.hidden) { w = win; break; }
        }
        if (w) break;
    }
    if (!w) w = UIApplication.sharedApplication.keyWindow;

    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)present {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topViewController];
        if (!top) return;
        if ([top isKindOfClass:WXSettingsController.class]) return;
        if ([top isKindOfClass:UINavigationController.class] &&
            [((UINavigationController *)top).topViewController isKindOfClass:WXSettingsController.class]) {
            return;
        }

        WXSettingsController *c = [WXSettingsController new];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:c];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        @try {
            [top presentViewController:nav animated:YES completion:nil];
        } @catch (NSException *e) {
            NSLog(@"[WXFloatBar] present settings failed: %@", e);
        }
    });
}

#pragma mark 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WXFloatBar";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"完成"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(dismissSelf)];

    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 8;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    UILayoutGuide *g = _scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:16],
        [_stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-24],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.leadingAnchor constant:16],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.trailingAnchor constant:-16],
    ]];

    [self buildUI];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark 构件

- (UIView *)card {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    v.layer.cornerRadius = 12;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}

- (UIView *)cardRow:(UIView *)content {
    UIView *card = [self card];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [content.topAnchor constraintEqualToAnchor:card.topAnchor constant:8],
        [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8],
    ]];
    return card;
}

- (UILabel *)sectionTitle:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    l.textColor = UIColor.secondaryLabelColor;
    return l;
}

- (void)buildUI {
    // ===== 头部 / 署名 =====
    UILabel *title = [UILabel new];
    title.text = @"WXFloatBar";
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];

    UILabel *author = [UILabel new];
    author.text = @"液态玻璃悬浮底栏 · by hao";
    author.font = [UIFont systemFontOfSize:13];
    author.textColor = UIColor.secondaryLabelColor;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, author]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 4;
    [self.stack addArrangedSubview:header];

    // ===== 外观 =====
    [self.stack addArrangedSubview:[self sectionTitle:@"外观"]];

    [self addSliderTitle:@"左右边距"
                     min:0 max:30
                   value:WXPrefFloat(kWXPrefMargin, 8)
                    unit:@"pt"
                   block:^(CGFloat v) {
        WXPrefSetFloat(kWXPrefMargin, v);
        [WXTabBarStyler rescan];
    }];

    [self addSliderTitle:@"胶囊高度"
                     min:40 max:80
                   value:WXPrefFloat(kWXPrefHeight, 58)
                    unit:@"pt"
                   block:^(CGFloat v) {
        WXPrefSetFloat(kWXPrefHeight, v);
        [WXTabBarStyler rescan];
    }];

    [self addSliderTitle:@"玻璃浓度"
                     min:0.02 max:0.6
                   value:WXPrefFloat(kWXPrefTintAlpha, 0.14)
                    unit:@""
                   block:^(CGFloat v) {
        WXPrefSetFloat(kWXPrefTintAlpha, v);
        [WXTabBarStyler rescan];
    }];

    [self addSwitchTitle:@"显示文字"
                      on:WXPrefBool(kWXPrefShowLabels, YES)
                   block:^(BOOL on) {
        WXPrefSetBool(kWXPrefShowLabels, on);
        [WXTabBarStyler rescan];
    }];

    // ===== 头像 =====
    [self.stack addArrangedSubview:[self sectionTitle:@"头像（底栏「我」）"]];
    [self addAvatarCard];

    // ===== 重置 =====
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    reset.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    reset.layer.cornerRadius = 12;
    [reset.heightAnchor constraintEqualToConstant:48].active = YES;
    [reset addTarget:self action:@selector(resetAll) forControlEvents:UIControlEventTouchUpInside];
    [self.stack addArrangedSubview:reset];

    UILabel *hint = [UILabel new];
    hint.text = @"改完立即生效 · 长按底栏随时打开本面板";
    hint.font = [UIFont systemFontOfSize:12];
    hint.textColor = UIColor.tertiaryLabelColor;
    hint.textAlignment = NSTextAlignmentCenter;
    [self.stack addArrangedSubview:hint];

    // ===== 作者署名 =====
    UILabel *sign = [UILabel new];
    sign.text = @"作者：hao";
    sign.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    sign.textColor = UIColor.secondaryLabelColor;
    sign.textAlignment = NSTextAlignmentCenter;
    sign.numberOfLines = 0;

    UILabel *ver = [UILabel new];
    ver.text = @"WXFloatBar 2.2.0";
    ver.font = [UIFont systemFontOfSize:11];
    ver.textColor = UIColor.tertiaryLabelColor;
    ver.textAlignment = NSTextAlignmentCenter;

    UIStackView *foot = [[UIStackView alloc] initWithArrangedSubviews:@[sign, ver]];
    foot.axis = UILayoutConstraintAxisVertical;
    foot.spacing = 3;
    foot.layoutMargins = UIEdgeInsetsMake(24, 0, 0, 0);
    foot.layoutMarginsRelativeArrangement = YES;
    [self.stack addArrangedSubview:foot];
}

#pragma mark 滑块

- (void)addSliderTitle:(NSString *)title
                   min:(CGFloat)min
                   max:(CGFloat)max
                 value:(CGFloat)value
                  unit:(NSString *)unit
                 block:(void (^)(CGFloat))block {
    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:15];

    UILabel *val = [UILabel new];
    val.text = unit.length ? [NSString stringWithFormat:@"%.0f %@", value, unit]
                           : [NSString stringWithFormat:@"%.2f", value];
    val.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    val.textColor = UIColor.secondaryLabelColor;
    val.textAlignment = NSTextAlignmentRight;

    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[name, val]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.distribution = UIStackViewDistributionEqualSpacing;

    UISlider *slider = [UISlider new];
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];

    objc_setAssociatedObject(slider, kWXSliderBlock, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kWXSliderValue, val, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, kWXSliderUnit, unit ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[top, slider]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 6;

    [self.stack addArrangedSubview:[self cardRow:col]];
}

- (void)sliderChanged:(UISlider *)s {
    void (^blk)(CGFloat) = objc_getAssociatedObject(s, kWXSliderBlock);
    UILabel *val = objc_getAssociatedObject(s, kWXSliderValue);
    NSString *unit = objc_getAssociatedObject(s, kWXSliderUnit);
    val.text = unit.length ? [NSString stringWithFormat:@"%.0f %@", s.value, unit]
                           : [NSString stringWithFormat:@"%.2f", s.value];
    if (blk) blk(s.value);
}

#pragma mark 开关

- (void)addSwitchTitle:(NSString *)title on:(BOOL)on block:(void (^)(BOOL))block {
    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:15];

    UISwitch *sw = [UISwitch new];
    sw.on = on;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(sw, kWXSwitchBlock, [block copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[name, sw]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionEqualSpacing;
    row.alignment = UIStackViewAlignmentCenter;

    [self.stack addArrangedSubview:[self cardRow:row]];
}

- (void)switchChanged:(UISwitch *)s {
    void (^blk)(BOOL) = objc_getAssociatedObject(s, kWXSwitchBlock);
    if (blk) blk(s.isOn);
}

#pragma mark 头像

- (void)addAvatarCard {
    UILabel *name = [UILabel new];
    name.text = @"选择照片";
    name.font = [UIFont systemFontOfSize:15];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"选择" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(chooseAvatar) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[name, btn]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionEqualSpacing;
    row.alignment = UIStackViewAlignmentCenter;

    [self.stack addArrangedSubview:[self cardRow:row]];

    UILabel *tip = [UILabel new];
    tip.text = @"想用自己的微信头像：在微信里点左上角头像 → 保存到相册，再回来这里选择。";
    tip.font = [UIFont systemFontOfSize:11.5];
    tip.textColor = UIColor.tertiaryLabelColor;
    tip.numberOfLines = 0;
    [self.stack addArrangedSubview:tip];
}

- (void)chooseAvatar {
    @try {
        PHPickerConfiguration *cfg = [PHPickerConfiguration new];
        cfg.filter = PHPickerFilter.imagesFilter;
        cfg.selectionLimit = 1;
        PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        p.delegate = self;
        [self presentViewController:p animated:YES completion:nil];
    } @catch (NSException *e) {
        NSLog(@"[WXFloatBar] picker failed: %@", e);
    }
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    NSItemProvider *item = results.firstObject.itemProvider;
    if (![item canLoadObjectOfClass:UIImage.class]) return;

    __weak typeof(self) weakSelf = self;
    [item loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
        UIImage *img = (UIImage *)obj;
        if (![img isKindOfClass:UIImage.class]) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf saveAvatar:img]; });
    }];
}

- (void)saveAvatar:(UIImage *)image {
    if (!image.CGImage) return;

    // 居中裁成正方形 -> 120x120 -> PNG
    CGFloat side = MIN(image.size.width, image.size.height);
    CGFloat sx = (image.size.width  - side) / 2.0 * image.scale;
    CGFloat sy = (image.size.height - side) / 2.0 * image.scale;
    CGRect src = CGRectMake(sx, sy, side * image.scale, side * image.scale);

    UIImage *square = image;
    CGImageRef cg = CGImageCreateWithImageInRect(image.CGImage, src);
    if (cg) {
        square = [UIImage imageWithCGImage:cg scale:image.scale orientation:image.imageOrientation];
        CGImageRelease(cg);
    }

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(120, 120), NO, 1.0);
    [square drawInRect:CGRectMake(0, 0, 120, 120)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    NSData *png = UIImagePNGRepresentation(out);
    NSString *path = WXAvatarStorePath();
    if (png && [png writeToFile:path atomically:YES]) {
        WXPrefSetString(kWXPrefAvatar, path);
        [WXTabBarStyler rescan];

        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已应用"
                                                                  message:@"头像已设到底栏「我」"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else {
        NSLog(@"[WXFloatBar] avatar write failed: %@", path);
    }
}

#pragma mark 重置

- (void)resetAll {
    WXPrefSetFloat(kWXPrefMargin, 8);
    WXPrefSetFloat(kWXPrefHeight, 58);
    WXPrefSetFloat(kWXPrefTintAlpha, 0.14);
    WXPrefSetBool(kWXPrefShowLabels, YES);
    WXPrefSetString(kWXPrefAvatar, nil);
    [WXTabBarStyler rescan];
    [self dismissSelf];
}

@end
