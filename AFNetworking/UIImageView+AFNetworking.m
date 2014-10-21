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

static char kAFImageRequestOperationObjectKey;

static void setImageWithURLRequest(UIImageView* self, NSURLRequest* urlRequest, UIImage* placeholderImage, void (^success)(NSURLRequest*, NSHTTPURLResponse*, UIImage*), void (^failure)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error));

@interface UIImageView (_AFNetworking)

@property (nonatomic, strong, setter=af_setImageRequestOperation:) NSOperation* af_imageRequestOperation;

@end

@implementation UIImageView (AFNetworking)

+ (NSMutableDictionary*) af_imageRequestQueue {
    static NSMutableDictionary* _af_imageRequestQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _af_imageRequestQueue = [NSMutableDictionary dictionary];
    });
    return _af_imageRequestQueue;
}

+ (AFHTTPRequestOperation*) af_operationForKey:(NSString*)key {
    @synchronized ([UIImageView class]) {
        return self.af_imageRequestQueue[key];
    }
}

+ (void) af_setOperation:(AFHTTPRequestOperation*)operation forKey:(NSString*)key {
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

static const char* const kImageRequestKey;
- (NSOperation*) af_imageRequestOperation {
    return objc_getAssociatedObject(self, &kImageRequestKey);
}

- (void) af_setImageRequestOperation:(NSOperation*)aOperation {
    objc_setAssociatedObject(self, &kImageRequestKey, aOperation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    setImageWithURLRequest(self, urlRequest, placeholderImage, success, failure);
}

- (void) cancelImageRequestOperationForKey:(NSString*)key {
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
    }
}

@end

@interface NSOperation (MultipleBlocks)

- (NSMutableArray*) completionBlocks;

- (void) addCompletionBlock:(void(^)(AFHTTPRequestOperation*, id))completionBlock;

- (void) removeCompletionBlocks;

@property (nonatomic, assign, getter=isCompleted) BOOL completed;

@end

@implementation NSOperation (MultipleBlocks)

static const char* const kExecutionBlocksKey;
static const char* const kCompletionFlagKey;
- (NSMutableArray*) completionBlocks {
    NSMutableArray* _completionBlocks = objc_getAssociatedObject(self, &kExecutionBlocksKey);
    if (!_completionBlocks) {
        _completionBlocks = [NSMutableArray new];
        objc_setAssociatedObject(self, &kExecutionBlocksKey, _completionBlocks, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return _completionBlocks;
}

- (void) addCompletionBlock:(void(^)(AFHTTPRequestOperation*, id))completionBlock {
    [self.completionBlocks addObject:completionBlock];
}

- (void) removeCompletionBlocks {
    objc_setAssociatedObject(self, &kExecutionBlocksKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL) isCompleted {
    return [objc_getAssociatedObject(self, &kCompletionFlagKey) boolValue];
}

- (void) setCompleted:(BOOL)completed {
    objc_setAssociatedObject(self, &kCompletionFlagKey, @(completed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

static void(^standardCompletionBlock)(AFHTTPRequestOperation*, id) = ^(AFHTTPRequestOperation* op, id response) {
    [UIImageView af_setOperation:nil forKey:[op.request.URL absoluteString]];
    @synchronized (op) {
        for (void(^completionBlock)(AFHTTPRequestOperation*, id) in op.completionBlocks) {
            completionBlock(op, response);
        }
        [op removeCompletionBlocks];
        op.completed = YES;
    }
};

static void(^preloadingCompletionBlock)(AFHTTPRequestOperation*, id) = ^(AFHTTPRequestOperation* op, id response) {
    if ([response isKindOfClass:[UIImage class]]) {
        [[UIImageView af_sharedImageCache] cacheImage:response forKey:[op.request.URL absoluteString]];
    }
};

void setImageWithURLRequest(UIImageView* self, NSURLRequest* urlRequest, UIImage* placeholderImage, void (^success)(NSURLRequest*, NSHTTPURLResponse*, UIImage*), void (^failure)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error)) {
    NSString* key = [urlRequest.URL absoluteString];
    if (!key) return;
    
    /**
     The default is block behaves like a pre-loading request unless there is a specific UIImageView making the request.
     */
    void(^uiImageViewCompletionBlock)(AFHTTPRequestOperation*, id) = preloadingCompletionBlock;
    if (self) {
        uiImageViewCompletionBlock = ^(AFHTTPRequestOperation* op, id response) {
            if (op == self.af_imageRequestOperation) {
                if ([response isKindOfClass:[UIImage class]]) {
                    [[UIImageView af_sharedImageCache] cacheImage:response forKey:key];
                    if (success) {
                        success(op.request, op.response, response);
                    } else {
                        self.image = response;
                    }
                } else if (failure) {
                    failure(op.request, op.response, response);
                }
            }
        };
    }
    
    AFImageRequestOperation* oldRequestOperation = [UIImageView af_operationForKey:key];
    AFImageRequestOperation* requestOperation;
    @synchronized (oldRequestOperation) {
        UIImage* cachedImage = [[UIImageView af_sharedImageCache] cachedImageForRequest:urlRequest];
        if (cachedImage) {
            if (success) {
                success(nil, nil, cachedImage);
            } else {
                self.image = cachedImage;
            }
            return;
        }
        if (placeholderImage) {
            self.image = placeholderImage;
        }
        
        requestOperation = oldRequestOperation ?: [[AFImageRequestOperation alloc] initWithRequest:urlRequest];
        self.af_imageRequestOperation = requestOperation;
        #ifdef _AFNETWORKING_ALLOW_INVALID_SSL_CERTIFICATES_
        requestOperation.allowsInvalidSSLCertificate = YES;
        #endif
        if (requestOperation.isCompleted) { /* We missed the boat on getting our request in; simulate it */
            uiImageViewCompletionBlock(requestOperation, [[UIImageView af_sharedImageCache] cachedImageForRequest:requestOperation.request]);
        } else {
            if (self) requestOperation.queuePriority = NSOperationQueuePriorityVeryHigh; /* There is a cell making the request, it's more important */
            [requestOperation addCompletionBlock:uiImageViewCompletionBlock];
        }
    }
    if (!oldRequestOperation) { /* operations can only be started once, and we need the standard completion block to kick in */
        [requestOperation setCompletionBlockWithSuccess:standardCompletionBlock failure:standardCompletionBlock];
        [[UIImageView af_sharedImageRequestOperationQueue] addOperation:requestOperation];
    }
}

void enqueueImageDownloadRequest(NSURL* url) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request addValue:@"image/*" forHTTPHeaderField:@"Accept"];
    setImageWithURLRequest(nil, request, nil, nil, nil);
}

#endif
