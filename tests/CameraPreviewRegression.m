// Runs the actual plugin view classes in an iOS Simulator app, without camera access.
// Device camera rendering still requires the physical-device checklist in README.md.
#import "../IdCardCaptureIOS/LQIdCardCaptureViewController.m"

static NSUInteger LQChecks = 0;

// Substitute only the host's reported enum. UIKit must retain its real scene
// and focus infrastructure; camera orientation selection remains production code.
@interface LQOrientationController : LQIdCardCaptureViewController
@property (nonatomic) UIInterfaceOrientation simulatedInterfaceOrientation;
@end
@implementation LQOrientationController
- (UIInterfaceOrientation)cameraInterfaceOrientation { return self.simulatedInterfaceOrientation; }
@end
static void LQCheck(BOOL passed, NSString *message) {
    if (!passed) { @throw [NSException exceptionWithName:@"RegressionFailure" reason:message userInfo:nil]; }
    LQChecks += 1;
}

static void LQCheckTransparentGuide(LQCameraMaskView *mask) {
    [mask layoutIfNeeded];
    size_t width = (size_t)mask.bounds.size.width;
    size_t height = (size_t)mask.bounds.size.height;
    unsigned char *pixels = calloc(width * height, 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    [mask.layer renderInContext:context];
    // The guide is vertically centered so the pixel address is independent of bitmap row order.
    size_t middle = ((height / 2) * width + (size_t)CGRectGetMidX(mask.guideRect)) * 4;
    BOOL transparent = pixels[middle + 3] == 0;
    BOOL outsideDimmed = pixels[3] > 120 && pixels[3] < 180;
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(pixels);
    LQCheck(transparent, @"The center of the camera guide must be completely transparent.");
    LQCheck(outsideDimmed, @"Outside the guide must dim, not hide, the preview.");
}

static void LQRunRegressions(void) {
    for (NSUInteger entry = 0; entry < 2; entry++) {
        LQOrientationController *camera = [[LQOrientationController alloc] initWithCompletion:nil];
        camera.simulatedInterfaceOrientation = UIInterfaceOrientationPortrait;
        LQCheck([camera currentVideoOrientation] == AVCaptureVideoOrientationLandscapeRight,
            @"Entering from a portrait-locked host must keep a landscape preview, including re-entry.");
        camera.simulatedInterfaceOrientation = UIInterfaceOrientationLandscapeLeft;
        LQCheck([camera currentVideoOrientation] == AVCaptureVideoOrientationLandscapeLeft,
            @"The settled opposite landscape orientation must still be supported.");
        camera.simulatedInterfaceOrientation = UIInterfaceOrientationPortrait;
        LQCheck([camera currentVideoOrientation] == AVCaptureVideoOrientationLandscapeLeft,
            @"Returning host portrait state must not rotate the preview or photo connection.");
        camera.simulatedInterfaceOrientation = UIInterfaceOrientationLandscapeRight;
        LQCheck([camera currentVideoOrientation] == AVCaptureVideoOrientationLandscapeRight,
            @"A real landscape change must update the retained direction.");
        camera.resolved = YES;
    }
    LQIdCardCaptureViewController *controller = [[LQIdCardCaptureViewController alloc] initWithCompletion:nil];
    [controller loadViewIfNeeded]; // Must not request camera permission before presentation.
    LQCheck(controller.session == nil && !controller.configuring, @"Loading an offscreen view must not start the camera.");

    for (NSValue *sizeValue in @[[NSValue valueWithCGSize:CGSizeMake(844, 390)],
                                [NSValue valueWithCGSize:CGSizeMake(667, 375)],
                                [NSValue valueWithCGSize:CGSizeMake(1024, 768)]]) {
        controller.view.frame = CGRectMake(0, 0, 390, 844);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
        CGSize size = sizeValue.CGSizeValue;
        controller.view.frame = CGRectMake(0, 0, size.width, size.height);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
        LQCheck(CGRectEqualToRect(controller.previewView.frame, controller.view.bounds), @"Preview must fill the final viewport.");
        LQCheckTransparentGuide(controller.maskView);
    }

    controller.frontPath = @"existing-front";
    controller.capturing = YES;
    [controller selectBack];
    [controller retakeCurrentSide];
    LQCheck([controller.activeSide isEqualToString:LQFrontSide], @"Side must not change during capture.");
    LQCheck([controller.frontPath isEqualToString:@"existing-front"], @"Retake must not erase state during capture.");
    [controller updateSelection];
    LQCheck(!controller.doneButton.enabled && !controller.frontSlot.enabled && !controller.shutterButton.enabled,
        @"Capture must lock completion, side selection and repeated shutter actions.");
    controller.capturing = NO;
    controller.frontPath = nil;
    [controller completeCapture];
    LQCheck([controller.lastError[@"errorCode"] isEqualToString:@"PHOTO_SIDES_MISSING"], @"Incomplete capture needs an actionable error.");

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1600, 1200), NO, 1);
    [UIColor.redColor setFill];
    UIRectFill(CGRectMake(0, 0, 1600, 1200));
    UIImage *source = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    controller.capturePreviewSize = CGSizeMake(800, 400);
    controller.captureGuideRect = CGRectMake(100, 100, 300, 180);
    UIImage *cropped = [controller croppedGuideImage:source];
    LQCheck(cropped != nil && CGImageGetWidth(cropped.CGImage) == 600 && CGImageGetHeight(cropped.CGImage) == 360,
        @"Aspect-fill crop must use the frozen preview geometry in oriented image pixels.");
    controller.capturePreviewSize = CGSizeZero;
    LQCheck([controller croppedGuideImage:source] == nil, @"Invalid preview geometry must fail safely.");

    NSString *path = [controller saveImage:source side:LQFrontSide];
    LQCheck(path.length > 0 && [NSFileManager.defaultManager isReadableFileAtPath:path], @"A successful save must produce a readable file.");
    if (path != nil) { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; }
    controller.resolved = YES;
}

@interface LQRegressionAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation LQRegressionAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *result;
        @try {
            LQRunRegressions();
            result = @{ @"passed": @YES, @"checks": @(LQChecks) };
        } @catch (NSException *exception) {
            result = @{ @"passed": @NO, @"checks": @(LQChecks), @"error": exception.reason ?: exception.name };
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        NSString *directory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [data writeToFile:[directory stringByAppendingPathComponent:@"regression-result.json"] atomically:YES];
        NSLog(@"Camera regression result: %@", result);
    });
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(LQRegressionAppDelegate.class));
    }
}
