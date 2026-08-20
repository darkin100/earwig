#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Domain for NSErrors converted from raised NSExceptions.
extern NSErrorDomain const EarwigObjCExceptionDomain;

/// Runs `block`, converting any raised NSException into an NSError.
///
/// Some AVFoundation entry points (notably
/// -[AVAudioNode installTapOnBus:bufferSize:format:block:]) report invalid
/// audio formats by raising an Objective-C exception rather than returning an
/// error. Swift cannot catch those, so an uncaught one aborts the process.
/// Wrapping such a call in this shim turns it into an ordinary Swift `throw`.
///
/// Returns YES when `block` ran to completion, NO when it raised.
BOOL EarwigCatchException(void (NS_NOESCAPE ^block)(void),
                          NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
