//
//  WXSettingsController.h
//  长按底栏打开的内嵌设置面板（不依赖 PreferenceLoader）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WXSettingsController : UIViewController

/// 从当前界面弹出面板
+ (void)present;

/// 给 tab bar 装长按手势（幂等）
+ (void)installLongPressOnView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
