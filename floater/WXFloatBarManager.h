//
//  WXFloatBarManager.h
//  悬浮底栏总控：挂载 / 拖拽吸附 / 位置持久化 / 输入器注入
//

#import <UIKit/UIKit.h>
#import "WXGlassView.h"

NS_ASSUME_NONNULL_BEGIN

@interface WXFloatBarManager : NSObject

+ (instancetype)shared;

/// 气泡宽高（默认 320x58），改完需重挂载
@property (nonatomic, assign) CGSize barSize;

/// 自动吸附到左右边缘（默认 YES）
@property (nonatomic, assign) BOOL snapToEdges;

/// 是否显示文字
@property (nonatomic, assign) BOOL showTitles;

/// 退出微信会话时自动收起
@property (nonatomic, assign) BOOL autoHideOnHome;

@property (nonatomic, strong, readonly, nullable) WXCapsuleBar *bar;

- (void)show;
- (void)hide;
- (void)toggle;
- (BOOL)isVisible;

/// 重新读取设置并刷新外观
- (void)reloadSettings;

/// 供输入器进程调用：直接在指定 window 上挂载
- (void)attachToWindow:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
