#import "LQIdCardCaptureViewController.h"
#import <AVFoundation/AVFoundation.h>

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

/** Draws the dimmed camera overlay and the non-rounded ID-card guide frame. */
@interface LQCameraMaskView : UIView
@property (nonatomic) CGRect guideRect;
@end

@implementation LQCameraMaskView

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:0 alpha:0.58].CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, self.bounds.size.width, self.guideRect.origin.y));
    CGContextFillRect(context, CGRectMake(0, CGRectGetMaxY(self.guideRect), self.bounds.size.width,
        self.bounds.size.height - CGRectGetMaxY(self.guideRect)));
    CGContextFillRect(context, CGRectMake(0, self.guideRect.origin.y, self.guideRect.origin.x,
        self.guideRect.size.height));
    CGContextFillRect(context, CGRectMake(CGRectGetMaxX(self.guideRect), self.guideRect.origin.y,
        self.bounds.size.width - CGRectGetMaxX(self.guideRect), self.guideRect.size.height));
    CGContextSetStrokeColorWithColor(context, UIColor.whiteColor.CGColor);
    CGContextSetLineWidth(context, 2.0);
    CGContextStrokeRect(context, CGRectInset(self.guideRect, 1.0, 1.0));
}

@end

@interface LQIdCardCaptureViewController () <AVCapturePhotoCaptureDelegate>
@property (nonatomic, copy) LQIdCardCaptureCompletion completion;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) LQCameraMaskView *maskView;
@property (nonatomic, strong) LQIdCardSlot *frontSlot;
@property (nonatomic, strong) LQIdCardSlot *backSlot;
@property (nonatomic, strong) UIButton *shutterButton;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, copy) NSString *activeSide;
@property (nonatomic, copy) NSString *frontPath;
@property (nonatomic, copy) NSString *backPath;
@property (nonatomic) BOOL resolved;
@end

@implementation LQIdCardCaptureViewController

- (instancetype)initWithCompletion:(LQIdCardCaptureCompletion)completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _completion = [completion copy];
        _activeSide = LQFrontSide;
    }
    return self;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [self buildInterface];
    [self updateSelection];
    [self requestAndStartCamera];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;

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
    [self.maskView setNeedsDisplay];

    CGFloat shutterX = (CGRectGetMaxX(self.maskView.guideRect) + panelX) / 2.0 - 38.0;
    self.shutterButton.frame = CGRectMake(shutterX, (height - 76.0) / 2.0, 76.0, 76.0);
}

/** Builds the overlay entirely in code so the plugin does not depend on a host storyboard. */
- (void)buildInterface {
    UIView *previewView = [[UIView alloc] initWithFrame:self.view.bounds];
    previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:previewView];

    self.previewLayer = [AVCaptureVideoPreviewLayer layer];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [previewView.layer addSublayer:self.previewLayer];

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

- (void)requestAndStartCamera {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self configureCamera];
        return;
    }
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                [self configureCamera];
            } else {
                [self finishWithResult:@{ @"code": @-1, @"message": @"未获得相机权限" }];
            }
        });
    }];
}

- (void)configureCamera {
    if (self.session != nil) {
        if (!self.session.isRunning) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self.session startRunning]; });
        }
        return;
    }
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (input == nil) {
        [self finishWithResult:@{ @"code": @-1, @"message": error.localizedDescription ?: @"相机启动失败" }];
        return;
    }
    self.session = [[AVCaptureSession alloc] init];
    [self.session beginConfiguration];
    self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    [self.session addInput:input];
    self.photoOutput = [[AVCapturePhotoOutput alloc] init];
    [self.session addOutput:self.photoOutput];
    [self.session commitConfiguration];
    self.previewLayer.session = self.session;
    AVCaptureConnection *connection = self.previewLayer.connection;
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [self.session startRunning]; });
}

- (void)takePhoto {
    if (self.photoOutput == nil || !self.session.isRunning) {
        return;
    }
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    AVCaptureConnection *connection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    }
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
didFinishProcessingPhoto:(AVCapturePhoto *)photo
                 error:(NSError *)error {
    (void)output;
    if (error != nil || photo.fileDataRepresentation == nil) {
        return;
    }
    UIImage *image = [self croppedGuideImage:[[UIImage alloc] initWithData:photo.fileDataRepresentation]];
    if (image == nil) {
        return;
    }
    NSString *path = [self saveImage:image side:self.activeSide];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.activeSide isEqualToString:LQFrontSide]) {
            self.frontPath = path;
            [self.frontSlot setCapturedImage:image];
            [self selectSide:LQBackSide];
        } else {
            self.backPath = path;
            [self.backSlot setCapturedImage:image];
            [self updateSelection];
        }
    });
}

/** Crops the still image using AVCapture's preview-to-output normalized rectangle conversion. */
- (UIImage *)croppedGuideImage:(UIImage *)source {
    UIImage *normalized = [self normalizedImage:source];
    CGRect normalizedRect = [self.previewLayer metadataOutputRectOfInterestForRect:self.maskView.guideRect];
    CGRect pixels = CGRectMake(normalizedRect.origin.x * normalized.size.width,
        normalizedRect.origin.y * normalized.size.height,
        normalizedRect.size.width * normalized.size.width,
        normalizedRect.size.height * normalized.size.height);
    pixels = CGRectIntersection(pixels, CGRectMake(0, 0, normalized.size.width, normalized.size.height));
    CGImageRef cgImage = CGImageCreateWithImageInRect(normalized.CGImage, pixels);
    if (cgImage == nil) {
        return nil;
    }
    UIImage *cropped = [UIImage imageWithCGImage:cgImage scale:normalized.scale orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return cropped;
}

- (UIImage *)normalizedImage:(UIImage *)image {
    if (image.imageOrientation == UIImageOrientationUp) {
        return image;
    }
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    [image drawInRect:CGRectMake(0, 0, image.size.width, image.size.height)];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized;
}

- (NSString *)saveImage:(UIImage *)image side:(NSString *)side {
    NSString *directory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *timestamp = [NSString stringWithFormat:@"%.0f", NSDate.date.timeIntervalSince1970 * 1000.0];
    NSString *path = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"idcard_%@_%@.jpg", side, timestamp]];
    [UIImageJPEGRepresentation(image, 0.95) writeToFile:path atomically:YES];
    return path;
}

- (void)selectFront { [self selectSide:LQFrontSide]; }
- (void)selectBack { [self selectSide:LQBackSide]; }

- (void)selectSide:(NSString *)side {
    self.activeSide = side;
    [self updateSelection];
}

- (void)retakeCurrentSide {
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
    self.doneButton.enabled = complete;
    self.doneButton.alpha = complete ? 1.0 : 0.45;
}

- (void)completeCapture {
    if (self.frontPath.length == 0 || self.backPath.length == 0) {
        return;
    }
    NSArray *images = @[
        @{ @"side": LQFrontSide, @"path": self.frontPath, @"uri": [NSURL fileURLWithPath:self.frontPath].absoluteString },
        @{ @"side": LQBackSide, @"path": self.backPath, @"uri": [NSURL fileURLWithPath:self.backPath].absoluteString }
    ];
    [self finishWithResult:@{ @"code": @0, @"images": images }];
}

- (void)cancelCapture {
    [self finishWithResult:@{ @"code": @1, @"message": @"已取消证件采集" }];
}

- (void)finishWithResult:(NSDictionary *)result {
    if (self.resolved) {
        return;
    }
    self.resolved = YES;
    LQIdCardCaptureCompletion callback = self.completion;
    [self.session stopRunning];
    [self dismissViewControllerAnimated:YES completion:^{
        if (callback != nil) {
            callback(result);
        }
    }];
}

@end
