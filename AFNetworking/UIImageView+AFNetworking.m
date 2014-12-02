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

static void setImageWithURLRequest(UIImageView* self, NSURLRequest* urlRequest, UIImage* placeholderImage, void (^success)(NSURLRequest*, NSHTTPURLResponse*, UIImage*), void (^failure)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error));

/**
 Set the associated object while also returning that same object; useful for weak object references to be auto-released after the call.  Also can be used to reduced LoCs.
 */
static id objc_setAssociatedObject_ret(id object, const void* key, id value, objc_AssociationPolicy policy) {
    objc_setAssociatedObject(object, key, value, policy);
    return value;
}

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
        [self.af_imageRequestQueue setValue:operation forKey:key];
    }
}

+ (NSOperationQueue*) af_sharedImageRequestOperationQueue {
    static NSOperationQueue* _af_imageRequestOperationQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _af_imageRequestOperationQueue = [NSOperationQueue new];
        if ([_af_imageRequestOperationQueue respondsToSelector:@selector(setUnderlyingQueue:)]) {
            _af_imageRequestOperationQueue.underlyingQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        } /* There is no need for an else clause since the default is a GCD provided (background) thread */
        _af_imageRequestOperationQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
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

- (NSOperation*) af_imageRequestOperation {
    return objc_getAssociatedObject(self, _cmd);
}

- (void) af_setImageRequestOperation:(NSOperation*)aOperation {
    objc_setAssociatedObject(self, @selector(af_imageRequestOperation), aOperation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

- (NSMutableArray*) completionBlocks {
    return objc_getAssociatedObject(self, _cmd) ?: objc_setAssociatedObject_ret(self, _cmd, [NSMutableArray new], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void) addCompletionBlock:(void(^)(AFHTTPRequestOperation*, id))completionBlock {
    [self.completionBlocks addObject:completionBlock];
}

- (void) removeCompletionBlocks {
    objc_setAssociatedObject(self, @selector(completionBlocks), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL) isCompleted {
    return [objc_getAssociatedObject(self, @selector(isCompleted)) boolValue];
}

- (void) setCompleted:(BOOL)completed {
    objc_setAssociatedObject(self, @selector(isCompleted), @(completed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

static void(^standardCompletionBlock)(AFHTTPRequestOperation*, id) = ^(AFHTTPRequestOperation* op, id response) {
    @synchronized (op) {
        NSString* key = [op.request.URL absoluteString];
        if ([response isKindOfClass:[UIImage class]]) {
            [[UIImageView af_sharedImageCache] cacheImage:response forKey:key];
        }
        [UIImageView af_setOperation:nil forKey:key];
        for (void(^completionBlock)(AFHTTPRequestOperation*, id) in op.completionBlocks) {
            completionBlock(op, response);
        }
        [op removeCompletionBlocks];
        op.completed = YES;
    }
};

static void(^preloadingCompletionBlock)(AFHTTPRequestOperation*, id) = ^(AFHTTPRequestOperation* op, id response) {};

void setImageWithURLRequest(UIImageView* self, NSURLRequest* urlRequest, UIImage* placeholderImage, void (^success)(NSURLRequest*, NSHTTPURLResponse*, UIImage*), void (^failure)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error)) {
    NSString* key = [urlRequest.URL absoluteString];
    if (!key) return;
    
    void(^uiImageViewCompletionBlock)(AFHTTPRequestOperation*, id) = preloadingCompletionBlock;
    if (self) { /* if there's an actual image view making this request... */
        __weak typeof(self) weakSelf = self;
        uiImageViewCompletionBlock = ^(AFHTTPRequestOperation* op, id response) {
            __strong typeof(self) strongSelf = weakSelf;
            if (op == strongSelf.af_imageRequestOperation || !strongSelf) { /* if the view dealloc'd we will still call to the blocks */
                strongSelf.af_imageRequestOperation = nil;
                dispatch_async(dispatch_get_main_queue(), ^{ /* request was performed on a background thread */
                    __strong typeof(self) strongSelf = weakSelf;
                    if ([response isKindOfClass:[UIImage class]] && success) { /* success block will do something... */
                        success(op.request, op.response, response);
                    } else if ([response isKindOfClass:[UIImage class]]) { /* no success block, assign it ourselves */
                        strongSelf.image = response;
                    } else if (failure) { /* not an image, something went wrong! */
                        failure(op.request, op.response, response);
                    }
                });
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
        [UIImageView af_setOperation:requestOperation forKey:key];
        self.af_imageRequestOperation.queuePriority = NSOperationQueuePriorityNormal;
        self.af_imageRequestOperation = requestOperation;
        #ifdef _AFNETWORKING_ALLOW_INVALID_SSL_CERTIFICATES_
        requestOperation.allowsInvalidSSLCertificate = YES;
        #endif
        if (requestOperation.isCompleted) { /* We missed the boat on getting our request in; simulate it */
            uiImageViewCompletionBlock(requestOperation, [[UIImageView af_sharedImageCache] cachedImageForRequest:requestOperation.request]);
        } else {
            if (self) {
                requestOperation.queuePriority = NSOperationQueuePriorityHigh; /* There is a cell making the request, it's more important */
            } else {
                requestOperation.queuePriority = NSOperationQueuePriorityNormal;
            }
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
