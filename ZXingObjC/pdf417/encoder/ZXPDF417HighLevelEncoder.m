/*
 * Copyright 2006 Jeremias Maerki in part, and ZXing Authors in part
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "ZXByteArray.h"
#import "ZXErrors.h"
#import "ZXPDF417HighLevelEncoder.h"

/**
 * code for Text compaction
 */
const int ZX_PDF417_TEXT_COMPACTION = 0;

/**
 * code for Byte compaction
 */
const int ZX_PDF417_BYTE_COMPACTION = 1;

/**
 * code for Numeric compaction
 */
const int ZX_PDF417_NUMERIC_COMPACTION = 2;

/**
 * Text compaction submode Alpha
 */
const int ZX_PDF417_SUBMODE_ALPHA = 0;

/**
 * Text compaction submode Lower
 */
const int ZX_PDF417_SUBMODE_LOWER = 1;

/**
 * Text compaction submode Mixed
 */
const int ZX_PDF417_SUBMODE_MIXED = 2;

/**
 * Text compaction submode Punctuation
 */
const int ZX_PDF417_SUBMODE_PUNCTUATION = 3;

/**
 * mode latch to Text Compaction mode
 */
const int ZX_PDF417_LATCH_TO_TEXT = 900;

/**
 * mode latch to Byte Compaction mode (number of characters NOT a multiple of 6)
 */
const int ZX_PDF417_LATCH_TO_BYTE_PADDED = 901;

/**
 * mode latch to Numeric Compaction mode
 */
const int ZX_PDF417_LATCH_TO_NUMERIC = 902;

/**
 * mode shift to Byte Compaction mode
 */
const int ZX_PDF417_SHIFT_TO_BYTE = 913;

/**
 * mode latch to Byte Compaction mode (number of characters a multiple of 6)
 */
const int ZX_PDF417_LATCH_TO_BYTE = 924;

/**
 * Raw code table for text compaction Mixed sub-mode
 */
const int8_t ZX_PDF417_TEXT_MIXED_RAW[] = {
  48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 38, 13, 9, 44, 58,
  35, 45, 46, 36, 47, 43, 37, 42, 61, 94, 0, 32, 0, 0, 0};

/**
 * Raw code table for text compaction: Punctuation sub-mode
 */
const int8_t ZX_PDF417_TEXT_PUNCTUATION_RAW[] = {
  59, 60, 62, 64, 91, 92, 93, 95, 96, 126, 33, 13, 9, 44, 58,
  10, 45, 46, 36, 47, 34, 124, 42, 40, 41, 63, 123, 125, 39, 0};

const int ZX_PDF417_MIXED_TABLE_LEN = 128;
unichar ZX_PDF417_MIXED_TABLE[ZX_PDF417_MIXED_TABLE_LEN];

const int ZX_PDF417_PUNCTUATION_LEN = 128;
unichar ZX_PDF417_PUNCTUATION[ZX_PDF417_PUNCTUATION_LEN];

const NSStringEncoding ZX_PDF417_DEFAULT_ENCODING = (NSStringEncoding) 0x80000400;

@implementation ZXPDF417HighLevelEncoder

+ (void)initialize {
  //Construct inverse lookups
  for (int i = 0; i < ZX_PDF417_MIXED_TABLE_LEN; i++) {
    ZX_PDF417_MIXED_TABLE[i] = 0xFF;
  }
  for (int8_t i = 0; i < sizeof(ZX_PDF417_TEXT_MIXED_RAW) / sizeof(int8_t); i++) {
    int8_t b = ZX_PDF417_TEXT_MIXED_RAW[i];
    if (b > 0) {
      ZX_PDF417_MIXED_TABLE[b] = i;
    }
  }
  for (int i = 0; i < ZX_PDF417_PUNCTUATION_LEN; i++) {
    ZX_PDF417_PUNCTUATION[i] = 0xFF;
  }
  for (int8_t i = 0; i < sizeof(ZX_PDF417_TEXT_PUNCTUATION_RAW) / sizeof(int8_t); i++) {
    int8_t b = ZX_PDF417_TEXT_PUNCTUATION_RAW[i];
    if (b > 0) {
      ZX_PDF417_PUNCTUATION[b] = i;
    }
  }
}

/**
 * Converts the message to a byte array using the default encoding (Cp437) as defined by the
 * specification
 *
 * @param msg the message
 * @return the byte array of the message
 */
+ (ZXByteArray *)bytesForMessage:(NSString *)msg {
  NSData *data = [msg dataUsingEncoding:ZX_PDF417_DEFAULT_ENCODING];
  int8_t *bytes = (int8_t *)[data bytes];
  ZXByteArray *byteArray = [[ZXByteArray alloc] initWithLength:(unsigned int)[data length]];
  memcpy(byteArray.array, bytes, [data length] * sizeof(int8_t));
  return byteArray;
}

+ (NSString *)encodeHighLevel:(NSString *)msg compaction:(ZXCompaction)compaction error:(NSError **)error {
  ZXByteArray *bytes = nil; //Fill later and only if needed

  //the codewords 0..928 are encoded as Unicode characters
  NSMutableString *sb = [NSMutableString stringWithCapacity:msg.length];

  NSUInteger len = msg.length;
  int p = 0;
  int textSubMode = ZX_PDF417_SUBMODE_ALPHA;

  // User selected encoding mode
  if (compaction == ZXCompactionText) {
    [self encodeText:msg startpos:p count:(int)len buffer:sb initialSubmode:textSubMode];
  } else if (compaction == ZXCompactionByte) {
    bytes = [self bytesForMessage:msg];
    [self encodeBinary:bytes startpos:p count:(int)msg.length startmode:ZX_PDF417_BYTE_COMPACTION buffer:sb];
  } else if (compaction == ZXCompactionNumeric) {
    [sb appendFormat:@"%C", (unichar) ZX_PDF417_LATCH_TO_NUMERIC];
    [self encodeNumeric:msg startpos:p count:(int)len buffer:sb];
  } else {
    int encodingMode = ZX_PDF417_TEXT_COMPACTION; //Default mode, see 4.4.2.1
    while (p < len) {
      int n = [self determineConsecutiveDigitCount:msg startpos:p];
      if (n >= 13) {
        [sb appendFormat:@"%C", (unichar) ZX_PDF417_LATCH_TO_NUMERIC];
        encodingMode = ZX_PDF417_NUMERIC_COMPACTION;
        textSubMode = ZX_PDF417_SUBMODE_ALPHA; //Reset after latch
        [self encodeNumeric:msg startpos:p count:n buffer:sb];
        p += n;
      } else {
        int t = [self determineConsecutiveTextCount:msg startpos:p];
        if (t >= 5 || n == len) {
          if (encodingMode != ZX_PDF417_TEXT_COMPACTION) {
            [sb appendFormat:@"%C", (unichar) ZX_PDF417_LATCH_TO_TEXT];
            encodingMode = ZX_PDF417_TEXT_COMPACTION;
            textSubMode = ZX_PDF417_SUBMODE_ALPHA; //start with submode alpha after latch
          }
          textSubMode = [self encodeText:msg startpos:p count:t buffer:sb initialSubmode:textSubMode];
          p += t;
        } else {
          if (bytes == NULL) {
            bytes = [self bytesForMessage:msg];
          }
          int b = [self determineConsecutiveBinaryCount:msg bytes:bytes startpos:p error:error];
          if (b == -1) {
            return nil;
          } else if (b == 0) {
            b = 1;
          }
          if (b == 1 && encodingMode == ZX_PDF417_TEXT_COMPACTION) {
            //Switch for one byte (instead of latch)
            [self encodeBinary:bytes startpos:p count:1 startmode:ZX_PDF417_TEXT_COMPACTION buffer:sb];
          } else {
            //Mode latch performed by encodeBinary
            [self encodeBinary:bytes startpos:p count:b startmode:encodingMode buffer:sb];
            encodingMode = ZX_PDF417_BYTE_COMPACTION;
            textSubMode = ZX_PDF417_SUBMODE_ALPHA; //Reset after latch
          }
          p += b;
        }
      }
    }
  }

  return sb;
}

/**
 * Encode parts of the message using Text Compaction as described in ISO/IEC 15438:2001(E),
 * chapter 4.4.2.
 *
 * @param msg            the message
 * @param startpos       the start position within the message
 * @param count          the number of characters to encode
 * @param sb             receives the encoded codewords
 * @param initialSubmode should normally be SUBMODE_ALPHA
 * @return the text submode in which this method ends
 */
+ (int)encodeText:(NSString *)msg startpos:(int)startpos count:(int)count buffer:(NSMutableString *)sb initialSubmode:(int)initialSubmode {
  NSMutableString *tmp = [NSMutableString stringWithCapacity:count];
  int submode = initialSubmode;
  int idx = 0;
  while (true) {
    unichar ch = [msg characterAtIndex:startpos + idx];
    switch (submode) {
      case ZX_PDF417_SUBMODE_ALPHA:
        if ([self isAlphaUpper:ch]) {
          if (ch == ' ') {
            [tmp appendFormat:@"%C", (unichar) 26]; //space
          } else {
            [tmp appendFormat:@"%C", (unichar) (ch - 65)];
          }
        } else {
          if ([self isAlphaLower:ch]) {
            submode = ZX_PDF417_SUBMODE_LOWER;
            [tmp appendFormat:@"%C", (unichar) 27]; //ll
            continue;
          } else if ([self isMixed:ch]) {
            submode = ZX_PDF417_SUBMODE_MIXED;
            [tmp appendFormat:@"%C", (unichar) 28]; //ml
            continue;
          } else {
            [tmp appendFormat:@"%C", (unichar) 29]; //ps
            [tmp appendFormat:@"%C", ZX_PDF417_PUNCTUATION[ch]];
            break;
          }
        }
        break;
      case ZX_PDF417_SUBMODE_LOWER:
        if ([self isAlphaLower:ch]) {
          if (ch == ' ') {
            [tmp appendFormat:@"%C", (unichar) 26]; //space
          } else {
            [tmp appendFormat:@"%C", (unichar) (ch - 97)];
          }
        } else {
          if ([self isAlphaUpper:ch]) {
            [tmp appendFormat:@"%C", (unichar) 27]; //as
            [tmp appendFormat:@"%C", (unichar) (ch - 65)];
            //space cannot happen here, it is also in "Lower"
            break;
          } else if ([self isMixed:ch]) {
            submode = ZX_PDF417_SUBMODE_MIXED;
            [tmp appendFormat:@"%C", (unichar) 28]; //ml
            continue;
          } else {
            [tmp appendFormat:@"%C", (unichar) 29]; //ps
            [tmp appendFormat:@"%C", ZX_PDF417_PUNCTUATION[ch]];
            break;
          }
        }
        break;
      case ZX_PDF417_SUBMODE_MIXED:
        if ([self isMixed:ch]) {
          [tmp appendFormat:@"%C", ZX_PDF417_MIXED_TABLE[ch]]; //as
        } else {
          if ([self isAlphaUpper:ch]) {
            submode = ZX_PDF417_SUBMODE_ALPHA;
            [tmp appendFormat:@"%C", (unichar) 28]; //al
            continue;
          } else if ([self isAlphaLower:ch]) {
            submode = ZX_PDF417_SUBMODE_LOWER;
            [tmp appendFormat:@"%C", (unichar) 27]; //ll
            continue;
          } else {
            if (startpos + idx + 1 < count) {
              char next = [msg characterAtIndex:startpos + idx + 1];
              if ([self isPunctuation:next]) {
                submode = ZX_PDF417_SUBMODE_PUNCTUATION;
                [tmp appendFormat:@"%C", (unichar) 25]; //pl
                continue;
              }
            }
            [tmp appendFormat:@"%C", (unichar) 29]; //ps
            [tmp appendFormat:@"%C", ZX_PDF417_PUNCTUATION[ch]];
          }
        }
        break;
      default: //ZX_PDF417_SUBMODE_PUNCTUATION
        if ([self isPunctuation:ch]) {
          [tmp appendFormat:@"%C", ZX_PDF417_PUNCTUATION[ch]];
        } else {
          submode = ZX_PDF417_SUBMODE_ALPHA;
          [tmp appendFormat:@"%C", (unichar) 29]; //al
          continue;
        }
    }
    idx++;
    if (idx >= count) {
      break;
    }
  }
  unichar h = 0;
  NSUInteger len = tmp.length;
  for (int i = 0; i < len; i++) {
    BOOL odd = (i % 2) != 0;
    if (odd) {
      h = (unichar) ((h * 30) + [tmp characterAtIndex:i]);
      [sb appendFormat:@"%C", h];
    } else {
      h = [tmp characterAtIndex:i];
    }
  }
  if ((len % 2) != 0) {
    [sb appendFormat:@"%C", (unichar) ((h * 30) + 29)]; //ps
  }
  return submode;
}

/**
 * Encode parts of the message using Byte Compaction as described in ISO/IEC 15438:2001(E),
 * chapter 4.4.3. The Unicode characters will be converted to binary using the cp437
 * codepage.
 *
 * @param bytes     the message converted to a byte array
 * @param startpos  the start position within the message
 * @param count     the number of bytes to encode
 * @param startmode the mode from which this method starts
 * @param sb        receives the encoded codewords
 */
+ (void)encodeBinary:(ZXByteArray *)bytes startpos:(int)startpos count:(int)count startmode:(int)startmode buffer:(NSMutableString *)sb {
  if (count == 1 && startmode == ZX_PDF417_TEXT_COMPACTION) {
    [sb appendFormat:@"%C", (unichar) ZX_PDF417_SHIFT_TO_BYTE];
  } else {
    BOOL sixpack = ((count % 6) == 0);
    if (sixpack) {
      [sb appendFormat:@"%C", (unichar) ZX_PDF417_LATCH_TO_BYTE];
    } else {
      [sb appendFormat:@"%C", (unichar) ZX_PDF417_LATCH_TO_BYTE_PADDED];
    }
  }

  int idx = startpos;
  // Encode sixpacks
  if (count >= 6) {
    const int charsLen = 5;
    unichar chars[charsLen];
    memset(chars, 0, charsLen * sizeof(unichar));
    while ((startpos + count - idx) >= 6) {
      long t = 0;
      for (int i = 0; i < 6; i++) {
        t <<= 8;
        t += bytes.array[idx + i] & 0xff;
      }
      for (int i = 0; i < 5; i++) {
        chars[i] = (unichar) (t % 900);
        t /= 900;
      }
      for (int i = charsLen - 1; i >= 0; i--) {
        [sb appendFormat:@"%C", chars[i]];
      }
      idx += 6;
    }
  }
  //Encode rest (remaining n<5 bytes if any)
  for (int i = idx; i < startpos + count; i++) {
    int ch = bytes.array[i] & 0xff;
    [sb appendFormat:@"%C", (unichar)ch];
  }
}

+ (void)encodeNumeric:(NSString *)msg startpos:(int)startpos count:(int)count buffer:(NSMutableString *)sb {
  int idx = 0;
  NSMutableString *tmp = [NSMutableString stringWithCapacity:count / 3 + 1];
  while (idx < count - 1) {
    [tmp setString:@""];
    int len = MIN(44, count - idx);
    NSString *part = [@"1" stringByAppendingString:[msg substringWithRange:NSMakeRange(startpos + idx, len)]];
    long long bigint = [part longLongValue];
    do {
      long c = bigint % 900;
      [tmp appendFormat:@"%C", (unichar) c];
      bigint /= 900;
    } while (bigint != 0);

    //Reverse temporary string
    for (int i = (int)tmp.length - 1; i >= 0; i--) {
      [sb appendFormat:@"%C", [tmp characterAtIndex:i]];
    }
    idx += len;
  }
}

+ (BOOL)isDigit:(unichar)ch {
  return ch >= '0' && ch <= '9';
}

+ (BOOL)isAlphaUpper:(unichar)ch {
  return ch == ' ' || (ch >= 'A' && ch <= 'Z');
}

+ (BOOL)isAlphaLower:(unichar)ch {
  return ch == ' ' || (ch >= 'a' && ch <= 'z');
}

+ (BOOL)isMixed:(unichar)ch {
  return ZX_PDF417_MIXED_TABLE[ch] != 0xFF;
}

+ (BOOL)isPunctuation:(unichar)ch {
  return ZX_PDF417_PUNCTUATION[ch] != 0xFF;
}

+ (BOOL)isText:(unichar)ch {
  return ch == '\t' || ch == '\n' || ch == '\r' || (ch >= 32 && ch <= 126);
}

/**
 * Determines the number of consecutive characters that are encodable using numeric compaction.
 *
 * @param msg      the message
 * @param startpos the start position within the message
 * @return the requested character count
 */
+ (int)determineConsecutiveDigitCount:(NSString *)msg startpos:(int)startpos {
  int count = 0;
  NSUInteger len = msg.length;
  int idx = startpos;
  if (idx < len) {
    char ch = [msg characterAtIndex:idx];
    while ([self isDigit:ch] && idx < len) {
      count++;
      idx++;
      if (idx < len) {
        ch = [msg characterAtIndex:idx];
      }
    }
  }
  return count;
}

/**
 * Determines the number of consecutive characters that are encodable using text compaction.
 *
 * @param msg      the message
 * @param startpos the start position within the message
 * @return the requested character count
 */
+ (int)determineConsecutiveTextCount:(NSString *)msg startpos:(int)startpos {
  NSUInteger len = msg.length;
  int idx = startpos;
  while (idx < len) {
    char ch = [msg characterAtIndex:idx];
    int numericCount = 0;
    while (numericCount < 13 && [self isDigit:ch] && idx < len) {
      numericCount++;
      idx++;
      if (idx < len) {
        ch = [msg characterAtIndex:idx];
      }
    }
    if (numericCount >= 13) {
      return idx - startpos - numericCount;
    }
    if (numericCount > 0) {
      //Heuristic: All text-encodable chars or digits are binary encodable
      continue;
    }
    ch = [msg characterAtIndex:idx];

    //Check if character is encodable
    if (![self isText:ch]) {
      break;
    }
    idx++;
  }
  return idx - startpos;
}

/**
 * Determines the number of consecutive characters that are encodable using binary compaction.
 *
 * @param msg      the message
 * @param bytes    the message converted to a byte array
 * @param startpos the start position within the message
 * @return the requested character count
 */
+ (int)determineConsecutiveBinaryCount:(NSString *)msg bytes:(ZXByteArray *)bytes startpos:(int)startpos error:(NSError **)error {
  NSUInteger len = msg.length;
  int idx = startpos;
  while (idx < len) {
    char ch = [msg characterAtIndex:idx];
    int numericCount = 0;

    while (numericCount < 13 && [self isDigit:ch]) {
      numericCount++;
      //textCount++;
      int i = idx + numericCount;
      if (i >= len) {
        break;
      }
      ch = [msg characterAtIndex:i];
    }
    if (numericCount >= 13) {
      return idx - startpos;
    }
    int textCount = 0;
    while (textCount < 5 && [self isText:ch]) {
      textCount++;
      int i = idx + textCount;
      if (i >= len) {
        break;
      }
      ch = [msg characterAtIndex:i];
    }
    if (textCount >= 5) {
      return idx - startpos;
    }
    ch = [msg characterAtIndex:idx];

    //Check if character is encodable
    //Sun returns a ASCII 63 (?) for a character that cannot be mapped. Let's hope all
    //other VMs do the same
    if (bytes.array[idx] == 63 && ch != '?') {
      NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Non-encodable character detected: %c (Unicode: %C)", ch, (unichar)ch]};

      if (error) *error = [[NSError alloc] initWithDomain:ZXErrorDomain code:ZXWriterError userInfo:userInfo];
      return -1;
    }
    idx++;
  }
  return idx - startpos;
}

@end
