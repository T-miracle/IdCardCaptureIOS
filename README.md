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

## 0.3.0 预览修复与手机诊断

系统“音频与视频”有画面、拍照能生成缩略图，只能证明摄像头采集与照片输出可用，不能证明 App 内的预览已经正常显示。预览视图、遮罩、横屏布局和宿主安装包版本仍需分别验证。

本版本将全屏 `drawRect` 遮罩改成四个外围面板，中间取景区域保持透明；预览继续使用 `AVCaptureVideoPreviewLayer` 作为视图的 backing layer。相机在 `viewDidAppear` 完成布局后绑定、启动，横屏切换时由 UIView 管理预览尺寸。拍照方向与当前界面保持一致，拍照时冻结正反面和取景框数据，裁切按照片归一化后的方向与 aspect-fill 比例计算。

这属于针对显示链路的修复，不把 `session.isRunning` 或预览连接 active 当作“真机画面可见”的证明。模拟器检查也不能代替真实相机验证。

页面底部持续显示 `IDCapture 0.3.0-提交号前8位` 与当前阶段。若看不到这个版本文字，先核对基座和安装包。Actions 还会输出 `artifact/BUILD-INFO.txt`，记录完整提交号、运行编号和 Framework 二进制 SHA-256。

更新步骤：

1. 提交并推送插件修改，由 GitHub Actions 执行模拟器检查、真机 Framework 编译和打包。
2. 下载该次运行的 `UniIdCardCapture-ios-plugin`，用新 Framework 替换 Uni-App 本地插件的 iOS Framework。
3. 若宿主的插件 `package.json` 同时包含 Android 配置，保留 Android 部分，只同步 iOS 配置及版本 `0.3.0`，不要整份覆盖。
4. 重新制作并安装包含该原生插件的 iOS 自定义基座或 App 包。仅更新 JS、热更新或继续运行旧基座不会替换原生 Framework。
5. 在手机核对底部版本与 `BUILD-INFO.txt` 一致，再验证取景框内的动态画面。

## 错误提示与回调

进入相机后的错误保留在底部状态栏；页面可交互时同时弹窗。致命错误点击“返回”后回传 `code: -1`；可恢复错误留在相机页重试。成功仍为 `code: 0`，用户取消仍为 `code: 1`，回调每次调用最多执行一次。

| 阶段 | 错误码 | 处理 |
| --- | --- | --- |
| 页面打开 | `CAPTURE_ALREADY_OPEN`、`CAMERA_PRESENTER_UNAVAILABLE`、`CAMERA_PRESENT_FAILED` | 无法显示相机页时直接回调，由宿主提示 |
| 权限 | `CAMERA_USAGE_MISSING`、`CAMERA_PERMISSION_DENIED` | 检查宿主用途说明、系统权限 |
| 设备与输入 | `CAMERA_UNAVAILABLE`、`CAMERA_INPUT_FAILED`、`CAMERA_INPUT_UNSUPPORTED` | 返回后检查摄像头可用性 |
| 输出 | `PHOTO_OUTPUT_UNSUPPORTED` | 当前设备/会话无法添加拍照输出 |
| 会话启动 | `CAMERA_START_FAILED`、`CAMERA_START_TIMEOUT` | 启动失败或超过 12 秒，返回重试 |
| 预览 | `PREVIEW_ATTACH_FAILED`、`PREVIEW_CONNECTION_INACTIVE` | 检查页面挂载、预览尺寸与连接 |
| 系统中断 | `CAMERA_INTERRUPTED`、`CAPTURE_INTERRUPTED` | 回到前台后自动重连，未完成的拍照需重拍 |
| 运行失败 | `CAMERA_RUNTIME_ERROR` | 保留系统错误 domain/code，返回重试 |
| 拍照 | `CAMERA_NOT_READY`、`PHOTO_CONNECTION_INACTIVE`、`PHOTO_TIMEOUT` | 等待就绪或返回重试；20 秒超时结束该流程 |
| 照片处理 | `PHOTO_PROCESSING_FAILED`、`PHOTO_CAPTURE_FAILED`、`PHOTO_DECODE_FAILED` | 重拍，不更新缩略图 |
| 裁切 | `PHOTO_CROP_FAILED` | 等待方向/布局稳定后重拍 |
| 保存 | `PHOTO_DIRECTORY_MISSING`、`PHOTO_ENCODE_FAILED`、`PHOTO_WRITE_FAILED` | 检查存储空间，不回传无效路径 |
| 完成 | `PHOTO_SIDES_MISSING`、`PHOTO_FILE_MISSING` | 补拍或重新拍摄 |

错误回调示例：

```json
{
  "code": -1,
  "stage": "permission",
  "errorCode": "CAMERA_PERMISSION_DENIED",
  "message": "相机权限已关闭，请在系统设置中允许本 App 使用相机后重新进入。",
  "build": "IDCapture 0.3.0-12345678"
}
```

存在原生错误时附加 `nativeErrorDomain`、`nativeErrorCode`。取消时若此前发生过错误，附加 `lastError`。诊断不记录证件图像或图像内容。

宿主至少应处理无法打开页面时的错误：

```js
capture.capture({}, result => {
  if (result.code === -1) {
    uni.showModal({ title: '证件采集失败', content: result.message || '相机不可用', showCancel: false });
    return;
  }
  if (result.code === 0) {
    // 在这里消费 result.images，避免把证件数据写入日志。
  }
});
```

## 验证

GitHub Actions 运行 `bash tests/run-ios-regressions.sh`：编译一个不申请相机权限的模拟器测试 App，直接执行插件的真实视图与裁切代码，检查透明取景区域、外围半透明遮罩、旋转后的预览/诊断布局、构建标识、拍照操作锁、缺失照片提示、裁切尺寸和实际文件写入。结果作为 `camera-regression-results` 上传；失败时阻止插件打包。

Windows 无法运行上述 UIKit 检查或编译 iOS Framework，需要 Actions 的 macOS runner。实际摄像头预览必须在 iPhone 上按以下步骤验收：

- 确认版本后进入拍照，左右横屏均能看到持续变化的画面；证件框边缘与裁切图片相符。
- 拍正面自动选反面；快速连点拍照、切换卡槽、重拍不会覆盖错误的一面。
- 拉出控制中心再返回、切后台再返回，检查是否恢复预览；中断的拍照应提示重拍。
- 禁止相机权限再进入，应看到明确提示；重新授予权限后可进入拍摄。
- 拍照过程中返回，旧回调不能再修改页面或第二次回传；重新进入可以正常拍照。
- 两面完成后检查图片可读取；若仍黑屏，保留包含底部版本、尺寸和错误码的截图。

参考：[Apple AVCaptureVideoPreviewLayer](https://developer.apple.com/documentation/avfoundation/avcapturevideopreviewlayer)、[相机会话运行错误通知](https://developer.apple.com/documentation/avfoundation/avcapturesession/runtimeerrornotification)。
