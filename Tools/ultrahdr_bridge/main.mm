#import <CoreImage/CoreImage.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

#include "ultrahdr_api.h"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <string>
#include <vector>

static constexpr NSInteger kProtocolVersion = 1;

static void writeJSON(NSDictionary *object, int exitCode) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (data == nil) {
        fprintf(stderr, "{\"success\":false,\"messages\":[\"Unable to encode bridge response.\"]}\n");
        exit(exitCode == 0 ? 1 : exitCode);
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    exit(exitCode);
}

static void fail(NSString *message, int exitCode = 1) {
    writeJSON(@{
        @"protocolVersion": @(kProtocolVersion),
        @"success": @NO,
        @"messages": @[message ?: @"Unknown bridge error."]
    }, exitCode);
}

static bool check(uhdr_error_info_t status, NSString **message) {
    if (status.error_code == UHDR_CODEC_OK) return true;
    if (status.has_detail) {
        *message = [NSString stringWithUTF8String:status.detail];
    } else {
        *message = [NSString stringWithFormat:@"libultrahdr error %d", status.error_code];
    }
    return false;
}

static NSData *readFile(NSString *path) {
    return [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
}

static bool containsASCII(NSData *data, const char *needle) {
    if (data == nil || needle == nullptr) return false;
    std::string bytes(static_cast<const char *>(data.bytes), data.length);
    return bytes.find(needle) != std::string::npos;
}

static NSInteger auxiliaryChannelCount(CFDictionaryRef auxiliary) {
    if (auxiliary == nullptr) return 0;
    NSDictionary *dictionary = (__bridge NSDictionary *)auxiliary;
    NSDictionary *description = dictionary[(__bridge NSString *)kCGImageAuxiliaryDataInfoDataDescription];
    NSNumber *pixelFormat = description[@"PixelFormat"];
    NSString *metadata = [dictionary[(__bridge NSString *)kCGImageAuxiliaryDataInfoMetadata] description];

    if ([metadata containsString:@"HDRToneMap:[1]"] || [metadata containsString:@"HDRToneMap:[2]"]) {
        return 3;
    }
    // 'L008' / kCVPixelFormatType_OneComponent8, used by monochrome Apple and ISO gain maps.
    if (pixelFormat != nil && pixelFormat.unsignedIntValue == 0x4C303038) {
        return 1;
    }
    return pixelFormat == nil ? 0 : 3;
}

static CIImage *loadImage(NSString *path, bool expandHDR) {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSDictionary *options = @{
        kCIImageApplyOrientationProperty: @YES,
        kCIImageExpandToHDR: @(expandHDR)
    };
    return [CIImage imageWithContentsOfURL:url options:options];
}

static CIImage *normalizedImage(CIImage *image, NSInteger maxWidth) {
    CGRect extent = CGRectIntegral(image.extent);
    CIImage *normalized = [image imageByApplyingTransform:
        CGAffineTransformMakeTranslation(-CGRectGetMinX(extent), -CGRectGetMinY(extent))];
    if (maxWidth > 0 && CGRectGetWidth(extent) > maxWidth) {
        CGFloat scale = static_cast<CGFloat>(maxWidth) / CGRectGetWidth(extent);
        normalized = [normalized imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    }
    return normalized;
}

struct RawImageBuffer {
    std::vector<uint8_t> bytes;
    uhdr_raw_image_t image{};
};

static RawImageBuffer renderImage(CIImage *source, bool hdr, NSString *gamutName, NSInteger maxWidth) {
    CIImage *image = normalizedImage(source, maxWidth);
    CGRect extent = CGRectIntegral(image.extent);
    size_t width = static_cast<size_t>(CGRectGetWidth(extent));
    size_t height = static_cast<size_t>(CGRectGetHeight(extent));
    size_t bytesPerPixel = hdr ? 8 : 4;
    size_t rowBytes = width * bytesPerPixel;

    RawImageBuffer result;
    result.bytes.resize(rowBytes * height);

    CGColorSpaceRef colorSpace = nullptr;
    uhdr_color_gamut_t gamut = UHDR_CG_DISPLAY_P3;
    if ([gamutName caseInsensitiveCompare:@"sRGB"] == NSOrderedSame) {
        colorSpace = CGColorSpaceCreateWithName(hdr ? kCGColorSpaceExtendedLinearSRGB : kCGColorSpaceSRGB);
        gamut = UHDR_CG_BT_709;
    } else if ([gamutName caseInsensitiveCompare:@"Rec2020"] == NSOrderedSame) {
        colorSpace = CGColorSpaceCreateWithName(hdr ? kCGColorSpaceExtendedLinearITUR_2020 : kCGColorSpaceITUR_2020);
        gamut = UHDR_CG_BT_2100;
    } else {
        colorSpace = CGColorSpaceCreateWithName(hdr ? kCGColorSpaceExtendedLinearDisplayP3 : kCGColorSpaceDisplayP3);
    }

    CIContext *context = [CIContext contextWithOptions:@{
        kCIContextWorkingColorSpace: (__bridge id)colorSpace,
        kCIContextOutputColorSpace: (__bridge id)colorSpace
    }];
    [context render:image
           toBitmap:result.bytes.data()
           rowBytes:rowBytes
             bounds:extent
             format:hdr ? kCIFormatRGBAh : kCIFormatRGBA8
         colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);

    result.image.fmt = hdr ? UHDR_IMG_FMT_64bppRGBAHalfFloat : UHDR_IMG_FMT_32bppRGBA8888;
    result.image.cg = gamut;
    result.image.ct = hdr ? UHDR_CT_LINEAR : UHDR_CT_SRGB;
    result.image.range = UHDR_CR_FULL_RANGE;
    result.image.w = static_cast<unsigned int>(width);
    result.image.h = static_cast<unsigned int>(height);
    result.image.planes[UHDR_PLANE_PACKED] = result.bytes.data();
    result.image.stride[UHDR_PLANE_PACKED] = static_cast<unsigned int>(width);
    return result;
}

static NSDictionary *inspectFile(NSString *path) {
    NSData *data = readFile(path);
    if (data == nil) fail([NSString stringWithFormat:@"Unable to read %@.", path]);

    CIImage *image = loadImage(path, false);
    CIImage *expandedImage = loadImage(path, true);
    NSInteger width = image == nil ? 0 : lround(CGRectGetWidth(CGRectIntegral(image.extent)));
    NSInteger height = image == nil ? 0 : lround(CGRectGetHeight(CGRectIntegral(image.extent)));
    BOOL ultraHDR = is_uhdr_image(const_cast<void *>(data.bytes), static_cast<int>(data.length)) != 0;
    BOOL xmp = containsASCII(data, "hdrgm:Version") || containsASCII(data, "hdrgm:version");
    BOOL iso = containsASCII(data, "21496") || containsASCII(data, "iso:std:iso:ts:21496");
    BOOL gcontainer = containsASCII(data, "Container:Directory") ||
                      containsASCII(data, "http://ns.google.com/photos/1.0/container/");
    BOOL mpf = containsASCII(data, "MPF");
    BOOL appleLegacyMarker = containsASCII(data, "urn:com:apple:photo:2020:aux:hdrgainmap");
    BOOL apple = NO;
    BOOL appleAuxiliary = NO;
    BOOL isoAuxiliaryPresent = NO;
    BOOL ultraHDRDecoderVerified = NO;
    NSInteger gainMapWidth = 0;
    NSInteger gainMapHeight = 0;
    NSInteger gainMapChannels = 0;
    BOOL multiChannel = NO;

    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], nullptr);
    if (source != nullptr) {
        CFDictionaryRef auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeHDRGainMap);
        CFDictionaryRef isoAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            source, 0, kCGImageAuxiliaryDataTypeISOGainMap);
        appleAuxiliary = auxiliary != nullptr;
        isoAuxiliaryPresent = isoAuxiliary != nullptr;
        apple = appleAuxiliary;
        iso = iso || isoAuxiliary != nullptr;
        gainMapChannels = std::max(auxiliaryChannelCount(auxiliary), auxiliaryChannelCount(isoAuxiliary));
        if (auxiliary != nullptr) CFRelease(auxiliary);
        if (isoAuxiliary != nullptr) CFRelease(isoAuxiliary);
        CFRelease(source);
    }
    CIImage *auxiliaryGainMap = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                       options:@{kCIImageAuxiliaryHDRGainMap: @YES}];
    if (auxiliaryGainMap != nil && !CGRectIsEmpty(auxiliaryGainMap.extent)) {
        apple = apple || !iso;
        gainMapWidth = lround(CGRectGetWidth(CGRectIntegral(auxiliaryGainMap.extent)));
        gainMapHeight = lround(CGRectGetHeight(CGRectIntegral(auxiliaryGainMap.extent)));
    }

    if (ultraHDR) {
        uhdr_compressed_image_t compressed{};
        compressed.data = const_cast<void *>(data.bytes);
        compressed.data_sz = data.length;
        compressed.capacity = data.length;
        compressed.cg = UHDR_CG_UNSPECIFIED;
        compressed.ct = UHDR_CT_UNSPECIFIED;
        compressed.range = UHDR_CR_UNSPECIFIED;

        uhdr_codec_private_t *decoder = uhdr_create_decoder();
        NSString *error = nil;
        if (decoder != nullptr &&
            check(uhdr_dec_set_image(decoder, &compressed), &error) &&
            check(uhdr_dec_probe(decoder), &error)) {
            width = uhdr_dec_get_image_width(decoder);
            height = uhdr_dec_get_image_height(decoder);
            gainMapWidth = uhdr_dec_get_gainmap_width(decoder);
            gainMapHeight = uhdr_dec_get_gainmap_height(decoder);
            if (uhdr_gainmap_metadata_t *metadata = uhdr_dec_get_gainmap_metadata(decoder)) {
                multiChannel =
                    std::fabs(metadata->max_content_boost[0] - metadata->max_content_boost[1]) > 0.0001f ||
                    std::fabs(metadata->max_content_boost[1] - metadata->max_content_boost[2]) > 0.0001f;
            }
            NSString *decodeError = nil;
            if (check(uhdr_decode(decoder), &decodeError)) {
                ultraHDRDecoderVerified = YES;
                if (uhdr_raw_image_t *decodedGainMap = uhdr_get_decoded_gainmap_image(decoder)) {
                    multiChannel = decodedGainMap->fmt != UHDR_IMG_FMT_8bppYCbCr400;
                    gainMapChannels = multiChannel ? 3 : 1;
                }
            }
        }
        if (decoder != nullptr) uhdr_release_decoder(decoder);
    }

    BOOL hasGainMap = ultraHDR || apple || xmp || iso;
    BOOL isHDRSignal = hasGainMap || expandedImage.contentHeadroom > 1.0001f;
    return @{
        @"protocolVersion": @(kProtocolVersion),
        @"success": @YES,
        @"operation": @"inspect",
        @"engineVersion": @UHDR_LIB_VERSION_STR,
        @"input": path,
        @"width": @(width),
        @"height": @(height),
        @"hasGainMap": @(hasGainMap),
        @"isHDRSignal": @(isHDRSignal),
        @"contentHeadroom": @(expandedImage.contentHeadroom),
        @"gainMapKind": ultraHDR ? @"ultraHDR" : (apple ? @"apple" : (iso ? @"iso21496" : (xmp ? @"xmp" : @"none"))),
        @"gainMapWidth": @(gainMapWidth),
        @"gainMapHeight": @(gainMapHeight),
        @"multiChannel": @(multiChannel),
        @"gainMapChannels": @(gainMapChannels),
        @"hasXMP": @(xmp),
        @"hasISO21496": @(iso),
        @"hasAppleAuxiliary": @(appleAuxiliary),
        @"hasISOAuxiliary": @(isoAuxiliaryPresent),
        @"hasAppleLegacyMarker": @(appleLegacyMarker),
        @"hasGContainer": @(gcontainer),
        @"hasMPF": @(mpf),
        @"ultraHDRDecoderVerified": @(ultraHDRDecoderVerified),
        @"hasSDRFallback": @(hasGainMap),
        @"messages": @[]
    };
}

static NSDictionary *encodeRequest(NSDictionary *request) {
    NSString *hdrPath = request[@"hdrInput"] ?: request[@"input"];
    NSString *sdrPath = request[@"sdrInput"];
    NSString *outputPath = request[@"output"];
    if (hdrPath.length == 0 || outputPath.length == 0) {
        fail(@"Encoding requires hdrInput/input and output.");
    }

    NSInteger maxWidth = [request[@"maxWidth"] integerValue];
    NSString *gamut = request[@"colorGamut"] ?: @"DisplayP3";
    CIImage *hdrSource = loadImage(hdrPath, true);
    if (hdrSource == nil) fail(@"Unable to decode the HDR source.");
    RawImageBuffer hdr = renderImage(hdrSource, true, gamut, maxWidth);

    RawImageBuffer sdr;
    bool hasSDR = sdrPath.length > 0;
    if (hasSDR) {
        CIImage *sdrSource = loadImage(sdrPath, false);
        if (sdrSource == nil) fail(@"Unable to decode the SDR source.");
        sdr = renderImage(sdrSource, false, gamut, maxWidth);
        if (sdr.image.w != hdr.image.w || sdr.image.h != hdr.image.h) {
            fail(@"HDR and SDR renditions must have exactly matching dimensions after orientation.");
        }
    }

    uhdr_codec_private_t *encoder = uhdr_create_encoder();
    if (encoder == nullptr) fail(@"Unable to create libultrahdr encoder.");

    NSString *error = nil;
    auto require = [&](uhdr_error_info_t status) {
        if (!check(status, &error)) {
            uhdr_release_encoder(encoder);
            fail(error);
        }
    };

    require(uhdr_enc_set_raw_image(encoder, &hdr.image, UHDR_HDR_IMG));
    if (hasSDR) require(uhdr_enc_set_raw_image(encoder, &sdr.image, UHDR_SDR_IMG));

    NSInteger baseQuality = request[@"baseQuality"] ? [request[@"baseQuality"] integerValue] : 95;
    NSInteger gainMapQuality = request[@"gainMapQuality"] ? [request[@"gainMapQuality"] integerValue] : 95;
    NSInteger gainMapScale = request[@"gainMapScale"] ? [request[@"gainMapScale"] integerValue] : 1;
    BOOL multiChannel = request[@"multiChannel"] ? [request[@"multiChannel"] boolValue] : YES;
    BOOL realtime = [request[@"preset"] isEqual:@"realtime"];

    require(uhdr_enc_set_quality(encoder, static_cast<int>(baseQuality), UHDR_BASE_IMG));
    require(uhdr_enc_set_quality(encoder, static_cast<int>(gainMapQuality), UHDR_GAIN_MAP_IMG));
    require(uhdr_enc_set_gainmap_scale_factor(encoder, static_cast<int>(std::max<NSInteger>(1, gainMapScale))));
    require(uhdr_enc_set_using_multi_channel_gainmap(encoder, multiChannel ? 1 : 0));
    require(uhdr_enc_set_preset(encoder, realtime ? UHDR_USAGE_REALTIME : UHDR_USAGE_BEST_QUALITY));
    require(uhdr_enc_set_output_format(encoder, UHDR_CODEC_JPG));
    require(uhdr_encode(encoder));

    uhdr_compressed_image_t *encoded = uhdr_get_encoded_stream(encoder);
    if (encoded == nullptr || encoded->data == nullptr || encoded->data_sz == 0) {
        uhdr_release_encoder(encoder);
        fail(@"libultrahdr returned an empty encoded stream.");
    }

    NSData *outputData = [NSData dataWithBytes:encoded->data length:encoded->data_sz];
    NSError *writeError = nil;
    BOOL wrote = [outputData writeToFile:outputPath options:NSDataWritingAtomic error:&writeError];
    uhdr_release_encoder(encoder);
    if (!wrote) fail(writeError.localizedDescription ?: @"Unable to write Ultra HDR output.");

    NSMutableDictionary *result = [inspectFile(outputPath) mutableCopy];
    result[@"operation"] = request[@"operation"] ?: @"encodePair";
    result[@"output"] = outputPath;
    result[@"baseQuality"] = @(baseQuality);
    result[@"gainMapQuality"] = @(gainMapQuality);
    result[@"messages"] = @[
        hasSDR ? @"Used the photographer-provided SDR rendition." : @"Generated the SDR fallback from the HDR source.",
        multiChannel ? @"Encoded a multi-channel gain map." : @"Encoded a monochrome gain map."
    ];
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--version") == 0) {
            printf("ultrahdr_bridge 1 / libultrahdr %s\n", UHDR_LIB_VERSION_STR);
            return 0;
        }
        if (argc != 3 || strcmp(argv[1], "--request") != 0) {
            fail(@"Usage: ultrahdr_bridge --request /path/request.json");
        }

        NSData *requestData = readFile([NSString stringWithUTF8String:argv[2]]);
        if (requestData == nil) fail(@"Unable to read request JSON.");
        NSError *jsonError = nil;
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:requestData options:0 error:&jsonError];
        if (![request isKindOfClass:NSDictionary.class]) {
            fail(jsonError.localizedDescription ?: @"Invalid request JSON.");
        }
        if ([request[@"protocolVersion"] integerValue] != kProtocolVersion) {
            fail(@"Unsupported bridge protocol version.");
        }

        NSString *operation = request[@"operation"] ?: request[@"mode"];
        NSDictionary *response = nil;
        if ([operation isEqual:@"inspect"] || [operation isEqual:@"verify"]) {
            NSString *input = request[@"input"];
            if (input.length == 0) fail(@"Inspect/verify requires input.");
            response = inspectFile(input);
        } else if ([operation isEqual:@"encodeHDR"] ||
                   [operation isEqual:@"encodePair"] ||
                   [operation isEqual:@"normalizeExisting"] ||
                   [operation isEqual:@"encode"]) {
            response = encodeRequest(request);
        } else {
            fail([NSString stringWithFormat:@"Unsupported operation: %@", operation ?: @"(missing)"]);
        }
        writeJSON(response, 0);
    }
}
