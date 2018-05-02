//
//  ViewController.m
//  ABPMCompressCheck
//
//  Created by Realank on 2017/12/18.
//  Copyright © 2017年 iHealth. All rights reserved.
//

#import "ViewController.h"
#define BufferSize 1024*64
@interface ViewController()
@property (unsafe_unretained) IBOutlet NSTextView *rawFileTV;
@property (unsafe_unretained) IBOutlet NSTextView *compressedFileTV;
@property (weak) IBOutlet NSTextField *resultLabel;

@property (nonatomic, strong) NSString* rawContentString;
@property (nonatomic, strong) NSString* compressedContentString;

@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    _resultLabel.stringValue = @"";
}

- (void)setRawContentString:(NSString *)rawContentString{
    _rawContentString = rawContentString;
    _rawFileTV.string = rawContentString;
}

- (void)setCompressedContentString:(NSString *)compressedContentString{
    _compressedContentString = compressedContentString;
    _compressedFileTV.string = compressedContentString;
}

- (void)openFile:(BOOL)compressedFile{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    __weak typeof(self)weakSelf = self;
    //是否可以创建文件夹
    panel.canCreateDirectories = NO;
    //是否可以选择文件夹
    panel.canChooseDirectories = NO;
    //是否可以选择文件
    panel.canChooseFiles = YES;
    
    //是否可以多选
    [panel setAllowsMultipleSelection:NO];
    
    //显示
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSInteger result) {
        //是否点击open 按钮
        if (result == NSModalResponseOK) {
            //NSURL *pathUrl = [panel URL];
            NSString *pathString = [panel.URLs.firstObject path];
            NSLog(@"open file %@",pathString);
            NSString* content = [[NSString alloc] initWithContentsOfFile:pathString encoding:NSUTF8StringEncoding error:nil];
            if (compressedFile) {
                NSString* cleanContent=[content stringByReplacingOccurrencesOfString:@" " withString:@""];
                cleanContent=[cleanContent stringByReplacingOccurrencesOfString:@"\n" withString:@""];
                self.compressedContentString = cleanContent;
            }else{
                NSArray* numArray = [content componentsSeparatedByString:@"\n"];
                NSMutableString* hexString = [NSMutableString string];
                for (NSString* num in numArray) {
                    NSInteger intNum = [num integerValue];
                    NSString* hexNum = [NSString stringWithFormat:@"%04X",intNum];
                    [hexString appendString:hexNum];
                }
                self.rawContentString = [hexString copy];
            }
        }
        
    }];
}
- (IBAction)openRawDataFile:(id)sender {
    _resultLabel.stringValue = @"";
    [self openFile:NO];
}
- (IBAction)openCompressedFile:(id)sender {
    _resultLabel.stringValue = @"";
    [self openFile:YES];
}
- (IBAction)compare:(id)sender {
    
    if (_compressedContentString.length == 0 || _rawContentString.length == 0) {
        [self compareResultMatch:NO failReason:@"输入为空"];
        return;
    }
    NSData* compressedData = [self dataWithString:_compressedContentString];
    NSData* rawData = [self dataWithString:_rawContentString];
    const uint8_t* readBuffer = [compressedData bytes];
    uint8_t* writeBuffer = malloc(sizeof(uint8_t) * BufferSize * 4);
    size_t size = decompressFile4bit(readBuffer, compressedData.length, writeBuffer);
    if (size == -1) {
        [self compareResultMatch:NO failReason:@"解压buffer错误"];
        return;
    }else if(size == -2){
        [self compareResultMatch:NO failReason:@"CRC错误"];
        return;
    }else if (size != rawData.length) {
        [self compareResultMatch:NO failReason:@"解压长度错误"];
//        return;
    }
    const uint8_t* rawDataBytes = [rawData bytes];
    for (int i = 0; i < size; i+=2) {
        long left = (writeBuffer[i] << 8) + writeBuffer[i+1];
        long right = (rawDataBytes[i] << 8) + rawDataBytes[i+1];
        NSLog(@"%d vs %d",left,right);
        if (left != right) {
            [self compareResultMatch:NO failReason:@"内容不匹配"];
            return;
        }
        
    }
    [self compareResultMatch:YES failReason:nil];
}

- (void)compareResultMatch:(BOOL)isMatch failReason:(NSString*)reason{
    NSLog(@"result %d",isMatch);
    if (isMatch) {
        _resultLabel.stringValue = @"匹配成功";
        _resultLabel.textColor = [NSColor greenColor];
    }else{
        _resultLabel.stringValue = [NSString stringWithFormat:@"匹配失败:%@",reason];
        _resultLabel.textColor = [NSColor redColor];
    }
}

- (NSData *)dataFromHexString:(NSString *)hexString{
    NSAssert((hexString.length > 0) && (hexString.length % 2 == 0), @"hexString.length mod 2 != 0");
    NSMutableData *data = [[NSMutableData alloc] init];
    for (NSUInteger i=0; i<hexString.length; i+=2) {
        NSRange tempRange = NSMakeRange(i, 2);
        NSString *tempStr = [hexString substringWithRange:tempRange];
        NSScanner *scanner = [NSScanner scannerWithString:tempStr];
        unsigned int tempIntValue;
        [scanner scanHexInt:&tempIntValue];
        [data appendBytes:&tempIntValue length:1];
    }
    return data;
}

- (NSData*)dataWithString:(NSString*)content{
    NSString* cleanContent=[content stringByReplacingOccurrencesOfString:@" " withString:@""];
    cleanContent=[content stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    NSData* data = [self dataFromHexString:cleanContent];
    return [data copy];
}

uint8_t fourBitNum(const uint8_t* buffer,size_t index){
    size_t byteIndex = index/2;
    size_t bitIndex = index%2;
    return (buffer[byteIndex] >> (4*(!bitIndex)))&0x0f;
}

size_t decompressFile4bit(const uint8_t* compressedDataBuffer,size_t size,uint8_t* decompressedDataBuffer){

    if (compressedDataBuffer == NULL || decompressedDataBuffer == NULL) {
        printf("Buffer Error\n");
        return -1;
    }
    size_t length = (compressedDataBuffer[1] << 8) + compressedDataBuffer[0];
    uint16_t check = (compressedDataBuffer[3] << 8) + compressedDataBuffer[2];
    uint16_t previousValue = 0;
    uint16_t sum = 0;
    uint16_t twoBytesNum = 0;
    size_t writeLength = 0;

    uint16_t result = CrcCalc(compressedDataBuffer+4,size-4);
    if (result != check) {
        printf("CRC Check Failed\n");
        return -2;
    }
    
    for (int i = 8; i < size * 2; i++) {
        int8_t delta = fourBitNum(compressedDataBuffer, i) - 7;
        if (i/2 <= size - 4) {
            uint8_t fourBit1 = fourBitNum(compressedDataBuffer, i);
            uint8_t fourBit2 = fourBitNum(compressedDataBuffer, i+1);
            uint8_t fourBit3 = fourBitNum(compressedDataBuffer, i+2);
            uint8_t fourBit4 = fourBitNum(compressedDataBuffer, i+3);
            twoBytesNum = (fourBit1 << 12) + (fourBit2 << 8) + (fourBit3 << 4) + fourBit4;
        }else{
            twoBytesNum = 0x00;
        }

        if (twoBytesNum == 0xf0f0) {
            twoBytesNum = 0x00;
            uint8_t fourBit1 = fourBitNum(compressedDataBuffer, i+4);
            uint8_t fourBit2 = fourBitNum(compressedDataBuffer, i+5);
            uint8_t fourBit3 = fourBitNum(compressedDataBuffer, i+6);
            uint8_t fourBit4 = fourBitNum(compressedDataBuffer, i+7);
            uint16_t pressureData = (fourBit1 << 12) + (fourBit2 << 8) + (fourBit3 << 4) + fourBit4;
            if (pressureData == 0xffff) {
                //finish
                return writeLength;
            }else{
                decompressedDataBuffer[writeLength] = pressureData >> 8;
                decompressedDataBuffer[writeLength+1] = pressureData & 0xff;
                writeLength += 2;
                previousValue = pressureData;
                //            sum += (0xf0 + 0xf0 + fourBit1 + fourBit2 + fourBit3 + fourBit4);
                i+=7;
                continue;
            }
            
        }

        uint16_t pressureData = (previousValue + delta);
        decompressedDataBuffer[writeLength] = pressureData >> 8;
        decompressedDataBuffer[writeLength+1] = pressureData & 0xff;
        writeLength += 2;
        previousValue = pressureData;
//        sum += pressureData;
    }

    return writeLength;
}

uint16_t CrcCalc(uint8_t *data, uint16_t length)
{
    uint16_t i;
    uint8_t j;
    union
    {
        uint16_t CRCX;
        uint8_t CRCY[2];
    } CRC;
    
    CRC.CRCX = 0xFFFF;
    for(i=0; i<length; i++)
    {
        CRC.CRCY[0] = (CRC.CRCY[0] ^ data[i]);
        for(j=0; j<8; j++)
        {
            if((CRC.CRCX & 0x0001) == 1)
                CRC.CRCX = (CRC.CRCX >> 1) ^ 0x1021;
            else
                CRC.CRCX >>= 1;
        }
    }
    return CRC.CRCX;
}
- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end
