//
//  KTAudioFileWriter.m
//  KTRNNoiseRecorder
//
//  Created by Kam on 2020/7/29.
//

#import "KTAudioFileWriter.h"
#include "rnnoise-arm/rnnoise.h"

@interface KTAudioFileWriter ()
@property (nonatomic, assign) AudioFileID audioFile;
@property (nonatomic, assign) SInt64 mCurrentPacket;
@property (nonatomic, strong) dispatch_queue_t testQueue;
@property (nonatomic, strong) NSMutableArray<NSData *> *dataArray;
@property (nonatomic, assign) DenoiseState *dst;
@property (nonatomic, assign) AudioStreamBasicDescription format;
@end

static const NSUInteger kFrameSize = 480;

@implementation KTAudioFileWriter

- (instancetype)initWithPath:(NSString *)path foramtDes:(AudioStreamBasicDescription *)format {
    if (self = [super init]) {
        AudioFileTypeID fileType = kAudioFileWAVEType;
        CFURLRef audioFileURL = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path.UTF8String, (CFIndex)strlen(path.UTF8String), false);
        AudioFileCreateWithURL(audioFileURL, fileType, format, kAudioFileFlags_DontPageAlignAudioData | kAudioFileFlags_EraseFile, &_audioFile);
        _mCurrentPacket = 0;
        _testQueue = dispatch_queue_create("com.audioFileWriter.aha", NULL);
        _dataArray = [NSMutableArray new];
        _dst = rnnoise_create();
        _format = *format;
    }
    return self;
}

- (void)dealloc {
    if (_dst) {
        rnnoise_destroy(_dst);
        _dst = NULL;
    }
}

- (void)wirteData:(void * const)mAudioData size:(UInt32)mAudioDataByteSize {
    NSData *data = [NSData dataWithBytes:mAudioData length:mAudioDataByteSize];
    dispatch_async(_testQueue, ^{
        [self.dataArray addObject:data];
        [self __process];
    });
}

- (BOOL)__canConsume {
    NSUInteger dataSize = 0;
    UInt32 sizeToProcess = kFrameSize * sizeof(short);
    for (NSData *data in _dataArray) {
        dataSize += data.length;
        if (dataSize >= sizeToProcess) return YES;
    }
    return NO;
}

- (void)__process{
    while ([self __canConsume]) {
        
        NSData *data = self.dataArray[0];
        [self.dataArray removeObjectAtIndex:0];
        
        UInt32 sizeToProcess = kFrameSize * sizeof(short);
        NSUInteger times =  data.length / sizeToProcess;
        NSUInteger remain = data.length % sizeToProcess;
        
        const Byte *rawData = (const Byte *)data.bytes;
        float *x = NULL;
        if (_denoise) x = malloc(kFrameSize * sizeof(float));
        short *buffer = malloc(kFrameSize * sizeof(short));
        
        UInt32 inNumPackets = sizeToProcess / self.format.mBytesPerPacket;
        
        for (UInt32 t = 0; t < times; t++) {
            memcpy(buffer, rawData + t * sizeToProcess, sizeToProcess);
            
            if (_denoise) {
                for (UInt32 j = 0; j < kFrameSize; j++) x[j] = buffer[j];
                rnnoise_process_frame(_dst, x, x);
                for (UInt32 j = 0; j < kFrameSize; j++) buffer[j] = x[j];
            }

            /// !!!: opt
            OSStatus st = AudioFileWritePackets(self.audioFile, false, sizeToProcess, NULL, self.mCurrentPacket, &inNumPackets, buffer);
            if (st != noErr) printf("error on writing\n");
            self.mCurrentPacket += inNumPackets;
        }
        
        free(buffer);
        if (x) free(x);
        
        NSMutableData *head = nil;
        if (remain > 0) head = [NSMutableData dataWithBytes:(rawData + times * sizeToProcess) length:remain];
        if (head) {
            if (self.dataArray.count) {
                NSData *tail = self.dataArray[0];
                [self.dataArray removeObjectAtIndex:0];
                [head appendData:tail];
                [self.dataArray insertObject:head atIndex:0];
            } else {
                [self.dataArray addObject:head];
            }
        }
    }
}

- (void)endWrittingWithCompeletion:(void (^)(void))completion {
    dispatch_async(_testQueue, ^{
        [self __process];
        NSData *data = self.dataArray.firstObject;
        [self.dataArray removeAllObjects];
        
        UInt32 inNumPackets = (UInt32)data.length / self.format.mBytesPerPacket;
        OSStatus st = AudioFileWritePackets(self.audioFile, false, (UInt32)data.length, NULL, self.mCurrentPacket, &inNumPackets, data.bytes);
        if (st != noErr) printf("error on ending writing\n");
        self.mCurrentPacket += inNumPackets;
        st = AudioFileClose(self.audioFile);
        if (st != noErr) printf("error on ending writing\n");
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

@end
