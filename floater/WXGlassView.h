//
//  WXGlassView.h
//  WXFloatBar —— 微信真液态玻璃悬浮胶囊
//  可被独立进程（TrollStore 输入器）注入，不引用微信符号
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WXGlassStyle) {
    WXGlassStyleClear = 0,   // 通透（最亮）
    WXGlassStyleFrost,       // 磨砂
    WXGlassStyleTint,        // 染色（跟随微信绿）
};

@interface WXGlassView : UIView

@property (nonatomic, assign) CGFloat blurRadius;        // 默认 22
@property (nonatomic, assign) CGFloat tintAlpha;         // 玻璃底色透明度 默认 0.10
@property (nonatomic, assign) CGFloat edgeOpacity;       // 高光描边强度 默认 0.55
@property (nonatomic, strong) UIColor *tintColor;        // 染色
@property (nonatomic, assign) WXGlassStyle style;

/// 渐变遮罩强度：0 = 均匀，1 = 顶部亮底部暗
@property (nonatomic, assign) CGFloat sheen;

- (void)refresh;

@end

@interface WXCapsuleBar : UIView

@property (nonatomic, strong, readonly) WXGlassView *glass;
@property (nonatomic, strong, readonly) NSArray<UIButton *> *buttons;
/// 点击回调，index 从 0 开始
@property (nonatomic, copy) void (^onTap)(NSInteger index, UIButton *sender);

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items size:(CGSize)size;
/// 滑动高光动效：在按钮位置触发一次液态波纹
- (void)pulseAtButtonIndex:(NSInteger)index;

/// 拖动时把液态高光跟随到某个点（点在 WXCapsuleBar 坐标系）
- (void)driveLiquidWithPoint:(CGPoint)pointInSelf;

/// 显示/隐藏按钮文字
- (void)setShowsTitles:(BOOL)show;

@end

NS_ASSUME_NONNULL_END
