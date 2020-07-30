//
//  KTRNNoiseRecorder.h
//  KTRNNoiseRecorder
//
//  Created by Kam on 2020/7/29.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KTRNNoiseRecorder : NSObject
@property (nonatomic, assign) BOOL denoise; // default is NO
- (void)startRecordingAt:(NSString *)path;
- (void)endRecording;
@end

NS_ASSUME_NONNULL_END
