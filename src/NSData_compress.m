/*
 * Copyright � 2003,2006,2011, Bryan L Blackburn.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * 3. Neither the names Bryan L Blackburn, Withay.com, nor the names of
 *    any contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY BRYAN L BLACKBURN ``AS IS'' AND ANY
 * EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
/*
 * Compresses/decompresses data using zlib (see RFC 1950 and /usr/include/zlib.h)
 *
 * Be sure to add /usr/lib/libz.dylib to the linked frameworks, or add "-lz" to
 * 'Other Linker Flags' in the 'Linker Settings' section of the target's
 * 'Build Settings'
 */
/* NSData_compress.m */

#import "NSData_compress.h"
#include <zlib.h>

const NSInteger NSDataCompressionLevelNone = Z_NO_COMPRESSION;
const NSInteger NSDataCompressionLevelDefault = Z_DEFAULT_COMPRESSION;
const NSInteger NSDataCompressionLevelLow = Z_BEST_SPEED;
const NSInteger NSDataCompressionLevelMedium = 5;
const NSInteger NSDataCompressionLevelHigh = Z_BEST_COMPRESSION;


// Localized strings
#define NSDATA_COMPRESS_LOC_MEMERR NSLocalizedString(@"memory error", @"")


@implementation NSData (withay_compress)

static BOOL compressLoggingEnabled = YES;


/*
 * Log the warning/error, if logging enabled
 */
+ (void) logCompressMessage:(NSString *)format, ...
{
   if(compressLoggingEnabled)
   {
      va_list args;
      va_start(args, format);
      NSLogv([NSString stringWithFormat:@"NSData_compress: %@\n", format], args);
      va_end(args);
   }
}


/*
 * Enable/disable logging, class-wide, not object-wide
 */
+ (void) setCompressLogging:(BOOL)logEnabled
{
   compressLoggingEnabled = logEnabled;
}


/*
 * Compress the data, default level of compression
 */
- (NSMutableData *) compressedData
{
   return [self compressedDataAtLevel:NSDataCompressionLevelDefault];
}


/*
 * Compress the data at the given compression level; stores the original data
 * size at the end of the compressed data
 */
- (NSMutableData *) compressedDataAtLevel:(NSInteger)level
{
   /*
    * zlib says to make sure the destination has 0.1% more + 12 bytes; last
    * additional bytes to store the original size (needed for uncompress)
    */
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of sizeof
   unsigned long bufferLength = ceil((CGFloat) [self length] * 1.001) + 12 + sizeof(NSUInteger);
   NSMutableData *newData = [NSMutableData dataWithLength:bufferLength];
   if(newData != nil)
   {
      NSInteger zlibError = compress2([newData mutableBytes],
                                      &bufferLength,
                                      [self bytes],
                                      [self length],
                                      level);
      if(zlibError == Z_OK)
      {
         // Add original size to the end of the buffer, written big-endian
         *((NSUInteger *) ([newData mutableBytes] + bufferLength)) = NSSwapHostIntToBig([self length]);
#warning 64BIT: Inspect use of sizeof
         [newData setLength:bufferLength + sizeof(NSUInteger)];
      }
      else
      {
         [NSData logCompressMessage:NSLocalizedString(@"call to compress2() failed: %d - %s", @""),
                                    zlibError,
                                    zError(zlibError)];
         newData = nil;
      }
   }
   else
      [NSData logCompressMessage:NSDATA_COMPRESS_LOC_MEMERR];

   return newData;
}


/*
 * Decompress data
 */
- (NSMutableData *) uncompressedData
{
   NSMutableData *newData = nil;
   if([self isCompressedFormat])
   {
      NSUInteger originalSize = NSSwapBigIntToHost(*((NSUInteger *) ([self bytes] + [self length] -
#warning 64BIT: Inspect use of sizeof
                                                                     sizeof(NSUInteger))));
      /*
       * In the rare circumstance that data which is not compressed happens to
       * pass the checks above, we need to deal with the possibility that there
       * will be a huge number as the original size (ie, 2GB).  If that is the
       * case, NSInvalidArgumentException will be thrown.
       * There is still the possibility that uncompressed data will pass the checks
       * above and have a believable size at the end, but that will be discovered
       * in the uncompress() call.
       */
      NS_DURING
         newData = [NSMutableData dataWithLength:originalSize];
      NS_HANDLER
         if([[localException name] isEqualToString:NSInvalidArgumentException])
         {
            [NSData logCompressMessage:NSLocalizedString(@"bad size in data, is it really compressed? "
                                                         @"(reason is %@)",
                                                         @""),
                                       [localException reason]];
            NS_VALUERETURN(nil, NSMutableData *);
         }
         else
            [localException raise];   // This should NEVER happen...
      NS_ENDHANDLER
      if(newData != nil)
      {
#warning 64BIT: Inspect use of unsigned long
         unsigned long outSize = originalSize;
         NSInteger zlibError = uncompress([newData mutableBytes],
                                          &outSize,
                                          [self bytes],
#warning 64BIT: Inspect use of sizeof
                                          [self length] - sizeof(NSUInteger));
         if(zlibError != Z_OK)
         {
            [NSData logCompressMessage:NSLocalizedString(@"call to uncompress() failed: %d - %s", @""),
                                       zlibError,
                                       zError(zlibError)];
            newData = nil;
         }
         else if(originalSize != outSize)
            [NSData logCompressMessage:NSLocalizedString(@"(warning) data size was %u, expected %u", @""),
                                       outSize,
                                       originalSize];
      }
      else
         [NSData logCompressMessage:NSDATA_COMPRESS_LOC_MEMERR];
   }
   else
      [NSData logCompressMessage:NSLocalizedString(@"data is not in zlib-compatible format", @"")];

   return newData;
}


/*
 * Quick check of the data to avoid obviously-not-compressed data (see the
 * RFC for the explanation of these checks)
 */
- (BOOL) isCompressedFormat
{
   const unsigned char *bytes = [self bytes];
   /*
    * The checks are:
    *    (*bytes & 0x0F) == 8           : method is deflate (this is called CM,
    *                                       compression method, in the RFC)
    *    (*bytes & 0x80) == 0           : info must be at most seven, this makes
    *                                       sure the MSB is not set, otherwise it
    *                                       is at least 8 (this is called CINFO,
    *                                       compression info, in the RFC)
    *    *((short *) bytes)) % 31 == 0 : the two first bytes as a whole (big
    *                                       endian format) must be a multiple of 31
    *                                       (this is discussed in the FCHECK in
    *                                       FLG, flags, section)
    */
   if((*bytes & 0x0F) == 8 && (*bytes & 0x80) == 0 && NSSwapBigShortToHost(*((short *) bytes)) % 31 == 0)
      return YES;

   return NO;
}

@end
