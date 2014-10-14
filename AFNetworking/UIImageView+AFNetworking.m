// UIImageView+AFNetworking.m
//
// Copyright (c) 2011 Gowalla (http://gowalla.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
#import "UIImageView+AFNetworking.h"

#pragma mark -

static char kAFImageRequestOperationObjectKey;

@interface UIImageView (_AFNetworking)
@property (readwrite, nonatomic, strong, setter = af_setImageRequestOperation:) AFImageRequestOperation *af_imageRequestOperation;
@end

@implementation UIImageView (_AFNetworking)
@dynamic af_imageRequestOperation;
@end

#pragma mark -

@implementation UIImageView (AFNetworking)

+ (NSMutableDictionary*) af_imageRequestQueue {
    static NSMutableDictionary* _af_imageRequestQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _af_imageRequestQueue = [NSMutableDictionary dictionary];
    });
    return _af_imageRequestQueue;
}

+ (NSOperation*) af_operationForKey:(NSString*)key {
    @synchronized ([UIImageView class]) {
        return self.af_imageRequestQueue[key];
    }
}

+ (void) af_setOperation:(NSOperation*)operation forKey:(NSString*)key {
    @synchronized ([UIImageView class]) {
        if (operation) {
            self.af_imageRequestQueue[key] = operation;
        } else {
            [self.af_imageRequestQueue removeObjectForKey:key];
        }
    }
}

+ (NSOperationQueue*) af_sharedImageRequestOperationQueue {
    static NSOperationQueue* _af_imageRequestOperationQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _af_imageRequestOperationQueue = [NSOperationQueue new];
        [_af_imageRequestOperationQueue setMaxConcurrentOperationCount:NSOperationQueueDefaultMaxConcurrentOperationCount];
    });
    return _af_imageRequestOperationQueue;
}

+ (AFImageCache*) af_sharedImageCache {
    static AFImageCache* _af_imageCache;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _af_imageCache = [AFImageCache new];
    });
    return _af_imageCache;
}

- (void) setImageWithURL:(NSURL*)url {
    [self setImageWithURL:url placeholderImage:nil];
}

- (void) setImageWithURL:(NSURL*)url placeholderImage:(UIImage*)placeholderImage {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request addValue:@"image/*" forHTTPHeaderField:@"Accept"];
    [self setImageWithURLRequest:request placeholderImage:placeholderImage success:nil failure:nil];
}

- (void) setImageWithURLRequest:(NSURLRequest*)urlRequest
              placeholderImage:(UIImage*)placeholderImage
                       success:(void (^)(NSURLRequest* request, NSHTTPURLResponse* response, UIImage* image))success
                       failure:(void (^)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error))failure {

    UIImage* cachedImage = [[[self class] af_sharedImageCache] cachedImageForRequest:urlRequest];
    NSString* key = [urlRequest.URL absoluteString];
    
    if (cachedImage) {
        if (success) {
            success(nil, nil, cachedImage);
        } else {
            self.image = cachedImage;
        }
    } else {
        if (placeholderImage) {
            self.image = placeholderImage;
        }

        AFImageRequestOperation* oldOperation = [[self class] af_operationForKey:key];
        void(^oldCompletionBlock)() = oldOperation.completionBlock;
        AFImageRequestOperation* requestOperation = oldOperation ?: [[AFImageRequestOperation alloc] initWithRequest:urlRequest];
		
#ifdef _AFNETWORKING_ALLOW_INVALID_SSL_CERTIFICATES_
		requestOperation.allowsInvalidSSLCertificate = YES;
#endif
		
        [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation* operation, id responseObject) {
            if (oldCompletionBlock) {
                oldCompletionBlock();
            }
            
            NSOperation* op = [[self class] af_operationForKey:key];
            
            if (success) {
                success(operation.request, operation.response, responseObject);
            } else if (responseObject) {
                self.image = responseObject;
            }

            [[[self class] af_sharedImageCache] cacheImage:responseObject forRequest:operation.request];
            [[self class] af_setOperation:nil forKey:key];
            
        } failure:^(AFHTTPRequestOperation* operation, NSError* error) {
            if (oldCompletionBlock) {
                oldCompletionBlock();
            }
            
            NSOperation* op = [[self class] af_operationForKey:key];
            
            if (failure) {
                failure(operation.request, operation.response, error);
            }
            
            [[self class] af_setOperation:nil forKey:key];
        }];

        [[self class] af_setOperation:requestOperation forKey:key];
        [[[self class] af_sharedImageRequestOperationQueue] addOperation:requestOperation];
    }
}

- (void)cancelImageRequestOperationForKey:(NSString*)key {
    [[[self class] af_operationForKey:key] cancel];
}

@end

@implementation AFImageCache

- (UIImage*) cachedImageForRequest:(NSURLRequest*)request {
    switch ([request cachePolicy]) {
        case NSURLRequestReloadIgnoringCacheData:
        case NSURLRequestReloadIgnoringLocalAndRemoteCacheData:
            return nil;
        default:
            return [self objectForKey:[request.URL absoluteString]];
    }
}

- (void) cacheImage:(UIImage*)image forKey:(NSString*)key {
    if (image) {
        [self setObject:image forKey:key];
    } else {
        [self removeObjectForKey:key];
    }
}

@end
    
void enqueueImageDownloadRequest(NSURL* url) {
    [[UIImageView new] setImageWithURL:url];
}

#endif
