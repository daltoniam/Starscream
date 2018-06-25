//////////////////////////////////////////////////////////////////////////////////////////////////
//
//  NSString+SHA1.m
//  Starscream
//
//  Created by Sergey Lem on 6/25/18.
//  Copyright (c) 2014-2016 Dalton Cherry.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//////////////////////////////////////////////////////////////////////////////////////////////////

#import "NSString+SHA1.h"
#import <CommonCrypto/CommonDigest.h>

@implementation NSString (SHA1)

- (NSString *)ss_SHA1Base64Digest {
    NSData *stringData = [self dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *digest = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(stringData.bytes, stringData.length, digest.mutableBytes);
    return [digest base64EncodedDataWithOptions:0];
}

@end
