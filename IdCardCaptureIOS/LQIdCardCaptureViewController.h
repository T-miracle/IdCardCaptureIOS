#import <UIKit/UIKit.h>

typedef void (^LQIdCardCaptureCompletion)(NSDictionary *result);

/** Full-screen iOS camera flow that collects front and back ID-card images in one session. */
@interface LQIdCardCaptureViewController : UIViewController

- (instancetype)initWithCompletion:(LQIdCardCaptureCompletion)completion;

@end
