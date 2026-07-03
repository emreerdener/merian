#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MerianObjCExceptionBlock)(void);

BOOL MerianCatchObjCException(MerianObjCExceptionBlock block, NSError **error);

NS_ASSUME_NONNULL_END
