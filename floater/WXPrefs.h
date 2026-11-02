//
//  WXPrefs.h
//  配置读写（NSUserDefaults，域 com.hao.wxfloatbar）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const WXPrefDomain;

// 键名
extern NSString *const kWXPrefMargin;      // 左右边距 pt
extern NSString *const kWXPrefHeight;      // 胶囊高度 pt
extern NSString *const kWXPrefTintAlpha;   // 玻璃底色透明度
extern NSString *const kWXPrefBlur;        // 模糊强度
extern NSString *const kWXPrefShowLabels;  // 是否显示文字
extern NSString *const kWXPrefAvatar;      // 头像图片路径（空=不用）

// 读取（带默认值）
CGFloat WXPrefFloat(NSString *key, CGFloat def);
BOOL    WXPrefBool(NSString *key, BOOL def);
NSString *_Nullable WXPrefString(NSString *key, NSString *_Nullable def);
void    WXPrefSetFloat(NSString *key, CGFloat v);
void    WXPrefSetBool(NSString *key, BOOL v);
void    WXPrefSetString(NSString *key, NSString *_Nullable v);

/// 头像图片存储目录（/var/mobile/Library/Preferences 不可写时回退到 tmp）
NSString *WXAvatarStorePath(void);

NS_ASSUME_NONNULL_END
