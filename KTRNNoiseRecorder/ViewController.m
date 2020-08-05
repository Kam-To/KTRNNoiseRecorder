//
//  ViewController.m
//  KTRNNoiseRecorder
//
//  Created by Kam on 2020/7/29.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "KTRNNoiseRecorder.h"
#import "AudioFileConvertOperation.h"

#import "rnnoise.h"

#define FRAME_SIZE 480

@interface ViewController () <AudioFileConvertOperationDelegate>
@property (weak, nonatomic) IBOutlet UILabel *desLabel;
@property (weak, nonatomic) IBOutlet UISwitch *swicher;
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (nonatomic, strong) KTRNNoiseRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) AudioFileConvertOperation *op;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _recorder = [KTRNNoiseRecorder new];
    _filePath = [NSSearchPathForDirectoriesInDomains(9, 1, 1).firstObject stringByAppendingPathComponent:@"file.wav"];
}

- (IBAction)switchAction:(UISwitch *)sender {
    _recorder.denoise = sender.isOn;
}

- (IBAction)recordAction:(UIButton *)sender {
    NSString *title = sender.titleLabel.text;
    BOOL doRecord = [title isEqualToString:@"Record"];
    if (doRecord) {
        [_recorder startRecordingAt:_filePath];
        [sender setTitle:@"Stop" forState:UIControlStateNormal];
    } else {
        [_recorder endRecording];
        [sender setTitle:@"Record" forState:UIControlStateNormal];
    }
    [self __updateState:doRecord];
}

- (IBAction)playAction:(id)sender {

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        NSString *processed = [NSSearchPathForDirectoriesInDomains(9, 1, 1).firstObject stringByAppendingPathComponent:@"p_file.caf"];
        self.op = [[AudioFileConvertOperation alloc] initWithSourceURL:[NSURL fileURLWithPath:self.filePath]
                                                        destinationURL:[NSURL fileURLWithPath:processed]
                                                            sampleRate:44100.0
                                                          outputFormat:kAudioFormatMPEG4AAC];
        self.op.delegate = self;
        [self.op start];
    });
}

- (void)__updateState:(BOOL)isRecording {
    _swicher.enabled = !isRecording;
    _playButton.enabled = !isRecording;
}

#pragma mark - AudioFileConvertOperationDelegate
- (void)audioFileConvertOperation:(AudioFileConvertOperation *)audioFileConvertOperation didEncounterError:(NSError *)error {
    
}

- (void)audioFileConvertOperation:(AudioFileConvertOperation *)audioFileConvertOperation didCompleteWithURL:(NSURL *)destinationURL {
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *error = nil;
        NSString *processed = [NSSearchPathForDirectoriesInDomains(9, 1, 1).firstObject stringByAppendingPathComponent:@"p_file.caf"];
        NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:processed error:&error];
        self.desLabel.text = fileAttributes.description;

        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                         withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                                               error:&error];
        
        self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:destinationURL error:&error];
        [self.player play];
    });
}


@end
