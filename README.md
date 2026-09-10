# Uni ID Card Capture for Uni-App — iOS

This is an open-source iOS native Module plugin for traditional Uni-App (Vue 2 / App-Plus). It builds a static `UniIdCardCapture.framework` and returns `{ code: 0, images: [{ side, path, uri }, ...] }`.

## Plugin identity

- Plugin ID / Module name: `uni-id-card-capture`
- iOS Module class: `UniIdCardCaptureModule`
- Framework: `UniIdCardCapture.framework`

## DCloud SDK 前置条件

Download an iOS offline SDK that matches your HBuilderX version. The workflow discovers the SDK header layout automatically; do not commit the SDK archive or its extracted files.

```text
vendor/dcloud-ios-sdk/
```

For GitHub Actions, configure `DCLOUD_SDK_REPO_TOKEN` as a repository Secret and configure `DCLOUD_IOS_SDK_REPOSITORY` plus `DCLOUD_IOS_SDK_RELEASE_TAG` as Actions Variables. The private Release must provide `SDK.zip`.

## GitHub Actions 产物接入

1. Run `Build iOS ID-card Capture Plugin` or push a change.
2. Download the `UniIdCardCapture-ios-plugin` Artifact. Its nested archive contains `artifact/ios/UniIdCardCapture.framework` and `artifact/package.json`.
3. Copy the framework to `nativeplugins/uni-id-card-capture/ios/` in a Uni-App project and copy `artifact/package.json` to the plugin root.
4. Register the local plugin for iOS in `manifest.json`, configure `NSCameraUsageDescription`, then rebuild a custom base or cloud package.

```js
const capture = uni.requireNativePlugin('uni-id-card-capture');
capture.capture({}, result => console.log(result.images));
```

## App 权限

iOS 宿主必须包含 `NSCameraUsageDescription`；否则系统会在访问摄像头时终止应用。请在 HBuilderX 的 iOS 隐私权限配置中填写相机用途说明，再制作自定义基座或云打包。
