#import "LQIdCardCaptureViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "LQCaptureBuild.h"

static CGFloat const LQIdCardRatio = 85.60 / 53.98;
static NSString * const LQFrontSide = @"front";
static NSString * const LQBackSide = @"back";

/** Right-side card slot with a dashed border and optional captured thumbnail. */
@interface LQIdCardSlot : UIControl
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, copy) NSString *side;
- (instancetype)initWithSide:(NSString *)side title:(NSString *)title;
- (void)setSelectedSlot:(BOOL)selected;
- (void)setCapturedImage:(UIImage *)image;
@end

@implementation LQIdCardSlot

- (instancetype)initWithSide:(NSString *)side title:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _side = side;
        _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self addSubview:_imageView];

        _placeholderLabel = [[UILabel alloc] initWithFrame:self.bounds];
        _placeholderLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _placeholderLabel.text = title;
        _placeholderLabel.textAlignment = NSTextAlignmentCenter;
        _placeholderLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightMedium];
        [self addSubview:_placeholderLabel];

        _borderLayer = [CAShapeLayer layer];
        _borderLayer.fillColor = UIColor.clearColor.CGColor;
        _borderLayer.lineWidth = 1.0;
        _borderLayer.lineDashPattern = @[ @5, @3 ];
        [self.layer addSublayer:_borderLayer];
        [self setSelectedSlot:[side isEqualToString:LQFrontSide]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.borderLayer.frame = self.bounds;
    self.borderLayer.path = [UIBezierPath bezierPathWithRect:CGRectInset(self.bounds, 0.5, 0.5)].CGPath;
}

- (void)setSelectedSlot:(BOOL)selected {
    UIColor *color = selected ? [UIColor colorWithRed:0.34 green:0.75 blue:0.17 alpha:1.0] : UIColor.whiteColor;
    self.placeholderLabel.textColor = color;
    self.borderLayer.strokeColor = color.CGColor;
}

- (void)setCapturedImage:(UIImage *)image {
    self.imageView.image = image;
    self.placeholderLabel.text = image == nil
        ? ([self.side isEqualToString:LQFrontSide] ? @"身份证正面" : @"身份证反面")
        : @"";
}

@end

/** Four separate panels leave a genuinely uncovered preview rectangle. */
@interface LQCameraMaskView : UIView
@property (nonatomic) CGRect guideRect;
@property (nonatomic, strong) NSArray<UIView *> *panels;
@property (nonatomic, strong) UIView *guideView;
@end

@implementation LQCameraMaskView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        NSMutableArray *panels = [NSMutableArray array];
        for (NSUInteger i = 0; i < 4; i++) {
            UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
            panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.58];
            [self addSubview:panel];
            [panels addObject:panel];
        }
        self.panels = panels;
        self.guideView = [[UIView alloc] initWithFrame:CGRectZero];
        self.guideView.opaque = NO;
        self.guideView.backgroundColor = UIColor.clearColor;
        self.guideView.layer.borderColor = UIColor.whiteColor.CGColor;
        self.guideView.layer.borderWidth = 2.0;
        [self addSubview:self.guideView];
    }
    return self;
}

- (void)setGuideRect:(CGRect)guideRect {
    _guideRect = guideRect;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect guide = CGRectIntersection(self.bounds, self.guideRect);
    if (CGRectIsNull(guide) || CGRectIsEmpty(guide)) {
        guide = CGRectZero;
    }
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    self.panels[0].frame = CGRectMake(0, 0, width, CGRectGetMinY(guide));
    self.panels[1].frame = CGRectMake(0, CGRectGetMaxY(guide), width, height - CGRectGetMaxY(guide));
    self.panels[2].frame = CGRectMake(0, CGRectGetMinY(guide), CGRectGetMinX(guide), guide.size.height);
    self.panels[3].frame = CGRectMake(CGRectGetMaxX(guide), CGRectGetMinY(guide), width - CGRectGetMaxX(guide), guide.size.height);
    self.guideView.frame = guide;
}

@end

/** Uses Apple's capture preview layer directly as the view's backing layer. */
@interface LQCameraPreviewView : UIView
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *previewLayer;
@end

@implementation LQCameraPreviewView

+ (Class)layerClass {
    return AVCaptureVideoPreviewLayer.class;
}

- (AVCaptureVideoPreviewLayer *)previewLayer {
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (void)setSession:(AVCaptureSession *)session {
    _session = session;
    self.previewLayer.session = session;
}

@end

@interface LQIdCardCaptureViewController () <AVCapturePhotoCaptureDelegate>
@property (nonatomic, copy) LQIdCardCaptureCompletion completion;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property (nonatomic, strong) LQCameraPreviewView *previewView;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) LQCameraMaskView *maskView;
@property (nonatomic, strong) LQIdCardSlot *frontSlot;
@property (nonatomic, strong) LQIdCardSlot *backSlot;
@property (nonatomic, strong) UIButton *shutterButton;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, copy) NSString *activeSide;
@property (nonatomic, copy) NSString *frontPath;
@property (nonatomic, copy) NSString *backPath;
@property (atomic) BOOL resolved;
// UI state is main-thread owned; session configuration/start/stop use sessionQueue.
@property (nonatomic) BOOL visible;
@property (nonatomic) BOOL configuring;
@property (nonatomic) BOOL cameraReady;
@property (nonatomic) BOOL capturing;
@property (nonatomic) BOOL fatalError;
@property (nonatomic) NSInteger previewCheckVersion;
@property (nonatomic) NSInteger configurationVersion;
@property (nonatomic) int64_t pendingPhotoID;
@property (nonatomic, copy) NSString *captureSide;
@property (nonatomic) CGRect captureGuideRect;
@property (nonatomic) CGSize capturePreviewSize;
// Uni-App locks its host in portrait. Keep the last valid camera landscape
// direction instead of applying that host orientation during modal transitions.
@property (nonatomic) AVCaptureVideoOrientation landscapeVideoOrientation;
@property (nonatomic, strong) UIImage *pendingImage;
@property (nonatomic, copy) NSString *pendingPath;
@property (nonatomic, copy) NSDictionary *lastError;
@end

@implementation LQIdCardCaptureViewController

- (instancetype)initWithCompletion:(LQIdCardCaptureCompletion)completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _completion = [completion copy];
        _activeSide = LQFrontSide;
        _landscapeVideoOrientation = AVCaptureVideoOrientationLandscapeRight;
        _sessionQueue = dispatch_queue_create("io.github.uniidcardcapture.session", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

/** Read the settled window orientation after presentation/rotation completes. */
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (!self.resolved) {
            [self.view setNeedsLayout];
            [self.view layoutIfNeeded];
            [self updatePreviewOrientation];
        }
    }];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [self buildInterface];
    [self updateSelection];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(cameraRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
    [center addObserver:self selector:@selector(cameraInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:nil];
    [center addObserver:self selector:@selector(cameraInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:nil];
    [center addObserver:self selector:@selector(applicationBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(applicationEnteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.visible = YES;
    [self.view layoutIfNeeded];
    [self updatePreviewOrientation];
    [self requestAndStartCamera];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.visible = NO;
    [self pauseCamera];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // The preview layer is the view's backing layer. Set the UIView frame;
    // UIKit must own its backing layer geometry during host rotation.
    self.previewView.frame = self.view.bounds;
    self.maskView.frame = self.view.bounds;

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGFloat panelWidth = MIN(168.0, width * 0.18);
    CGFloat cardHeight = panelWidth / LQIdCardRatio;
    CGFloat panelX = width - panelWidth - 28.0;
    CGFloat panelTop = (height - cardHeight * 2.0 - 16.0) / 2.0;
    self.frontSlot.frame = CGRectMake(panelX, panelTop, panelWidth, cardHeight);
    self.backSlot.frame = CGRectMake(panelX, CGRectGetMaxY(self.frontSlot.frame) + 16.0, panelWidth, cardHeight);

    CGFloat guideLeft = 44.0;
    CGFloat guideMaxWidth = MAX(260.0, panelX - guideLeft - 130.0);
    CGFloat guideHeight = MIN(height - 150.0, guideMaxWidth / LQIdCardRatio);
    CGFloat guideWidth = guideHeight * LQIdCardRatio;
    self.maskView.guideRect = CGRectMake(guideLeft, (height - guideHeight) / 2.0, guideWidth, guideHeight);
    [self.maskView layoutIfNeeded];

    UIEdgeInsets insets = self.view.safeAreaInsets;
    [self updatePreviewOrientation];

    CGFloat shutterX = (CGRectGetMaxX(self.maskView.guideRect) + panelX) / 2.0 - 38.0;
    self.shutterButton.frame = CGRectMake(shutterX, (height - 76.0) / 2.0, 76.0, 76.0);
}

/** Builds the overlay entirely in code so the plugin does not depend on a host storyboard. */
- (void)buildInterface {
    self.previewView = [[LQCameraPreviewView alloc] initWithFrame:self.view.bounds];
    self.previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.previewView];

    self.previewView.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    self.maskView = [[LQCameraMaskView alloc] initWithFrame:self.view.bounds];
    self.maskView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.maskView.userInteractionEnabled = NO;
    [self.view addSubview:self.maskView];

    UIButton *back = [self textButton:@"‹  返回" color:UIColor.clearColor];
    back.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightMedium];
    back.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    back.frame = CGRectMake(24.0, 10.0, 140.0, 48.0);
    [back addTarget:self action:@selector(cancelCapture) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:back];

    UIButton *retake = [self textButton:@"重拍" color:[UIColor colorWithRed:0.96 green:0.42 blue:0 alpha:1.0]];
    retake.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 240.0, 12.0, 104.0, 44.0);
    retake.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [retake addTarget:self action:@selector(retakeCurrentSide) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:retake];

    self.doneButton = [self textButton:@"完成" color:[UIColor colorWithRed:0.34 green:0.75 blue:0.17 alpha:1.0]];
    self.doneButton.frame = CGRectMake(CGRectGetWidth(self.view.bounds) - 124.0, 12.0, 104.0, 44.0);
    self.doneButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.doneButton addTarget:self action:@selector(completeCapture) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.doneButton];

    self.shutterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.shutterButton setTitle:@"拍照" forState:UIControlStateNormal];
    [self.shutterButton setTitleColor:UIColor.darkGrayColor forState:UIControlStateNormal];
    self.shutterButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    self.shutterButton.backgroundColor = UIColor.whiteColor;
    self.shutterButton.layer.cornerRadius = 38.0;
    self.shutterButton.layer.borderWidth = 4.0;
    self.shutterButton.layer.borderColor = UIColor.darkGrayColor.CGColor;
    [self.shutterButton addTarget:self action:@selector(takePhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shutterButton];

    self.frontSlot = [[LQIdCardSlot alloc] initWithSide:LQFrontSide title:@"身份证正面"];
    self.backSlot = [[LQIdCardSlot alloc] initWithSide:LQBackSide title:@"身份证反面"];
    [self.frontSlot addTarget:self action:@selector(selectFront) forControlEvents:UIControlEventTouchUpInside];
    [self.backSlot addTarget:self action:@selector(selectBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.frontSlot];
    [self.view addSubview:self.backSlot];
}

- (UIButton *)textButton:(NSString *)title color:(UIColor *)color {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightMedium];
    button.backgroundColor = color;
    button.layer.borderColor = UIColor.whiteColor.CGColor;
    button.layer.borderWidth = color == UIColor.clearColor ? 0.0 : 1.0;
    button.layer.cornerRadius = 4.0;
    return button;
}

/** Permission failures are visible before returning a structured error to Uni-App. */
- (void)requestAndStartCamera {
    if (self.resolved || self.fatalError || !self.visible || self.configuring) {
        return;
    }
    NSString *usage = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSCameraUsageDescription"];
    if (![usage isKindOfClass:NSString.class] || usage.length == 0) {
        [self reportError:@"permission" code:@"CAMERA_USAGE_MISSING"
                 message:@"宿主未配置相机用途说明，请配置 NSCameraUsageDescription 并重新制作自定义基座。" error:nil fatal:YES];
        return;
    }
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self configureCamera];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        self.configuring = YES;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.configuring = NO;
                if (self.resolved) { return; }
                if (granted) {
                    [self requestAndStartCamera];
                } else {
                    [self reportError:@"permission" code:@"CAMERA_PERMISSION_DENIED"
                             message:@"未获得相机权限，请在系统设置中允许本 App 使用相机后重新进入。" error:nil fatal:YES];
                }
            });
        }];
    } else {
        [self reportError:@"permission" code:@"CAMERA_PERMISSION_DENIED"
                 message:status == AVAuthorizationStatusRestricted ? @"相机访问受到系统限制，请检查屏幕使用时间或设备管理设置。" : @"相机权限已关闭，请在系统设置中允许本 App 使用相机后重新进入。"
                   error:nil fatal:YES];
    }
}

/** Only main-thread UI state changes here; callback payloads never include image data. */
- (void)reportError:(NSString *)stage code:(NSString *)code message:(NSString *)message
              error:(NSError *)error fatal:(BOOL)fatal {
    void (^report)(void) = ^{
        if (self.resolved || self.fatalError) { return; }
        NSMutableDictionary *result = [@{ @"code": @-1, @"stage": stage, @"errorCode": code,
            @"message": message, @"build": LQ_CAPTURE_BUILD_ID } mutableCopy];
        if (error != nil) {
            result[@"nativeErrorDomain"] = error.domain;
            result[@"nativeErrorCode"] = @(error.code);
        }
        self.lastError = result;
        self.fatalError = fatal;
        self.capturing = NO;
        self.pendingPhotoID = 0;
        self.pendingImage = nil;
        self.pendingPath = nil;
        if (fatal) {
            self.configuring = NO;
            self.cameraReady = NO;
            [self pauseCamera];
        }
        [self updateSelection];
        NSLog(@"[UNI-IDCARD-CAMERA] build=%@ stage=%@ code=%@ native=%@/%ld", LQ_CAPTURE_BUILD_ID,
            stage, code, error.domain ?: @"none", (long)error.code);
        if (self.visible && self.presentedViewController == nil
            && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"相机错误 · %@", code]
                message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:fatal ? @"返回" : @"知道了" style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                    if (fatal) { [self finishWithResult:result]; }
                }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    };
    if (NSThread.isMainThread) { report(); }
    else { dispatch_async(dispatch_get_main_queue(), report); }
}

/** Host state is isolated from the camera's retained orientation policy. */
- (UIInterfaceOrientation)cameraInterfaceOrientation {
    return self.view.window.windowScene.interfaceOrientation;
}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    UIInterfaceOrientation orientation = [self cameraInterfaceOrientation];
    switch (orientation) {
        case UIInterfaceOrientationLandscapeLeft:
            self.landscapeVideoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            self.landscapeVideoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        default:
            // Portrait/unknown belongs to the host or a transition, never this
            // landscape-only camera. Applying it rotates video by 90 degrees.
            break;
    }
    return self.landscapeVideoOrientation;
}

- (void)updatePreviewOrientation {
    AVCaptureConnection *connection = self.previewView.previewLayer.connection;
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = [self currentVideoOrientation];
    }
}

/** Bind only after presentation/layout. Session work never blocks the UI thread. */
- (void)configureCamera {
    if (self.configuring || self.resolved || self.fatalError || !self.visible
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { return; }
    self.configuring = YES;
    NSInteger configuration = ++self.configurationVersion;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!self.resolved && !self.fatalError && self.visible && self.configuring
            && self.configurationVersion == configuration
            && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            [self reportError:@"session" code:@"CAMERA_START_TIMEOUT" message:@"相机启动超过 12 秒未完成，请返回后重试。" error:nil fatal:YES];
        }
    });
    self.cameraReady = NO;
    [self updateSelection];
    dispatch_async(self.sessionQueue, ^{
        if (self.resolved) { return; }
        AVCaptureSession *session = self.session;
        if (session == nil) {
            AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
            if (device == nil) {
                [self reportError:@"device" code:@"CAMERA_UNAVAILABLE" message:@"找不到可用的后置摄像头。" error:nil fatal:YES];
                return;
            }
            NSError *error = nil;
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
            if (input == nil) {
                [self reportError:@"input" code:@"CAMERA_INPUT_FAILED" message:@"无法创建相机输入，请退出其他占用相机的应用后重试。" error:error fatal:YES];
                return;
            }
            session = [[AVCaptureSession alloc] init];
            [session beginConfiguration];
            if ([session canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
                session.sessionPreset = AVCaptureSessionPresetPhoto;
            }
            if (![session canAddInput:input]) {
                [session commitConfiguration];
                [self reportError:@"input" code:@"CAMERA_INPUT_UNSUPPORTED" message:@"当前会话无法添加摄像头输入。" error:nil fatal:YES];
                return;
            }
            [session addInput:input];
            AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];
            if (![session canAddOutput:output]) {
                [session commitConfiguration];
                [self reportError:@"output" code:@"PHOTO_OUTPUT_UNSUPPORTED" message:@"当前会话无法添加拍照输出。" error:nil fatal:YES];
                return;
            }
            [session addOutput:output];
            [session commitConfiguration];
            self.session = session;
            self.photoOutput = output;
        }
        __block BOOL attached = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (!self.resolved && !self.fatalError && self.visible && self.view.window != nil
                && UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
                [self.view layoutIfNeeded];
                self.previewView.session = session;
                [self updatePreviewOrientation];
                attached = !CGRectIsEmpty(self.previewView.bounds) && self.previewView.previewLayer.connection != nil;
            }
        });
        if (attached && !self.resolved && !session.isRunning) {
            [session startRunning];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.configuring = NO;
            if (self.resolved || self.fatalError || !self.visible
                || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) { return; }
            if (!attached) {
                [self reportError:@"preview" code:@"PREVIEW_ATTACH_FAILED" message:@"预览未连接到可见页面，请返回后重新进入。" error:nil fatal:YES];
            } else if (!session.isRunning) {
                [self reportError:@"session" code:@"CAMERA_START_FAILED" message:@"相机会话启动失败，请返回后重试。" error:nil fatal:YES];
            } else {
                [self checkPreviewConnection];
            }
        });
    });
}

/** Connection health is diagnostic only: a running session does not prove visible pixels. */
- (void)checkPreviewConnection {
    NSInteger version = ++self.previewCheckVersion;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.resolved || self.fatalError || !self.visible || version != self.previewCheckVersion) { return; }
        AVCaptureConnection *connection = self.previewView.previewLayer.connection;
        self.cameraReady = self.session.isRunning && !self.session.isInterrupted
            && connection.isEnabled && connection.isActive && self.previewView.window != nil
            && !CGRectIsEmpty(self.previewView.bounds);
        [self updateSelection];
        if (!self.cameraReady) {
            [self reportError:@"preview" code:@"PREVIEW_CONNECTION_INACTIVE" message:@"预览连接未就绪，请返回后重新进入；若被系统中断，恢复后会自动重连。" error:nil fatal:NO];
        }
    });
}

- (void)pauseCamera {
    self.cameraReady = NO;
    self.previewCheckVersion += 1;
    [self updateSelection];
    dispatch_async(self.sessionQueue, ^{ [self.session stopRunning]; });
}

- (void)applicationEnteredBackground:(NSNotification *)notification {
    [self pauseCamera];
    if (self.capturing) {
        [self reportError:@"capture" code:@"CAPTURE_INTERRUPTED" message:@"拍照被切换后台中断，请回到页面后重新拍摄。" error:nil fatal:NO];
    }
}

- (void)applicationBecameActive:(NSNotification *)notification {
    [self requestAndStartCamera];
}

- (void)cameraRuntimeError:(NSNotification *)notification {
    if (notification.object != self.session) { return; }
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    [self reportError:@"session" code:@"CAMERA_RUNTIME_ERROR" message:@"相机会话运行失败，请返回后重新进入。" error:error fatal:YES];
}

- (void)cameraInterrupted:(NSNotification *)notification {
    if (notification.object != self.session) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.resolved) { return; }
        self.cameraReady = NO;
        self.previewCheckVersion += 1;
        [self updateSelection];
        NSNumber *reason = notification.userInfo[AVCaptureSessionInterruptionReasonKey];
        [self reportError:@"session" code:@"CAMERA_INTERRUPTED"
            message:[NSString stringWithFormat:@"相机被系统中断（原因 %@），请关闭其他相机功能或返回前台，等待自动恢复。", reason ?: @0]
            error:nil fatal:NO];
    });
}

- (void)cameraInterruptionEnded:(NSNotification *)notification {
    if (notification.object != self.session) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self requestAndStartCamera]; });
}

/** Freeze side, geometry and orientation before capture; disallow duplicate requests. */
- (void)takePhoto {
    if (self.capturing || self.resolved || self.fatalError) { return; }
    if (!self.cameraReady || self.photoOutput == nil || !self.session.isRunning) {
        [self reportError:@"capture" code:@"CAMERA_NOT_READY" message:@"相机尚未就绪，请等待预览连接恢复后再拍照。" error:nil fatal:NO];
        return;
    }
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    self.capturing = YES;
    self.pendingPhotoID = settings.uniqueID;
    self.captureSide = self.activeSide;
    self.captureGuideRect = [self.maskView convertRect:self.maskView.guideRect toView:self.previewView];
    self.capturePreviewSize = self.previewView.bounds.size;
    self.pendingImage = nil;
    self.pendingPath = nil;
    [self updateSelection];
    AVCaptureVideoOrientation orientation = [self currentVideoOrientation];
    dispatch_async(self.sessionQueue, ^{
        if (self.resolved) { return; }
        AVCaptureConnection *connection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
        if (!self.session.isRunning || !connection.isEnabled || !connection.isActive) {
            [self reportError:@"capture" code:@"PHOTO_CONNECTION_INACTIVE" message:@"拍照连接已中断，请稍后重试。" error:nil fatal:NO];
            return;
        }
        if (connection.isVideoOrientationSupported) { connection.videoOrientation = orientation; }
        [self.photoOutput capturePhotoWithSettings:settings delegate:self];
    });
    int64_t identifier = settings.uniqueID;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!self.resolved && self.capturing && self.pendingPhotoID == identifier) {
            [self reportError:@"capture" code:@"PHOTO_TIMEOUT" message:@"拍照处理超过 20 秒未完成，请返回后重新进入。" error:nil fatal:YES];
        }
    });
}

/** Delegate callbacks marshal UI and capture state back to the main thread. */
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    NSData *data = error == nil ? photo.fileDataRepresentation : nil;
    int64_t identifier = photo.resolvedSettings.uniqueID;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.resolved || !self.capturing || self.pendingPhotoID != identifier) { return; }
        if (error != nil || data.length == 0) {
            [self reportError:@"capture" code:@"PHOTO_PROCESSING_FAILED" message:@"照片生成失败，请重新拍摄。" error:error fatal:NO];
            return;
        }
        UIImage *source = [[UIImage alloc] initWithData:data];
        if (source == nil) {
            [self reportError:@"decode" code:@"PHOTO_DECODE_FAILED" message:@"无法读取照片内容，请重新拍摄。" error:nil fatal:NO];
            return;
        }
        UIImage *image = [self croppedGuideImage:source];
        if (image == nil) {
            [self reportError:@"crop" code:@"PHOTO_CROP_FAILED" message:@"取景框裁切失败，请等待页面方向稳定后重新拍摄。" error:nil fatal:NO];
            return;
        }
        NSString *path = [self saveImage:image side:self.captureSide];
        if (path == nil) { return; } // saveImage reports encoding/directory/write errors.
        self.pendingImage = image;
        self.pendingPath = path;
    });
}

/** Final capture errors can arrive after processing; publish the thumbnail only on success. */
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishCaptureForResolvedSettings:(AVCaptureResolvedPhotoSettings *)settings error:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.resolved || !self.capturing || self.pendingPhotoID != settings.uniqueID) { return; }
        if (error != nil || self.pendingImage == nil || self.pendingPath.length == 0) {
            [self reportError:@"capture" code:@"PHOTO_CAPTURE_FAILED" message:@"拍照未完整完成，请重新拍摄。" error:error fatal:NO];
            return;
        }
        if ([self.captureSide isEqualToString:LQFrontSide]) {
            self.frontPath = self.pendingPath;
            [self.frontSlot setCapturedImage:self.pendingImage];
            self.activeSide = LQBackSide;
        } else {
            self.backPath = self.pendingPath;
            [self.backSlot setCapturedImage:self.pendingImage];
        }
        self.capturing = NO;
        self.pendingPhotoID = 0;
        self.pendingImage = nil;
        self.pendingPath = nil;
        [self updateSelection];
    });
}

/** Match aspect-fill preview coordinates against the orientation-normalized still image. */
- (UIImage *)croppedGuideImage:(UIImage *)source {
    UIImage *normalized = [self normalizedImage:source];
    if (normalized.CGImage == nil || self.capturePreviewSize.width <= 0 || self.capturePreviewSize.height <= 0) { return nil; }
    CGFloat width = CGImageGetWidth(normalized.CGImage);
    CGFloat height = CGImageGetHeight(normalized.CGImage);
    if (width <= 0 || height <= 0 || CGRectIsEmpty(self.captureGuideRect)) { return nil; }
    CGFloat scale = MAX(self.capturePreviewSize.width / width, self.capturePreviewSize.height / height);
    CGFloat offsetX = (width * scale - self.capturePreviewSize.width) / 2.0;
    CGFloat offsetY = (height * scale - self.capturePreviewSize.height) / 2.0;
    CGRect pixels = CGRectMake((self.captureGuideRect.origin.x + offsetX) / scale,
        (self.captureGuideRect.origin.y + offsetY) / scale,
        self.captureGuideRect.size.width / scale, self.captureGuideRect.size.height / scale);
    pixels = CGRectIntersection(CGRectIntegral(pixels), CGRectMake(0, 0, width, height));
    if (CGRectIsNull(pixels) || CGRectIsEmpty(pixels)) { return nil; }
    CGImageRef cgImage = CGImageCreateWithImageInRect(normalized.CGImage, pixels);
    if (cgImage == nil) { return nil; }
    UIImage *cropped = [UIImage imageWithCGImage:cgImage scale:1 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return cropped;
}

- (UIImage *)normalizedImage:(UIImage *)image {
    if (image == nil || image.size.width <= 0 || image.size.height <= 0) { return nil; }
    if (image.imageOrientation == UIImageOrientationUp) { return image; }
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized;
}

- (NSString *)saveImage:(UIImage *)image side:(NSString *)side {
    NSString *directory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (directory.length == 0) {
        [self reportError:@"save" code:@"PHOTO_DIRECTORY_MISSING" message:@"无法获取照片保存目录。" error:nil fatal:NO];
        return nil;
    }
    NSData *data = UIImageJPEGRepresentation(image, 0.95);
    if (data.length == 0) {
        [self reportError:@"encode" code:@"PHOTO_ENCODE_FAILED" message:@"照片 JPEG 编码失败，请重新拍摄。" error:nil fatal:NO];
        return nil;
    }
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"idcard_%@_%@.jpg", side, NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        [self reportError:@"save" code:@"PHOTO_WRITE_FAILED" message:@"照片保存失败，请检查设备剩余存储空间后重试。" error:error fatal:NO];
        return nil;
    }
    return path;
}

- (void)selectFront { [self selectSide:LQFrontSide]; }
- (void)selectBack { [self selectSide:LQBackSide]; }

- (void)selectSide:(NSString *)side {
    if (self.capturing || self.resolved || self.fatalError) { return; }
    self.activeSide = side;
    [self updateSelection];
}

- (void)retakeCurrentSide {
    if (self.capturing || self.resolved || self.fatalError) { return; }
    if ([self.activeSide isEqualToString:LQFrontSide]) {
        self.frontPath = nil;
        [self.frontSlot setCapturedImage:nil];
    } else {
        self.backPath = nil;
        [self.backSlot setCapturedImage:nil];
    }
    [self updateSelection];
}

- (void)updateSelection {
    [self.frontSlot setSelectedSlot:[self.activeSide isEqualToString:LQFrontSide]];
    [self.backSlot setSelectedSlot:[self.activeSide isEqualToString:LQBackSide]];
    BOOL complete = self.frontPath.length > 0 && self.backPath.length > 0;
    BOOL available = !self.capturing && !self.resolved && !self.fatalError;
    self.frontSlot.enabled = available;
    self.backSlot.enabled = available;
    self.doneButton.enabled = complete && available;
    self.doneButton.alpha = self.doneButton.enabled ? 1.0 : 0.45;
    self.shutterButton.enabled = available && self.cameraReady;
    self.shutterButton.alpha = self.shutterButton.enabled ? 1.0 : 0.45;
    [self.shutterButton setTitle:self.capturing ? @"处理中" : @"拍照" forState:UIControlStateNormal];
}

- (void)completeCapture {
    if (self.capturing || self.resolved || self.fatalError) { return; }
    if (self.frontPath.length == 0 || self.backPath.length == 0) {
        [self reportError:@"complete" code:@"PHOTO_SIDES_MISSING" message:@"请先完成身份证正反面拍摄。" error:nil fatal:NO];
        return;
    }
    if (![NSFileManager.defaultManager isReadableFileAtPath:self.frontPath]
        || ![NSFileManager.defaultManager isReadableFileAtPath:self.backPath]) {
        [self reportError:@"complete" code:@"PHOTO_FILE_MISSING" message:@"已拍照片文件无法读取，请重新拍摄后再完成。" error:nil fatal:NO];
        return;
    }
    NSArray *images = @[
        @{ @"side": LQFrontSide, @"path": self.frontPath, @"uri": [NSURL fileURLWithPath:self.frontPath].absoluteString },
        @{ @"side": LQBackSide, @"path": self.backPath, @"uri": [NSURL fileURLWithPath:self.backPath].absoluteString }
    ];
    [self finishWithResult:@{ @"code": @0, @"images": images, @"build": LQ_CAPTURE_BUILD_ID }];
}

- (void)cancelCapture {
    if (self.fatalError && self.lastError != nil) {
        [self finishWithResult:self.lastError];
        return;
    }
    NSMutableDictionary *result = [@{ @"code": @1, @"message": @"已取消证件采集", @"build": LQ_CAPTURE_BUILD_ID } mutableCopy];
    if (self.lastError != nil) { result[@"lastError"] = self.lastError; }
    [self finishWithResult:result];
}

- (void)finishWithResult:(NSDictionary *)result {
    if (self.resolved) {
        return;
    }
    self.resolved = YES;
    self.previewCheckVersion += 1;
    self.pendingPhotoID = 0;
    self.capturing = NO;
    LQIdCardCaptureCompletion callback = self.completion;
    self.completion = nil;
    [self pauseCamera];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self dismissViewControllerAnimated:YES completion:^{
        if (callback != nil) {
            callback(result);
        }
    }];
}

@end
