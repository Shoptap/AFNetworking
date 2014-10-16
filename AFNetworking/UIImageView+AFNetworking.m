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

void setImageWithURLRequest(UIImageView* self, NSURLRequest* urlRequest, UIImage* placeholderImage, void (^success)(NSURLRequest*, NSHTTPURLResponse*, UIImage*), void (^failure)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error));

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

- (AFImageRequestOperation*) af_imageRequestOperation {
    return objc_getAssociatedObject(self, _cmd);
}

- (void) af_setImageRequestOperation:(AFImageRequestOperation*)af_imageRequestOperation {
    objc_setAssociatedObject(self, @selector(af_imageRequestOperation), af_imageRequestOperation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

void setImageWithURLRequest(UIImageView* self, NSURLRequest* urlRequest, UIImage* placeholderImage, void (^success)(NSURLRequest*, NSHTTPURLResponse*, UIImage*), void (^failure)(NSURLRequest* request, NSHTTPURLResponse* response, NSError* error)) {
    Class cls = [UIImageView class];
    UIImage* cachedImage = [[cls af_sharedImageCache] cachedImageForRequest:urlRequest];
    NSString* key = [urlRequest.URL absoluteString];
    if (!key) return;
    
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
    
    AFImageRequestOperation* oldRequestOperation = [cls af_operationForKey:key];
    AFImageRequestOperation* requestOperation = oldRequestOperation ?: [[AFImageRequestOperation alloc] initWithRequest:urlRequest];
    self.af_imageRequestOperation = requestOperation;
    
#ifdef _AFNETWORKING_ALLOW_INVALID_SSL_CERTIFICATES_
    requestOperation.allowsInvalidSSLCertificate = YES;
#endif
    @synchronized (requestOperation) {
        if (self) {
            requestOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
            [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation* operation, id responseObject) {
                @synchronized (requestOperation) {
                    AFHTTPRequestOperation* op = [cls af_operationForKey:key];
                    if ([[op.request.URL absoluteString] isEqual:[self.af_imageRequestOperation.request.URL absoluteString]]) {
                        if (success) {
                            success(operation.request, operation.response, responseObject);
                        } else if (responseObject) {
                            self.image = responseObject;
                        }
                    } else {
                        UIImage* cachedImage = [[cls af_sharedImageCache] cachedImageForRequest:self.af_imageRequestOperation.request];
                        if (success) {
                            success(operation.request, operation.response, cachedImage);
                        } else if (responseObject) {
                            self.image = cachedImage;
                        }
                    }
                    self.af_imageRequestOperation = nil;
                    [[cls af_sharedImageCache] cacheImage:responseObject forKey:operation.request];
                    [cls af_setOperation:nil forKey:key];
                }
            } failure:^(AFHTTPRequestOperation* operation, NSError* error) {
                @synchronized (requestOperation) {
                    AFHTTPRequestOperation* op = [cls af_operationForKey:key];
                    if ([[op.request.URL absoluteString] isEqual:[self.af_imageRequestOperation.request.URL absoluteString]]) {
                        if (failure) {
                            failure(operation.request, operation.response, error);
                        }
                    }
                    self.af_imageRequestOperation = nil;
                    [cls af_setOperation:nil forKey:key];
                }
            }];
        } else if (!requestOperation.completionBlock) { /* this is _only_ a pre-loading request, its priority is lowest */
            requestOperation.queuePriority = NSOperationQueuePriorityNormal;
            [requestOperation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation* operation, id responseObject) {
                @synchronized (requestOperation) {
                    [[cls af_sharedImageCache] cacheImage:responseObject forKey:[operation.request.URL absoluteString]];
                    [cls af_setOperation:nil forKey:[operation.request.URL absoluteString]];
                }
            } failure:nil];
        } else { /* some cell already requested this, but we've got a pre-loading request */
            requestOperation.queuePriority = NSOperationQueuePriorityHigh;
        }
        
        if (requestOperation.completionBlock && !requestOperation.isExecuting && requestOperation.isFinished) {
            requestOperation.completionBlock();
        } /* if we missed setting the new block before the operation finished, we want the latest requestor to get the image */
        
        [cls af_setOperation:requestOperation forKey:key];
        
        if (!oldRequestOperation) {
            [[cls af_sharedImageRequestOperationQueue] addOperation:requestOperation];
        }
    }
}

void enqueueImageDownloadRequest(NSURL* url) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
    [request addValue:@"image/*" forHTTPHeaderField:@"Accept"];
    setImageWithURLRequest(nil, request, nil, nil, nil);
}

#endif
