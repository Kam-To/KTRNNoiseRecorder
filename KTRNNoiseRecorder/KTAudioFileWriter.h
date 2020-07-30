//
//  KTAudioFileWriter.h
//  KTRNNoiseRecorder
//
//  Created by Kam on 2020/7/29.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

NS_ASSUME_NONNULL_BEGIN

@interface KTAudioFileWriter : NSObject
@property (nonatomic, assign) BOOL denoise;
- (instancetype)initWithPath:(NSString *)path foramtDes:(AudioStreamBasicDescription *)format;
- (void)wirteData:(void * const)mAudioData size:(UInt32)mAudioDataByteSize;
- (void)endWrittingWithCompeletion:(void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END
