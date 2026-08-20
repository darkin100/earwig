#import "include/EarwigExceptionCatcher.h"

NSErrorDomain const EarwigObjCExceptionDomain = @"io.darkin.earwig.ObjCException";

BOOL EarwigCatchException(void (NS_NOESCAPE ^block)(void),
                          NSError * _Nullable * _Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSString *reason = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:EarwigObjCExceptionDomain
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: reason,
                @"ExceptionName": exception.name,
            }];
        }
        return NO;
    }
}
