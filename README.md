# Uni-App 身份证采集插件（iOS）

适用于传统 Uni-App（Vue 2 / App-Plus）的 iOS 原生 Module 插件。工程构建静态 `UniIdCardCapture.framework`，并回传 `{ code: 0, images: [{ side, path, uri }, ...] }`。

## 插件信息

- 插件 ID / Module 名称：`uni-id-card-capture`
- iOS Module 类：`UniIdCardCaptureModule`
- Framework：`UniIdCardCapture.framework`

## DCloud SDK 前置条件

下载与 HBuilderX 版本匹配的 DCloud iOS 离线 SDK。工作流会自动识别 SDK 的头文件结构；不要提交 SDK 压缩包或解压后的文件。

```text
vendor/dcloud-ios-sdk/
```

GitHub Actions 需要配置仓库 Secret `DCLOUD_SDK_REPO_TOKEN`，以及 Actions Variables `DCLOUD_IOS_SDK_REPOSITORY`、`DCLOUD_IOS_SDK_RELEASE_TAG`；私有 Release 需包含 `SDK.zip`。

## GitHub Actions 产物接入

1. 运行 `Build iOS ID-card Capture Plugin` 工作流，或推送代码自动触发。
2. 下载 `UniIdCardCapture-ios-plugin` Artifact。嵌套压缩包内含 `artifact/ios/UniIdCardCapture.framework` 与 `artifact/package.json`。
3. 将 Framework 放到 Uni-App 项目的 `nativeplugins/uni-id-card-capture/ios/`，并将 `package.json` 放到插件根目录。
4. 在 `manifest.json` 注册 iOS 本地插件、配置 `NSCameraUsageDescription`，然后重新制作自定义基座或云打包。

```js
const capture = uni.requireNativePlugin('uni-id-card-capture');
capture.capture({}, result => console.log(result.images));
```

## App 权限

iOS 宿主必须包含 `NSCameraUsageDescription`；否则系统会在访问摄像头时终止应用。请在 HBuilderX 的 iOS 隐私权限配置中填写相机用途说明，再制作自定义基座或云打包。
