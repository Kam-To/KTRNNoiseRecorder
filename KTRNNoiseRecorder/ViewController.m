//
//  ViewController.m
//  KTRNNoiseRecorder
//
//  Created by Kam on 2020/7/29.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "KTRNNoiseRecorder.h"

#import "rnnoise.h"

#define FRAME_SIZE 480

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *desLabel;
@property (weak, nonatomic) IBOutlet UISwitch *swicher;
@property (weak, nonatomic) IBOutlet UIButton *recordButton;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (nonatomic, strong) KTRNNoiseRecorder *recorder;
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, strong) NSString *filePath;
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

    NSError *error = nil;
    NSString *processed = _filePath;
    
//    NSString *processed = [NSSearchPathForDirectoriesInDomains(9, 1, 1).firstObject stringByAppendingPathComponent:@"p_file.wav"];
//    NSTimeInterval t1 = CFAbsoluteTimeGetCurrent();
//    original_demo_convert_test(_filePath.UTF8String, processed.UTF8String);
//    NSTimeInterval t2 = CFAbsoluteTimeGetCurrent();
//    printf("Cost   %lf\n", t2 - t1);
    
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:processed error:nil];
    self.desLabel.text = fileAttributes.description;
    
    NSURL *url = [NSURL fileURLWithPath:processed];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                     withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                                           error:&error];

    _player = [[AVAudioPlayer alloc] initWithContentsOfURL:url error:&error];
    [_player play];
}

- (void)__updateState:(BOOL)isRecording {
    _swicher.enabled = !isRecording;
    _playButton.enabled = !isRecording;
}

static void original_demo_convert_test(const char *inputPath, const char *outputPath) {
    int i;
    float x[FRAME_SIZE];
    FILE *f1, *fout;

    DenoiseState *st = rnnoise_create();

    f1 = fopen(inputPath, "r");
    fout = fopen(outputPath, "w");

    // 44bytes header of WAV file
    Byte d[44];
    fread(d, sizeof(Byte), sizeof(d), f1);
    fwrite(d, sizeof(Byte), sizeof(d), fout);

    while (1) {
        short tmp[FRAME_SIZE];
        fread(tmp, sizeof(short), FRAME_SIZE, f1);
        if (feof(f1)) break;
        for (i=0;i<FRAME_SIZE;i++) x[i] = tmp[i];
        rnnoise_process_frame(st, x, x);
        for (i=0;i<FRAME_SIZE;i++) tmp[i] = x[i];
        fwrite(tmp, sizeof(short), FRAME_SIZE, fout);
    }
    
    rnnoise_destroy(st);
    fclose(f1);
    fclose(fout);
}


@end
