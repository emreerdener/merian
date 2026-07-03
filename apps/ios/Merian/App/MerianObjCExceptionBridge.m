#import "MerianObjCExceptionBridge.h"

BOOL MerianCatchObjCException(MerianObjCExceptionBlock block, NSError **error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != nil) {
            NSString *reason = exception.reason ?: @"Objective-C exception raised";
            NSString *name = exception.name ?: @"NSException";
            NSArray<NSString *> *callStackSymbols = exception.callStackSymbols ?: @[];
            NSDictionary<NSErrorUserInfoKey, id> *userInfo = @{
                NSLocalizedDescriptionKey: reason,
                NSLocalizedFailureReasonErrorKey: name,
                @"exceptionName": name,
                @"exceptionReason": reason,
                @"callStackSymbols": callStackSymbols
            };
            *error = [NSError errorWithDomain:@"app.merian.objc-exception"
                                         code:1
                                     userInfo:userInfo];
        }
        return NO;
    }
}
