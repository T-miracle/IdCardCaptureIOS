#import "LQIdCardCaptureModule.h"
#import "LQIdCardCaptureViewController.h"

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
        UIViewController *presenter = [self topViewController];
        if (presenter == nil) {
            callback(@{ @"code": @-1, @"message": @"无法启动证件采集页面" }, NO);
            return;
        }
        LQIdCardCaptureViewController *controller = [[LQIdCardCaptureViewController alloc]
            initWithCompletion:^(NSDictionary *result) {
                callback(result, NO);
            }];
        controller.modalPresentationStyle = UIModalPresentationFullScreen;
        [presenter presentViewController:controller animated:YES completion:nil];
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
