# iOS 身份证采集插件源码

`IdCardCaptureIOS.xcodeproj` 构建生成静态 `IdCardCaptureIOS.framework`。模块名与 Android 保持一致：
`luqiao-idcard-capture`；成功回调为 `{ code: 0, images: [{ side, path, uri }, ...] }`。

## DCloud SDK 前置条件

工程引用 `$(DCUNI_SDK_ROOT)/HBuilder-Hello/inc/DCUniModule.h`。请从 DCloud iOS 离线 SDK 中取得该目录，放入：

```text
vendor/dcloud-ios-sdk/HBuilder-Hello/inc/DCUniModule.h
```

该 SDK 不应提交到仓库。GitHub Actions 可通过私有仓库 checkout、受控制品下载等方式在构建时注入。

## GitHub Actions 产物接入

1. 手动运行 `Build iOS ID-card Capture Plugin` 工作流；
2. 在该次运行的 Artifacts 下载并解压 `IdCardCaptureIOS-plugin.zip`；
3. 将 `artifact/ios/IdCardCaptureIOS.framework` 放入智慧安全 App 项目的
   `nativeplugins/luqiao-idcard-capture/ios/`；
4. 将 `artifact/package.json` 的 `_dp_nativeplugin.ios` 节合并进智慧安全 App 插件根目录的 `package.json`；
5. 在智慧安全 App 的 `manifest.json` 中，将
   `nativePlugins.luqiao-idcard-capture.__plugin_info__.platforms` 扩展为 `Android,iOS`，再重新云打包。

## App 权限

iOS 宿主必须包含 `NSCameraUsageDescription`；否则系统会在访问摄像头时终止应用。请在 HBuilderX 的 iOS 隐私权限配置中填写相机用途说明，再制作自定义基座或云打包。
