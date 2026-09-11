#import "LQIdCardCaptureModule.h"
#import "LQIdCardCaptureViewController.h"
#import "LQCaptureBuild.h"

@interface UniIdCardCaptureModule ()
@property (nonatomic) BOOL capturePending;
@end

@implementation UniIdCardCaptureModule

UNI_EXPORT_METHOD(@selector(capture:callback:))

/**
 * Opens the iOS native, two-sided ID-card capture flow.
 * The callback receives { code, images }, where images is ordered front then back.
 */
- (void)capture:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    (void)options;
    if (callback == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.capturePending) {
            callback(@{ @"code": @-1, @"stage": @"present", @"errorCode": @"CAPTURE_ALREADY_OPEN",
                @"message": @"证件采集页面已打开，请先完成或关闭当前页面。", @"build": LQ_CAPTURE_BUILD_ID }, NO);
            return;
        }
        UIViewController *presenter = [self topViewController];
        if (presenter == nil || presenter.view.window == nil || presenter.isBeingDismissed
            || presenter.isBeingPresented || [presenter isKindOfClass:UIAlertController.class]
            || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            callback(@{ @"code": @-1, @"stage": @"present", @"errorCode": @"CAMERA_PRESENTER_UNAVAILABLE",
                @"message": @"当前页面无法打开相机，请回到前台并关闭弹窗后重试。", @"build": LQ_CAPTURE_BUILD_ID }, NO);
            return;
        }
        self.capturePending = YES;
        __block BOOL settled = NO;
        void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
            if (settled) { return; }
            settled = YES;
            self.capturePending = NO;
            callback(result, NO);
        };
        LQIdCardCaptureViewController *controller = [[LQIdCardCaptureViewController alloc]
            initWithCompletion:^(NSDictionary *result) {
                finish(result);
            }];
        controller.modalPresentationStyle = UIModalPresentationFullScreen;
        [presenter presentViewController:controller animated:YES completion:nil];
        // UIKit can refuse presentation without an NSError. Report it once.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!settled && controller.presentingViewController == nil) {
                finish(@{ @"code": @-1, @"stage": @"present", @"errorCode": @"CAMERA_PRESENT_FAILED",
                    @"message": @"相机页面未能显示，请等待页面切换完成后重试。", @"build": LQ_CAPTURE_BUILD_ID });
            }
        });
    });
}

/** Finds the actual visible presenter for both pre-iOS-13 and scene-based applications. */
- (UIViewController *)topViewController {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]
                || scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
        }
    }
    window = window ?: UIApplication.sharedApplication.keyWindow;
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController != nil) {
        controller = controller.presentedViewController;
    }
    return controller;
}

@end
