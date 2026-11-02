//
//  WXTabBarStyler.h
//  把微信原生 UITabBar 改成「悬浮椭圆 + 液态滑动指示器」
//
//  设计原则：不替换 Tab 逻辑，只改外观和位置。
//  好处：点击 / 红点 / 切页 / 微信内部逻辑全部保持原生，不会因为改样式而坏掉。
//
//  兼容：iOS 15~16 rootless，arm64 / arm64e
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WXTabBarStyler : NSObject

/// 安装 swizzle（幂等，重复调用安全）
+ (void)install;

/// 外观参数
+ (void)setFloating:(BOOL)floating;
+ (void)setBarHeight:(CGFloat)height;
+ (void)setHorizontalMargin:(CGFloat)margin;
+ (void)setBottomGap:(CGFloat)gap;

@end

NS_ASSUME_NONNULL_END
