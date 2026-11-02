# WXFloatBar

微信液态玻璃悬浮底栏 · rootless (Dopamine) / 可被 TrollStore 输入器注入

![预览](preview.html)

## 效果

一条 320×58 的半透明胶囊浮在微信会话界面上方：

- **真实背景模糊** — `UIVisualEffectView`，能看到底下聊天气泡透过玻璃的折射
- **液态高光** — 拖动时一团柔光跟随手指水平移动，松手回到静止
- **点击波纹** — 点任一按钮，从触点扩散一圈涟漪
- **镜面描边** — 顶部 1px 渐变亮线 + 内阴影，玻璃厚度感
- **拖拽吸附** — 拖到左右边缘 60pt 内自动吸边，位置记忆到 NSUserDefaults
- **拖拽倾斜** — 拖动时按速度轻微旋转，松手回弹

## 目录

```
floater/
  WXGlassView.h/.m        玻璃渲染 + 胶囊按钮（纯 UI，无微信依赖）
  WXFloatBarManager.h/.m  挂载 / 拖拽 / 吸附 / 位置持久化 / 业务动作
  WXInjector.m            constructor 注入入口，自动等 window 就绪
build.sh                  编译 dylib + 打包 deb（需 macOS + Xcode）
pack_deb.py               纯 Python 打 deb，不依赖 dpkg-deb
preview.html              1:1 视觉预览（Safari 打开即可）
control                   deb 控制信息
Makefile                  Theos 备选构建方式
```

## 安装方式

### A. Dopamine 隐根（推荐）

产物：`com.hao.wxfloatbar_1.0.0_iphoneos-arm64.deb`

1. 用 **Filza** 或 **Sileo** 打开 deb
2. 安装后**手动杀掉微信**（不要只是切后台，要从多任务上划掉）
3. 重开微信，进入任意聊天窗口
4. 胶囊出现在输入栏上方，**按住胶囊可以拖**

包内落点：`/var/jb/Library/MobileSubstrate/DynamicLibraries/`

### B. TrollStore 输入器注入

产物：`WXFloatBar.dylib`

1. 用输入器工具把 `WXFloatBar.dylib` 注入到微信
2. 重新签名微信后启动

> ⚠️ 注意：App Store 装的微信签名是 Apple 的，直接改 bundle 会导致签名失效。
> 通常需要把微信重装成 **TrollStore 版本**（用自己的 IPA 通过 TrollStore 安装），
> 才能注入 dylib。如果你只是想用这个胶囊，**优先走 A 方案**。

## 编译

macOS + Xcode Command Line Tools：

```bash
./build.sh
```

产物在 `build/`：
- `WXFloatBar.dylib` — arm64 + arm64e fat binary
- `com.hao.wxfloatbar_1.0.0_iphoneos-arm64.deb`

或用 Theos：

```bash
make package THEOS_PACKAGE_SCHEME=rootless
```

## 兼容性

| 项目 | 值 |
|---|---|
| 最低系统 | iOS 15.0 |
| 架构 | arm64 / arm64e |
| 注入目标 | `com.tencent.xin` / `com.tencent.mm` |
| 根路径 | `/var/jb`（rootless） |

## 已知限制

- **微信版本差异**：本插件不 hook 微信内部类，只在自己的 window 层挂 UI，
  所以微信升级不会导致崩溃，但也意味着它拿不到聊天上下文
  （"分享/保存/复制"目前只弹提示，没有接真实消息数据）
- 按钮动作预留了接口，要接真实功能需要额外分析微信结构

## 配置

外观参数存在 `com.hao.wxfloatbar` 偏好域，代码里可调：

| Key | 默认 | 说明 |
|---|---|---|
| `style` | 0 | 0 通透 / 1 磨砂 / 2 染色绿 |
| `tintAlpha` | 0.10 | 玻璃底色透明度 |
| `edgeOpacity` | 0.55 | 描边强度 |
| `sheen` | 1.0 | 高光渐变强度 |
| `blur` | 22 | 模糊半径 |
| `showTitles` | YES | 是否显示按钮文字 |

位置存在 `WXFB_posX` / `WXFB_posY`。
