//
//  KTRNNoiseRecorder.m
//  KTRNNoiseRecorder
//
//  Created by Kam on 2020/7/29.
//

#import "KTRNNoiseRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "rnnoise.h"

static const int kNumberBuffers = 3;
struct AQRecorderState {
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef mQueue;
    AudioQueueBufferRef mBuffers[kNumberBuffers];
    AudioFileID mAudioFile;
    
    UInt32 bufferByteSize; // for each audio queue buffer,
    //This value is calculated in these examples in the DeriveBufferSize function, after the audio queue is created and before it is started.
    
    SInt64 mCurrentPacket; // The packet index for the first packet to be written from the current audio queue buffer.
    
    DenoiseState *dst; // rnnoise
    bool mIsRunning; // A Boolean value indicating whether or not the audio queue is running.
};

@interface KTRNNoiseRecorder()
@property (nonatomic, assign) AQRecorderState aqData;
@end

@implementation KTRNNoiseRecorder

/*
 
 https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioQueueProgrammingGuide/AQRecord/RecordingAudio.html#//apple_ref/doc/uid/TP40005343-CH4-SW1
 To add recording functionality to your application, you typically perform the following steps:
1. Define a custom structure to manage state, format, and path information.
2. Write an audio queue callback function to perform the actual recording.
3 .Optionally write code to determine a good size for the audio queue buffers. Write code to work with magic cookies, if you’ll be recording in a format that uses cookies.
4. Fill the fields of the custom structure. This includes specifying the data stream that the audio queue sends to the file it’s recording into, as well as the path to that file.
5. Create a recording audio queue and ask it to create a set of audio queue buffers. Also create a file to record into.
6. Tell the audio queue to start recording.
 
 When done, tell the audio queue to stop and then dispose of it. The audio queue disposes of its buffers.
 The remainder of this chapter describes each of these steps in detail.

 */

- (void)startRecordingAt:(NSString *)path {
    if (![self __activeAudioSession]) return;
     
    bzero(&_aqData, sizeof(AQRecorderState));
    _aqData.mDataFormat.mFormatID         = kAudioFormatLinearPCM;
    _aqData.mDataFormat.mSampleRate       = 48000;
    _aqData.mDataFormat.mChannelsPerFrame = 1;
    _aqData.mDataFormat.mBitsPerChannel   = 16;
    _aqData.mDataFormat.mBytesPerPacket   =
    _aqData.mDataFormat.mBytesPerFrame =
    _aqData.mDataFormat.mChannelsPerFrame * sizeof (SInt16);

    // Frames per packet (linear PCM, for example, uses one frame per packet)
    _aqData.mDataFormat.mFramesPerPacket  = 1;
    _aqData.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    
    _aqData.dst = rnnoise_create();
    
    /// !!!: Create a Recording Audio Queue
    AudioQueueNewInput(&_aqData.mDataFormat, HandleInputBuffer, &_aqData, NULL, kCFRunLoopCommonModes, 0, &_aqData.mQueue);
    
    // 用 mQueue 的格式填充一下自己的，更完整
    UInt32 dataFormatSize = sizeof(_aqData.mDataFormat);
    AudioQueueGetProperty(_aqData.mQueue, kAudioQueueProperty_StreamDescription, &_aqData.mDataFormat, &dataFormatSize);
    
    
    OSStatus st = noErr;
    
    /// !!!: Create an Audio File
    AudioFileTypeID fileType = kAudioFileWAVEType;
    CFURLRef audioFileURL = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path.UTF8String, (CFIndex)strlen(path.UTF8String), false);
    
    /// !!!: kAudioFileFlags_DontPageAlignAudioData
    st = AudioFileCreateWithURL(audioFileURL, fileType, &_aqData.mDataFormat, // 实际上我并不想直接写 PCM
                                kAudioFileFlags_DontPageAlignAudioData | kAudioFileFlags_EraseFile, &_aqData.mAudioFile);
        
    /// !!!: Set an Audio Queue Buffer Size
    DeriveBufferSize(_aqData.mQueue, _aqData.mDataFormat, 0.5, &_aqData.bufferByteSize);

    /// !!!: Prepare a Set of Audio Queue Buffers
    for (int i = 0; i < kNumberBuffers; i++) {
        st = AudioQueueAllocateBuffer(_aqData.mQueue, _aqData.bufferByteSize, &_aqData.mBuffers[i]);
        if (st != noErr) NSLog(@"error on allocating buffer  %d, %d", st, i);
        st = AudioQueueEnqueueBuffer(_aqData.mQueue, _aqData.mBuffers[i], 0, NULL);
        if (st != noErr) NSLog(@"error on enqueu buffer  %d, %d", st, i);
    }
    
    SetMagicCookieForFile(_aqData.mQueue, _aqData.mAudioFile);

    /// !!!: Record Audio
    _aqData.mCurrentPacket = 0;
    _aqData.mIsRunning = true;
    AudioQueueStart(_aqData.mQueue, NULL);
}

- (void)endRecording {

    OSStatus st = AudioQueueStop(_aqData.mQueue, true);
    if (st == noErr) {
        _aqData.mIsRunning = false;
     
        AudioQueueDispose(_aqData.mQueue, true);

        AudioFileClose(_aqData.mAudioFile);
        
        if (_aqData.dst) {
            rnnoise_destroy(_aqData.dst);
            _aqData.dst = NULL;
        }
    }
}

#pragma mark - Private
- (BOOL)__activeAudioSession {
    NSError *error = nil;
    BOOL ret = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryRecord error:&error];
    if (!ret) {
        NSLog(@"set category error(%@)", error);
        return ret;
    }
    
    ret = [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (!ret) NSLog(@"active session error(%@)", error);
    return ret;
}

// It derives a buffer size large enough to hold a given duration of audio data.
static void DeriveBufferSize(AudioQueueRef audioQueue, AudioStreamBasicDescription &ASBDescription, Float64 seconds, UInt32 *outBufferSize) {
    static const int maxBufferSize = 0x50000;
    int maxPacketSize = ASBDescription.mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
 
    Float64 numBytesForTime = ASBDescription.mSampleRate * maxPacketSize * seconds;
    *outBufferSize = UInt32 (numBytesForTime < maxBufferSize ? numBytesForTime : maxBufferSize);
}

static OSStatus SetMagicCookieForFile(AudioQueueRef inQueue, AudioFileID inFile) {
    UInt32 cookieSize;
    OSStatus st = AudioQueueGetPropertySize(inQueue, kAudioQueueProperty_MagicCookie, &cookieSize);
    if (st == noErr) {
        char *magicCookie = (char *)malloc(cookieSize);
        st = AudioQueueGetProperty(inQueue, kAudioQueueProperty_MagicCookie, magicCookie, &cookieSize);
        if (st == noErr) {
            st = AudioFileSetProperty (inFile, kAudioFilePropertyMagicCookieData, cookieSize, magicCookie );
        }
        free (magicCookie);
    }
    return st;
}

static void HandleInputBuffer(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer,
                            const AudioTimeStamp *inStartTime, UInt32 inNumPackets, const AudioStreamPacketDescription *inPacketDesc) {
    
    struct AQRecorderState *pAqData = (struct AQRecorderState *)aqData;
    
    /*
     CBR : inNumPackets =  [total bytes of data in the buffer]  / [(constant) number of bytes per packet]
     VBR : the audio queue supplies the number of packets in the buffer when it invokes the callback.
     */
    
    // 录制 PCM CBR 需要计算
    if (inNumPackets == 0 && pAqData->mDataFormat.mBytesPerPacket != 0) {
        inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
    }

    UInt32 dataSize = inBuffer->mAudioDataByteSize;
    void *dataToWrite = inBuffer->mAudioData;
    
    /// !!!: ⚠️⚠️⚠️⚠️⚠️  error here
    BOOL doDeNoise = pAqData->dst && (dataSize > 0);
    if (doDeNoise) {
        dataToWrite = malloc(dataSize);
        memcpy(dataToWrite, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
        
        static const UInt32 kFrameSize = 480;
        float x[kFrameSize];
        UInt32 times = dataSize / kFrameSize;
        UInt32 remain = dataSize % kFrameSize;
        printf("bytes %u\n", dataSize); // 500
        printf("    |_ times %u\n", times); // 500 % 480 = 1
        printf("    |_ remain %u\n", remain); // 500 / 480 = 20
        
        int8_t *cur = (int8_t *)dataToWrite;
        for (UInt32 i = 0; i < times; i++) {
            cur = ((int8_t *)dataToWrite + i * kFrameSize);
            for (UInt32 j = 0; j < kFrameSize; j++) x[j] = ((short *)(cur))[j];
            rnnoise_process_frame(pAqData->dst, x, x);
            for (UInt32 j = 0; j < kFrameSize; j++) ((short *)(cur))[j] = x[j];
        }
        
        cur = ((int8_t *)dataToWrite + times * kFrameSize);
        for (UInt32 i = 0; i < remain; i++) x[i] = ((short *)(cur))[i];
        rnnoise_process_frame(pAqData->dst, x, x);
        for (UInt32 i = 0; i < remain; i++) ((short *)(cur))[i] = x[i];
    }
        
    // 写入 mAudioData (byteSize, packet)
    OSStatus st = AudioFileWritePackets(pAqData->mAudioFile, false, dataSize, inPacketDesc,
                                        pAqData->mCurrentPacket, &inNumPackets, dataToWrite);
    
    if (doDeNoise) free(dataToWrite);
    if (st == noErr) {
        pAqData->mCurrentPacket += inNumPackets; // 实际写入的 packet 数目
    } else {
        printf("write packets error %d\n", st);
    }
    
    if (pAqData->mIsRunning == 0) return;

    // Adds a buffer to the buffer queue of a recording or playback audio queue.
    AudioQueueEnqueueBuffer(pAqData->mQueue, inBuffer, 0, NULL);
}

@end
