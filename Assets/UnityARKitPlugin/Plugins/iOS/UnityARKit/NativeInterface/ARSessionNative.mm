// Unity Technologies Inc (c) 2017
// ARSessionNative.mm
// Main implementation of ARKit plugin native parts

#import <CoreVideo/CoreVideo.h>
#include "stdlib.h"
#include "UnityAppController.h"
#include "ARKitDefines.h"

// These don't all need to be static data, but no other better place for them at the moment.
static id <MTLTexture> s_CapturedImageTextureY;
static id <MTLTexture> s_CapturedImageTextureCbCr;
static UnityARMatrix4x4 s_CameraProjectionMatrix;

static float s_AmbientIntensity;
static int s_TrackingQuality;
static float s_ShaderScale;
static const vector_float3* s_PointCloud;
static NSUInteger s_PointCloudSize;

static float unityCameraNearZ;
static float unityCameraFarZ;




static inline UnityARTrackingState GetUnityARTrackingStateFromARTrackingState(ARTrackingState trackingState)
{
    switch (trackingState) {
        case ARTrackingStateNormal:
            return UnityARTrackingStateNormal;
        case ARTrackingStateLimited:
            return UnityARTrackingStateLimited;
        case ARTrackingStateNotAvailable:
            return UnityARTrackingStateNotAvailable;
        default:
            [NSException raise:@"UnrecognizedARTrackingState" format:@"Unrecognized ARTrackingState: %ld", (long)trackingState];
            break;
    }
}

static inline UnityARTrackingReason GetUnityARTrackingReasonFromARTrackingReason(ARTrackingStateReason trackingReason)
{
    switch (trackingReason)
    {
        case ARTrackingStateReasonNone:
            return UnityARTrackingStateReasonNone;
        case ARTrackingStateReasonInitializing:
            return UnityARTrackingStateReasonInitializing;
        case ARTrackingStateReasonExcessiveMotion:
            return UnityARTrackingStateReasonExcessiveMotion;
        case ARTrackingStateReasonInsufficientFeatures:
            return UnityARTrackingStateReasonInsufficientFeatures;
        case ARTrackingStateReasonRelocalizing:
            return UnityARTrackingStateReasonRelocalizing;
        default:
            [NSException raise:@"UnrecognizedARTrackingStateReason" format:@"Unrecognized ARTrackingStateReason: %ld", (long)trackingReason];
            break;
    }
}

static inline UnityARWorldMappingStatus GetUnityARWorldMappingStatusFromARWorldMappingStatus(ARWorldMappingStatus worldMappingStatus)
{
    switch (worldMappingStatus) {
        case ARWorldMappingStatusNotAvailable:
            return UnityARWorldMappingStatusNotAvailable;
        case ARWorldMappingStatusLimited:
            return UnityARWorldMappingStatusLimited;
        case ARWorldMappingStatusExtending:
            return UnityARWorldMappingStatusExtending;
        case ARWorldMappingStatusMapped:
            return UnityARWorldMappingStatusMapped;
        default:
            [NSException raise:@"UnrecognizedARWorldMappingStatus" format:@"Unrecognized ARWorldMappingStatus: %ld", (long)worldMappingStatus];
            break;
    }
}


static inline AREnvironmentTexturing GetAREnvironmentTexturingFromUnityAREnvironmentTexturing(UnityAREnvironmentTexturing& unityEnvTexturing)
{
    switch (unityEnvTexturing)
    {
        case UnityAREnvironmentTexturingNone:
            return AREnvironmentTexturingNone;
        case UnityAREnvironmentTexturingManual:
            return AREnvironmentTexturingManual;
        case UnityAREnvironmentTexturingAutomatic:
            return AREnvironmentTexturingAutomatic;
    }
}



inline void GetARSessionConfigurationFromARKitWorldTrackingSessionConfiguration(ARKitWorldTrackingSessionConfiguration& unityConfig, ARWorldTrackingConfiguration* appleConfig)
{
    appleConfig.planeDetection = GetARPlaneDetectionFromUnityARPlaneDetection(unityConfig.planeDetection);
    appleConfig.worldAlignment = GetARWorldAlignmentFromUnityARAlignment(unityConfig.alignment);
    appleConfig.lightEstimationEnabled = (BOOL)unityConfig.enableLightEstimation;
    
    if ([appleConfig respondsToSelector:@selector(maximumNumberOfTrackedImages)])
        appleConfig.maximumNumberOfTrackedImages = unityConfig.maximumNumberOfTrackedImages;
    
    if (UnityIsARKit_1_5_Supported())
    {
        appleConfig.autoFocusEnabled = (BOOL) unityConfig.enableAutoFocus;
        if (unityConfig.ptrVideoFormat != NULL)
        {
            appleConfig.videoFormat = (__bridge ARVideoFormat*) unityConfig.ptrVideoFormat;
        }
    }
    
    if (UnityIsARKit_2_0_Supported())
    {
        appleConfig.initialWorldMap = (__bridge ARWorldMap*)unityConfig.ptrWorldMap;
        appleConfig.environmentTexturing = GetAREnvironmentTexturingFromUnityAREnvironmentTexturing(unityConfig.environmentTexturing);
      
    }
}

inline void GetARSessionConfigurationFromARKitSessionConfiguration(ARKitSessionConfiguration& unityConfig, ARConfiguration* appleConfig)
{
    appleConfig.worldAlignment = GetARWorldAlignmentFromUnityARAlignment(unityConfig.alignment);
    appleConfig.lightEstimationEnabled = (BOOL)unityConfig.enableLightEstimation;
}

inline void GetARFaceConfigurationFromARKitFaceConfiguration(ARKitFaceTrackingConfiguration& unityConfig, ARConfiguration* appleConfig)
{
    appleConfig.worldAlignment = GetARWorldAlignmentFromUnityARAlignment(unityConfig.alignment);
    appleConfig.lightEstimationEnabled = (BOOL)unityConfig.enableLightEstimation;
}

static inline void GetUnityARCameraDataFromCamera(UnityARCamera& unityARCamera, ARCamera* camera, BOOL getPointCloudData)
{
    CGSize nativeSize = GetAppController().rootView.bounds.size;
    matrix_float4x4 projectionMatrix = [camera projectionMatrixForOrientation:[[UIApplication sharedApplication] statusBarOrientation] viewportSize:nativeSize zNear:(CGFloat)unityCameraNearZ zFar:(CGFloat)unityCameraFarZ];
    
    ARKitMatrixToUnityARMatrix4x4(projectionMatrix, &s_CameraProjectionMatrix);
    ARKitMatrixToUnityARMatrix4x4(projectionMatrix, &unityARCamera.projectionMatrix);
    
    unityARCamera.trackingState = GetUnityARTrackingStateFromARTrackingState(camera.trackingState);
    unityARCamera.trackingReason = GetUnityARTrackingReasonFromARTrackingReason(camera.trackingStateReason);
    unityARCamera.getPointCloudData = getPointCloudData;
}

inline void UnityARPlaneGeometryFromARPlaneGeometry(UnityARPlaneGeometry& planeGeometry, ARPlaneGeometry *arPlaneGeometry)
{
    planeGeometry.vertexCount = arPlaneGeometry.vertexCount;
    planeGeometry.triangleCount = arPlaneGeometry.triangleCount;
    planeGeometry.textureCoordinateCount = arPlaneGeometry.textureCoordinateCount;
    planeGeometry.boundaryVertexCount = arPlaneGeometry.boundaryVertexCount;
    planeGeometry.vertices = (float *) arPlaneGeometry.vertices;
    planeGeometry.triangleIndices = (int *) arPlaneGeometry.triangleIndices;
    planeGeometry.textureCoordinates = (float *) arPlaneGeometry.textureCoordinates;
    planeGeometry.boundaryVertices = (float *) arPlaneGeometry.boundaryVertices;
    
}

inline void UnityARAnchorDataFromARAnchorPtr(UnityARAnchorData& anchorData, ARPlaneAnchor* nativeAnchor)
{
    anchorData.identifier = (void*)[nativeAnchor.identifier.UUIDString UTF8String];
    ARKitMatrixToUnityARMatrix4x4(nativeAnchor.transform, &anchorData.transform);
    anchorData.alignment = nativeAnchor.alignment;
    anchorData.center.x = nativeAnchor.center.x;
    anchorData.center.y = nativeAnchor.center.y;
    anchorData.center.z = nativeAnchor.center.z;
    anchorData.extent.x = nativeAnchor.extent.x;
    anchorData.extent.y = nativeAnchor.extent.y;
    anchorData.extent.z = nativeAnchor.extent.z;
    
    if (UnityIsARKit_1_5_Supported())
    {
        UnityARPlaneGeometryFromARPlaneGeometry(anchorData.planeGeometry, nativeAnchor.geometry);
    }
}

inline void UnityARMatrix4x4FromCGAffineTransform(UnityARMatrix4x4& outMatrix, CGAffineTransform displayTransform, BOOL isLandscape)
{
    if (isLandscape)
    {
        outMatrix.column0.x = displayTransform.a;
        outMatrix.column0.y = displayTransform.c;
        outMatrix.column0.z = displayTransform.tx;
        outMatrix.column1.x = displayTransform.b;
        outMatrix.column1.y = -displayTransform.d;
        outMatrix.column1.z = 1.0f - displayTransform.ty;
        outMatrix.column2.z = 1.0f;
        outMatrix.column3.w = 1.0f; 
    }
    else
    {
        outMatrix.column0.x = displayTransform.a;
        outMatrix.column0.y = -displayTransform.c;
        outMatrix.column0.z = 1.0f - displayTransform.tx;
        outMatrix.column1.x = displayTransform.b;
        outMatrix.column1.y = displayTransform.d;
        outMatrix.column1.z = displayTransform.ty;
        outMatrix.column2.z = 1.0f;
        outMatrix.column3.w = 1.0f;
    }
}

inline void UnityARUserAnchorDataFromARAnchorPtr(UnityARUserAnchorData& anchorData, ARAnchor* nativeAnchor)
{
    anchorData.identifier = (void*)[nativeAnchor.identifier.UUIDString UTF8String];
    ARKitMatrixToUnityARMatrix4x4(nativeAnchor.transform, &anchorData.transform);
}


#if ARKIT_USES_FACETRACKING
inline void UnityARFaceGeometryFromARFaceGeometry(UnityARFaceGeometry& faceGeometry, ARFaceGeometry *arFaceGeometry)
{
    faceGeometry.vertexCount = arFaceGeometry.vertexCount;
    faceGeometry.triangleCount = arFaceGeometry.triangleCount;
    faceGeometry.textureCoordinateCount = arFaceGeometry.textureCoordinateCount;
    faceGeometry.vertices = (float *) arFaceGeometry.vertices;
    faceGeometry.triangleIndices = (int *) arFaceGeometry.triangleIndices;
    faceGeometry.textureCoordinates = (float *) arFaceGeometry.textureCoordinates;
}

inline void UnityARFaceAnchorDataFromARFaceAnchorPtr(UnityARFaceAnchorData& anchorData, ARFaceAnchor* nativeAnchor)
{
    anchorData.identifier = (void*)[nativeAnchor.identifier.UUIDString UTF8String];
    ARKitMatrixToUnityARMatrix4x4(nativeAnchor.transform, &anchorData.transform);
    if (UnityIsARKit_2_0_Supported())
    {
        ARKitMatrixToUnityARMatrix4x4(nativeAnchor.leftEyeTransform, &anchorData.leftEyeTransform);
        ARKitMatrixToUnityARMatrix4x4(nativeAnchor.rightEyeTransform, &anchorData.rightEyeTransform);
        anchorData.lookAtPoint = UnityARVector3{nativeAnchor.lookAtPoint.x, nativeAnchor.lookAtPoint.y, nativeAnchor.lookAtPoint.z};
    }

    UnityARFaceGeometryFromARFaceGeometry(anchorData.faceGeometry, nativeAnchor.geometry);
    anchorData.blendShapes = (__bridge void *) nativeAnchor.blendShapes;
}
#endif

inline void UnityARImageAnchorDataFromARImageAnchorPtr(UnityARImageAnchorData& anchorData, ARImageAnchor* nativeAnchor)
{
    anchorData.identifier = (void*)[nativeAnchor.identifier.UUIDString UTF8String];
    ARKitMatrixToUnityARMatrix4x4(nativeAnchor.transform, &anchorData.transform);
    anchorData.referenceImageName = (void*)[nativeAnchor.referenceImage.name UTF8String];
    anchorData.referenceImageSize = nativeAnchor.referenceImage.physicalSize.width;
}

inline void UnityLightDataFromARFrame(UnityLightData& lightData, ARFrame *arFrame)
{
    if (arFrame.lightEstimate != NULL)
    {
#if ARKIT_USES_FACETRACKING
        if ([arFrame.lightEstimate class] == [ARDirectionalLightEstimate class])
        {
            lightData.arLightingType = DirectionalLightEstimate;
            ARDirectionalLightEstimate *dirLightEst = (ARDirectionalLightEstimate *) arFrame.lightEstimate;
            lightData.arDirectionalLightEstimate.sphericalHarmonicsCoefficients = (float *) dirLightEst.sphericalHarmonicsCoefficients.bytes;

            //[dirLightEst.sphericalHarmonicsCoefficients getBytes:lightData.arDirectionalLightEstimate.sphericalHarmonicsCoefficients length:sizeof(float)*27 ];

            UnityARVector4 dirAndIntensity;
            dirAndIntensity.x = dirLightEst.primaryLightDirection.x;
            dirAndIntensity.y = dirLightEst.primaryLightDirection.y;
            dirAndIntensity.z = dirLightEst.primaryLightDirection.z;
            dirAndIntensity.w = dirLightEst.primaryLightIntensity;
            lightData.arDirectionalLightEstimate.primaryLightDirectionAndIntensity = dirAndIntensity;
        }
        else
#endif
        {
            lightData.arLightingType = LightEstimate;
            lightData.arLightEstimate.ambientIntensity = arFrame.lightEstimate.ambientIntensity;
            lightData.arLightEstimate.ambientColorTemperature = arFrame.lightEstimate.ambientColorTemperature;
        }
    }
    
}


@interface UnityARAnchorCallbackWrapper : NSObject <UnityARAnchorEventDispatcher>
{
@public
    UNITY_AR_ANCHOR_CALLBACK _anchorAddedCallback;
    UNITY_AR_ANCHOR_CALLBACK _anchorUpdatedCallback;
    UNITY_AR_ANCHOR_CALLBACK _anchorRemovedCallback;
}
@end

@implementation UnityARAnchorCallbackWrapper

    -(void)sendAnchorAddedEvent:(ARAnchor*)anchor
    {
        UnityARAnchorData data;
        UnityARAnchorDataFromARAnchorPtr(data, (ARPlaneAnchor*)anchor);
       _anchorAddedCallback(data);
    }

    -(void)sendAnchorRemovedEvent:(ARAnchor*)anchor
    {
        UnityARAnchorData data;
        UnityARAnchorDataFromARAnchorPtr(data, (ARPlaneAnchor*)anchor);
       _anchorRemovedCallback(data);
    }

    -(void)sendAnchorUpdatedEvent:(ARAnchor*)anchor
    {
        UnityARAnchorData data;
        UnityARAnchorDataFromARAnchorPtr(data, (ARPlaneAnchor*)anchor);
       _anchorUpdatedCallback(data);
    }

@end

@interface UnityARUserAnchorCallbackWrapper : NSObject <UnityARAnchorEventDispatcher>
{
@public
    UNITY_AR_USER_ANCHOR_CALLBACK _anchorAddedCallback;
    UNITY_AR_USER_ANCHOR_CALLBACK _anchorUpdatedCallback;
    UNITY_AR_USER_ANCHOR_CALLBACK _anchorRemovedCallback;
}
@end

@implementation UnityARUserAnchorCallbackWrapper

    -(void)sendAnchorAddedEvent:(ARAnchor*)anchor
    {
        UnityARUserAnchorData data;
        UnityARUserAnchorDataFromARAnchorPtr(data, anchor);
       _anchorAddedCallback(data);
    }

    -(void)sendAnchorRemovedEvent:(ARAnchor*)anchor
    {
        UnityARUserAnchorData data;
        UnityARUserAnchorDataFromARAnchorPtr(data, anchor);
       _anchorRemovedCallback(data);
    }

    -(void)sendAnchorUpdatedEvent:(ARAnchor*)anchor
    {
        UnityARUserAnchorData data;
        UnityARUserAnchorDataFromARAnchorPtr(data, anchor);
       _anchorUpdatedCallback(data);
    }

@end

@interface UnityARFaceAnchorCallbackWrapper : NSObject <UnityARAnchorEventDispatcher>
{
@public
    UNITY_AR_FACE_ANCHOR_CALLBACK _anchorAddedCallback;
    UNITY_AR_FACE_ANCHOR_CALLBACK _anchorUpdatedCallback;
    UNITY_AR_FACE_ANCHOR_CALLBACK _anchorRemovedCallback;
}
@end

@implementation UnityARFaceAnchorCallbackWrapper

-(void)sendAnchorAddedEvent:(ARAnchor*)anchor
{
#if ARKIT_USES_FACETRACKING
    UnityARFaceAnchorData data;
    UnityARFaceAnchorDataFromARFaceAnchorPtr(data, (ARFaceAnchor*)anchor);
    _anchorAddedCallback(data);
#endif
}

-(void)sendAnchorRemovedEvent:(ARAnchor*)anchor
{
#if ARKIT_USES_FACETRACKING
    UnityARFaceAnchorData data;
    UnityARFaceAnchorDataFromARFaceAnchorPtr(data, (ARFaceAnchor*)anchor);
    _anchorRemovedCallback(data);
#endif
}

-(void)sendAnchorUpdatedEvent:(ARAnchor*)anchor
{
#if ARKIT_USES_FACETRACKING
    UnityARFaceAnchorData data;
    UnityARFaceAnchorDataFromARFaceAnchorPtr(data, (ARFaceAnchor*)anchor);
    _anchorUpdatedCallback(data);
#endif
}

@end

@interface UnityARImageAnchorCallbackWrapper : NSObject <UnityARAnchorEventDispatcher>
{
@public
    UNITY_AR_IMAGE_ANCHOR_CALLBACK _anchorAddedCallback;
    UNITY_AR_IMAGE_ANCHOR_CALLBACK _anchorUpdatedCallback;
    UNITY_AR_IMAGE_ANCHOR_CALLBACK _anchorRemovedCallback;
}
@end

@implementation UnityARImageAnchorCallbackWrapper

-(void)sendAnchorAddedEvent:(ARAnchor*)anchor
{
    UnityARImageAnchorData data;
    UnityARImageAnchorDataFromARImageAnchorPtr(data, (ARImageAnchor*)anchor);
    _anchorAddedCallback(data);
}

-(void)sendAnchorRemovedEvent:(ARAnchor*)anchor
{
    UnityARImageAnchorData data;
    UnityARImageAnchorDataFromARImageAnchorPtr(data, (ARImageAnchor*)anchor);
    _anchorRemovedCallback(data);
}

-(void)sendAnchorUpdatedEvent:(ARAnchor*)anchor
{
    UnityARImageAnchorData data;
    UnityARImageAnchorDataFromARImageAnchorPtr(data, (ARImageAnchor*)anchor);
    _anchorUpdatedCallback(data);
}

@end

static UnityPixelBuffer s_UnityPixelBuffers;


@implementation UnityARSession

- (id)init
{
    if (self = [super init])
    {
        _classToCallbackMap = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)setupMetal
{
    _device = MTLCreateSystemDefaultDevice();
    CVMetalTextureCacheCreate(NULL, NULL, _device, NULL, &_textureCache);
}

- (void)teardownMetal
{
    if (_textureCache) {
        CFRelease(_textureCache);
    }
}

static CGAffineTransform s_CurAffineTransform;

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame
{
    s_AmbientIntensity = frame.lightEstimate.ambientIntensity;
    s_TrackingQuality = (int)frame.camera.trackingState;
    s_PointCloud = frame.rawFeaturePoints.points;
    s_PointCloudSize = frame.rawFeaturePoints.count;

    UIInterfaceOrientation orient = [[UIApplication sharedApplication] statusBarOrientation];

    CGRect nativeBounds = [[UIScreen mainScreen] nativeBounds];
    CGSize nativeSize = GetAppController().rootView.bounds.size;
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    s_CurAffineTransform = CGAffineTransformInvert([frame displayTransformForOrientation:orientation viewportSize:nativeSize]);

    UnityARCamera unityARCamera;

    GetUnityARCameraDataFromCamera(unityARCamera, frame.camera, _getPointCloudData);

    
    CVPixelBufferRef pixelBuffer = frame.capturedImage;
    
    size_t imageWidth = CVPixelBufferGetWidth(pixelBuffer);
    size_t imageHeight = CVPixelBufferGetHeight(pixelBuffer);
    
    float imageAspect = (float)imageWidth / (float)imageHeight;
    float screenAspect = nativeBounds.size.height / nativeBounds.size.width;
    unityARCamera.videoParams.texCoordScale =  screenAspect / imageAspect;
    s_ShaderScale = screenAspect / imageAspect;
    
    unityARCamera.getLightEstimation = _getLightEstimation;
    if (_getLightEstimation)
    {
        UnityLightDataFromARFrame(unityARCamera.lightData, frame);
    }

    unityARCamera.videoParams.yWidth = (uint32_t)imageWidth;
    unityARCamera.videoParams.yHeight = (uint32_t)imageHeight;
    unityARCamera.videoParams.cvPixelBufferPtr = (void *) pixelBuffer;
    UnityARMatrix4x4 displayTransform;
    memset(&displayTransform, 0, sizeof(UnityARMatrix4x4));
    UnityARMatrix4x4FromCGAffineTransform(displayTransform, s_CurAffineTransform, UIInterfaceOrientationIsLandscape(orientation));
    unityARCamera.displayTransform = displayTransform;
    
    if (UnityIsARKit_2_0_Supported())
    {
        unityARCamera.worldMappingStatus = GetUnityARWorldMappingStatusFromARWorldMappingStatus(frame.worldMappingStatus);
    }

    if (_frameCallback != NULL)
    {

        matrix_float4x4 rotatedMatrix = matrix_identity_float4x4;
        unityARCamera.videoParams.screenOrientation = 3;

        // rotation  matrix
        // [ cos    -sin]
        // [ sin     cos]
        switch (orient) {
            case UIInterfaceOrientationPortrait:
                rotatedMatrix.columns[0][0] = 0;
                rotatedMatrix.columns[0][1] = 1;
                rotatedMatrix.columns[1][0] = -1;
                rotatedMatrix.columns[1][1] = 0;
                unityARCamera.videoParams.screenOrientation = 1;
                break;
            case UIInterfaceOrientationLandscapeLeft:
                rotatedMatrix.columns[0][0] = -1;
                rotatedMatrix.columns[0][1] = 0;
                rotatedMatrix.columns[1][0] = 0;
                rotatedMatrix.columns[1][1] = -1;
                unityARCamera.videoParams.screenOrientation = 4;
                break;
            case UIInterfaceOrientationPortraitUpsideDown:
                rotatedMatrix.columns[0][0] = 0;
                rotatedMatrix.columns[0][1] = -1;
                rotatedMatrix.columns[1][0] = 1;
                rotatedMatrix.columns[1][1] = 0;
                unityARCamera.videoParams.screenOrientation = 2;
                break;
            default:
                break;
        }

        matrix_float4x4 matrix = matrix_multiply(frame.camera.transform, rotatedMatrix);

        ARKitMatrixToUnityARMatrix4x4(matrix, &unityARCamera.worldTransform);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            _frameCallback(unityARCamera);
        });
    }

    
    if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2 || CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
        return;
    }
    
    if (s_UnityPixelBuffers.bEnable)
    {
        
        CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        
        if (s_UnityPixelBuffers.pYPixelBytes)
        {
            unsigned long numBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) * CVPixelBufferGetHeightOfPlane(pixelBuffer,0);
            void* baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer,0);
            memcpy(s_UnityPixelBuffers.pYPixelBytes, baseAddress, numBytes);
        }
        if (s_UnityPixelBuffers.pUVPixelBytes)
        {
            unsigned long numBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1) * CVPixelBufferGetHeightOfPlane(pixelBuffer,1);
            void* baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer,1);
            memcpy(s_UnityPixelBuffers.pUVPixelBytes, baseAddress, numBytes);
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    }
    
    id<MTLTexture> textureY = nil;
    id<MTLTexture> textureCbCr = nil;

    // textureY
    {
        const size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
        const size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
        MTLPixelFormat pixelFormat = MTLPixelFormatR8Unorm;
        
        
        CVMetalTextureRef texture = NULL;
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, _textureCache, pixelBuffer, NULL, pixelFormat, width, height, 0, &texture);
        if(status == kCVReturnSuccess)
        {
            textureY = CVMetalTextureGetTexture(texture);
            CFRelease(texture);
        }
    }

    // textureCbCr
    {
        const size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
        const size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
        MTLPixelFormat pixelFormat = MTLPixelFormatRG8Unorm;

        CVMetalTextureRef texture = NULL;
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, _textureCache, pixelBuffer, NULL, pixelFormat, width, height, 1, &texture);
        if(status == kCVReturnSuccess)
        {
            textureCbCr = CVMetalTextureGetTexture(texture);
            CFRelease(texture);
        }
    }

    if (textureY != nil && textureCbCr != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // always assign the textures atomic
            s_CapturedImageTextureY = textureY;
            s_CapturedImageTextureCbCr = textureCbCr;
        });
    }
}

- (void)session:(ARSession *)session didFailWithError:(NSError *)error
{
    if (_arSessionFailedCallback != NULL)
    {
        _arSessionFailedCallback(static_cast<const void*>([[error localizedDescription] UTF8String]));
    }
}

- (void)session:(ARSession *)session didAddAnchors:(NSArray<ARAnchor*>*)anchors
{
    [self sendAnchorAddedEventToUnity:anchors];
}

- (void)session:(ARSession *)session didUpdateAnchors:(NSArray<ARAnchor*>*)anchors
{
   [self sendAnchorUpdatedEventToUnity:anchors];
}

- (void)session:(ARSession *)session didRemoveAnchors:(NSArray<ARAnchor*>*)anchors
{
   [self sendAnchorRemovedEventToUnity:anchors];
}

- (void) sendAnchorAddedEventToUnity:(NSArray<ARAnchor*>*)anchors
{
    for (ARAnchor* anchorPtr in anchors)
    {
        id<UnityARAnchorEventDispatcher> dispatcher = [_classToCallbackMap objectForKey:[anchorPtr class]];
        [dispatcher sendAnchorAddedEvent:anchorPtr];
    }
}

- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera
{
    if (_arSessionTrackingChanged != NULL)
    {
        UnityARCamera unityCamera;
        GetUnityARCameraDataFromCamera(unityCamera, camera, _getPointCloudData);
        _arSessionTrackingChanged(unityCamera);
    }
}

- (void)sessionWasInterrupted:(ARSession *)session
{
    if (_arSessionInterrupted != NULL)
    {
        _arSessionInterrupted();

    }
}

- (void)sessionInterruptionEnded:(ARSession *)session
{
    if (_arSessionInterruptionEnded != NULL)
    {
        _arSessionInterruptionEnded();
    }
}

- (BOOL)sessionShouldAttemptRelocalization:(ARSession *)session
{
    if (_arSessionShouldRelocalize != NULL)
    {
        return _arSessionShouldRelocalize();
    }
    return NO;
}

- (void) sendAnchorRemovedEventToUnity:(NSArray<ARAnchor*>*)anchors
{
    for (ARAnchor* anchorPtr in anchors)
    {
        id<UnityARAnchorEventDispatcher> dispatcher = [_classToCallbackMap objectForKey:[anchorPtr class]];
        [dispatcher sendAnchorRemovedEvent:anchorPtr];
    }
}

- (void) sendAnchorUpdatedEventToUnity:(NSArray<ARAnchor*>*)anchors
{
    for (ARAnchor* anchorPtr in anchors)
    {
        id<UnityARAnchorEventDispatcher> dispatcher = [_classToCallbackMap objectForKey:[anchorPtr class]];
        [dispatcher sendAnchorUpdatedEvent:anchorPtr];
    }
}

@end

/// Create the native mirror to the C# ARSession object

extern "C" void* unity_CreateNativeARSession()
{
    UnityARSession *nativeSession = [[UnityARSession alloc] init];
    nativeSession->_session = [ARSession new];
    nativeSession->_session.delegate = nativeSession;
    unityCameraNearZ = .01;
    unityCameraFarZ = 30;
    s_UnityPixelBuffers.bEnable = false;
    return (__bridge_retained void*)nativeSession;
}

extern "C" void session_SetSessionCallbacks(const void* session, UNITY_AR_FRAME_CALLBACK frameCallback,
                                            UNITY_AR_SESSION_FAILED_CALLBACK sessionFailed,
                                            UNITY_AR_SESSION_VOID_CALLBACK sessionInterrupted,
                                            UNITY_AR_SESSION_VOID_CALLBACK sessionInterruptionEnded,
                                            UNITY_AR_SESSION_RELOCALIZE_CALLBACK sessionShouldRelocalize,
                                            UNITY_AR_SESSION_TRACKING_CHANGED trackingChanged,
                                            UNITY_AR_SESSION_WORLD_MAP_COMPLETION_CALLBACK worldMapCompletionHandler,
                                            UNITY_AR_SESSION_REF_OBJ_EXTRACT_COMPLETION_CALLBACK refObjExtractCompletionHandler)
{
    UnityARSession* nativeSession = (__bridge UnityARSession*)session;
    nativeSession->_frameCallback = frameCallback; 
    nativeSession->_arSessionFailedCallback = sessionFailed;
    nativeSession->_arSessionInterrupted = sessionInterrupted;
    nativeSession->_arSessionInterruptionEnded = sessionInterruptionEnded;
    nativeSession->_arSessionShouldRelocalize = sessionShouldRelocalize;
    nativeSession->_arSessionTrackingChanged = trackingChanged;
    nativeSession->_arSessionWorldMapCompletionHandler = worldMapCompletionHandler;
    nativeSession->_arSessionRefObjExtractCompletionHandler = refObjExtractCompletionHandler;
}

extern "C" void session_SetPlaneAnchorCallbacks(const void* session, UNITY_AR_ANCHOR_CALLBACK anchorAddedCallback, 
                                            UNITY_AR_ANCHOR_CALLBACK anchorUpdatedCallback, 
                                            UNITY_AR_ANCHOR_CALLBACK anchorRemovedCallback)
{
    UnityARSession* nativeSession = (__bridge UnityARSession*)session;
    UnityARAnchorCallbackWrapper* anchorCallbacks = [[UnityARAnchorCallbackWrapper alloc] init];
    anchorCallbacks->_anchorAddedCallback = anchorAddedCallback;
    anchorCallbacks->_anchorUpdatedCallback = anchorUpdatedCallback;
    anchorCallbacks->_anchorRemovedCallback = anchorRemovedCallback;
    [nativeSession->_classToCallbackMap setObject:anchorCallbacks forKey:[ARPlaneAnchor class]];
}

extern "C" void session_SetUserAnchorCallbacks(const void* session, UNITY_AR_USER_ANCHOR_CALLBACK userAnchorAddedCallback, 
                                            UNITY_AR_USER_ANCHOR_CALLBACK userAnchorUpdatedCallback, 
                                            UNITY_AR_USER_ANCHOR_CALLBACK userAnchorRemovedCallback)
{
    UnityARSession* nativeSession = (__bridge UnityARSession*)session;
    UnityARUserAnchorCallbackWrapper* userAnchorCallbacks = [[UnityARUserAnchorCallbackWrapper alloc] init];
    userAnchorCallbacks->_anchorAddedCallback = userAnchorAddedCallback;
    userAnchorCallbacks->_anchorUpdatedCallback = userAnchorUpdatedCallback;
    userAnchorCallbacks->_anchorRemovedCallback = userAnchorRemovedCallback;
    [nativeSession->_classToCallbackMap setObject:userAnchorCallbacks forKey:[ARAnchor class]];
}

extern "C" void session_SetFaceAnchorCallbacks(const void* session, UNITY_AR_FACE_ANCHOR_CALLBACK faceAnchorAddedCallback,
                                               UNITY_AR_FACE_ANCHOR_CALLBACK faceAnchorUpdatedCallback,
                                               UNITY_AR_FACE_ANCHOR_CALLBACK faceAnchorRemovedCallback)
{
#if ARKIT_USES_FACETRACKING
    UnityARSession* nativeSession = (__bridge UnityARSession*)session;
    UnityARFaceAnchorCallbackWrapper* faceAnchorCallbacks = [[UnityARFaceAnchorCallbackWrapper alloc] init];
    faceAnchorCallbacks->_anchorAddedCallback = faceAnchorAddedCallback;
    faceAnchorCallbacks->_anchorUpdatedCallback = faceAnchorUpdatedCallback;
    faceAnchorCallbacks->_anchorRemovedCallback = faceAnchorRemovedCallback;
    [nativeSession->_classToCallbackMap setObject:faceAnchorCallbacks forKey:[ARFaceAnchor class]];
#endif
}

extern "C" void session_SetImageAnchorCallbacks(const void* session, UNITY_AR_IMAGE_ANCHOR_CALLBACK imageAnchorAddedCallback,
                                                UNITY_AR_IMAGE_ANCHOR_CALLBACK imageAnchorUpdatedCallback,
                                                UNITY_AR_IMAGE_ANCHOR_CALLBACK imageAnchorRemovedCallback)
{
    if (UnityIsARKit_1_5_Supported())
    {
        UnityARSession* nativeSession = (__bridge UnityARSession*)session;
        UnityARImageAnchorCallbackWrapper* imageAnchorCallbacks = [[UnityARImageAnchorCallbackWrapper alloc] init];
        imageAnchorCallbacks->_anchorAddedCallback = imageAnchorAddedCallback;
        imageAnchorCallbacks->_anchorUpdatedCallback = imageAnchorUpdatedCallback;
        imageAnchorCallbacks->_anchorRemovedCallback = imageAnchorRemovedCallback;
        [nativeSession->_classToCallbackMap setObject:imageAnchorCallbacks forKey:[ARImageAnchor class]];
    }
}

extern "C" void StartWorldTrackingSessionWithOptions(void* nativeSession, ARKitWorldTrackingSessionConfiguration unityConfig, UnityARSessionRunOptions runOptions)
{
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    ARWorldTrackingConfiguration* config = [ARWorldTrackingConfiguration new];
    ARSessionRunOptions runOpts = GetARSessionRunOptionsFromUnityARSessionRunOptions(runOptions);
    GetARSessionConfigurationFromARKitWorldTrackingSessionConfiguration(unityConfig, config);
    session->_getPointCloudData = (BOOL) unityConfig.getPointCloudData;
    session->_getLightEstimation = (BOOL) unityConfig.enableLightEstimation;
    
    if(UnityIsARKit_1_5_Supported() && unityConfig.referenceImagesResourceGroup != NULL && strlen(unityConfig.referenceImagesResourceGroup) > 0)
    {
        NSString *strResourceGroup = [[NSString alloc] initWithUTF8String:unityConfig.referenceImagesResourceGroup];
        NSSet<ARReferenceImage *> *referenceImages = [ARReferenceImage referenceImagesInGroupNamed:strResourceGroup bundle:nil];
        config.detectionImages = referenceImages;
    }

    if(UnityIsARKit_2_0_Supported())
    {
        NSMutableSet<ARReferenceObject *> *referenceObjects = nullptr;
        if (unityConfig.referenceObjectsResourceGroup != NULL && strlen(unityConfig.referenceObjectsResourceGroup) > 0)
        {
            NSString *strResourceGroup = [[NSString alloc] initWithUTF8String:unityConfig.referenceObjectsResourceGroup];
            [referenceObjects setByAddingObjectsFromSet:[ARReferenceObject referenceObjectsInGroupNamed:strResourceGroup bundle:nil]];
        }
        
        if (unityConfig.ptrDynamicReferenceObjects != nullptr)
        {
            NSSet<ARReferenceObject *> *dynamicReferenceObjects = (__bridge NSSet<ARReferenceObject *> *)unityConfig.ptrDynamicReferenceObjects;
            if (referenceObjects != nullptr)
            {
                [referenceObjects setByAddingObjectsFromSet:dynamicReferenceObjects];
            }
            else
            {
                referenceObjects = dynamicReferenceObjects;
            }
        }
        
        config.detectionObjects = referenceObjects;
    }
    
    if (runOptions == UnityARSessionRunOptionsNone)
        [session->_session runWithConfiguration:config];
    else
        [session->_session runWithConfiguration:config options:runOpts];
    
    [session setupMetal];
}


extern "C" void StartWorldTrackingSession(void* nativeSession, ARKitWorldTrackingSessionConfiguration unityConfig)
{
    StartWorldTrackingSessionWithOptions(nativeSession, unityConfig, UnityARSessionRunOptionsNone);
}

extern "C" void StartSessionWithOptions(void* nativeSession, ARKitSessionConfiguration unityConfig, UnityARSessionRunOptions runOptions)
{
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    ARConfiguration* config = [AROrientationTrackingConfiguration new];
    ARSessionRunOptions runOpts = GetARSessionRunOptionsFromUnityARSessionRunOptions(runOptions);
    GetARSessionConfigurationFromARKitSessionConfiguration(unityConfig, config);
    session->_getPointCloudData = (BOOL) unityConfig.getPointCloudData;
    session->_getLightEstimation = (BOOL) unityConfig.enableLightEstimation;
    [session->_session runWithConfiguration:config options:runOpts ];
    [session setupMetal];
}

extern "C" void StartSession(void* nativeSession, ARKitSessionConfiguration unityConfig)
{
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    ARConfiguration* config = [AROrientationTrackingConfiguration new];
    GetARSessionConfigurationFromARKitSessionConfiguration(unityConfig, config);
    session->_getPointCloudData = (BOOL) unityConfig.getPointCloudData;
    session->_getLightEstimation = (BOOL) unityConfig.enableLightEstimation;
    [session->_session runWithConfiguration:config];
    [session setupMetal];
}

extern "C" void StartFaceTrackingSessionWithOptions(void* nativeSession, ARKitFaceTrackingConfiguration unityConfig, UnityARSessionRunOptions runOptions)
{
#if ARKIT_USES_FACETRACKING
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    ARConfiguration* config = [ARFaceTrackingConfiguration new];
    ARSessionRunOptions runOpts = GetARSessionRunOptionsFromUnityARSessionRunOptions(runOptions);
    GetARFaceConfigurationFromARKitFaceConfiguration(unityConfig, config);
    session->_getLightEstimation = (BOOL) unityConfig.enableLightEstimation;
    [session->_session runWithConfiguration:config options:runOpts ];
    [session setupMetal];
#else
    [NSException raise:@"UnityARKitPluginFaceTrackingNotEnabled" format:@"UnityARKitPlugin: Trying to start FaceTracking session without enabling it in settings."];
#endif
}

extern "C" void StartFaceTrackingSession(void* nativeSession, ARKitFaceTrackingConfiguration unityConfig)
{
    StartFaceTrackingSessionWithOptions(nativeSession, unityConfig, UnityARSessionRunOptionsNone);
}

extern "C" void PauseSession(void* nativeSession)
{
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    [session->_session pause];
}

extern "C" void StopSession(void* nativeSession)
{
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    [session teardownMetal];
}

extern "C" UnityARUserAnchorData SessionAddUserAnchor(void* nativeSession, UnityARUserAnchorData anchorData)
{
    // create a native ARAnchor and add it to the session
    // then return the data back to the user that they will
    // need in case they want to remove it
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    
    matrix_float4x4 anchor_transform = matrix_identity_float4x4;
    UnityARMatrix4x4ToARKitMatrix(anchorData.transform, &anchor_transform);
    ARAnchor *newAnchor = [[ARAnchor alloc] initWithTransform:anchor_transform];
    
    [session->_session addAnchor:newAnchor];
    UnityARUserAnchorData returnAnchorData;
    UnityARUserAnchorDataFromARAnchorPtr(returnAnchorData, newAnchor);
    return returnAnchorData;
}

extern "C" void SessionRemoveUserAnchor(void* nativeSession, const char * anchorIdentifier)
{
    // go through anchors and find the right one
    // then remove it from the session
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    for (ARAnchor* a in session->_session.currentFrame.anchors)
    {
        if ([[a.identifier UUIDString] isEqualToString:[NSString stringWithUTF8String:anchorIdentifier]])
        {
            [session->_session removeAnchor:a];
            return;
        }
    }
}

extern "C" void SessionSetWorldOrigin(void* nativeSession, UnityARMatrix4x4 worldMatrix)
{
    if (UnityIsARKit_1_5_Supported())
    {
        UnityARSession* session = (__bridge UnityARSession*)nativeSession;
        matrix_float4x4 arWorldMatrix;
        UnityARMatrix4x4ToARKitMatrix(worldMatrix, &arWorldMatrix);
        [session->_session setWorldOrigin:arWorldMatrix];
    }
}

extern "C" void SetCameraNearFar (float nearZ, float farZ)
{
    unityCameraNearZ = nearZ;
    unityCameraFarZ = farZ;
}

extern "C" void CapturePixelData (uint32_t enable, void* pYPixelBytes, void *pUVPixelBytes)
{
    s_UnityPixelBuffers.bEnable = (BOOL) enable;
    if (s_UnityPixelBuffers.bEnable)
    {
        s_UnityPixelBuffers.pYPixelBytes = pYPixelBytes;
        s_UnityPixelBuffers.pUVPixelBytes = pUVPixelBytes;
    } else {
        s_UnityPixelBuffers.pYPixelBytes = NULL;
        s_UnityPixelBuffers.pUVPixelBytes = NULL;
    }
}

extern "C" struct HitTestResult
{
    void* ptr;
    int count;
};

// Must match ARHitTestResult in ARHitTestResult.cs
extern "C" struct UnityARHitTestResult
{
    ARHitTestResultType type;
    double distance;
    UnityARMatrix4x4 localTransform;
    UnityARMatrix4x4 worldTransform;
    void* anchorPtr;
    bool isValid;
};

// Must match ARTextureHandles in UnityARSession.cs
extern "C" struct UnityARTextureHandles
{
    void* textureY;
    void* textureCbCr;
};

// Cache results locally
static NSArray<ARHitTestResult *>* s_LastHitTestResults;

// Returns the number of hits and caches the results internally
extern "C" int HitTest(void* nativeSession, CGPoint point, ARHitTestResultType types)
{
    UnityARSession* session = (__bridge UnityARSession*)nativeSession;
    point = CGPointApplyAffineTransform(CGPointMake(point.x, 1.0f - point.y), CGAffineTransformInvert(CGAffineTransformInvert(s_CurAffineTransform)));
    s_LastHitTestResults = [session->_session.currentFrame hitTest:point types:types];

    return (int)[s_LastHitTestResults count];
}
extern "C" UnityARHitTestResult GetLastHitTestResult(int index)
{
    UnityARHitTestResult unityResult;
    memset(&unityResult, 0, sizeof(UnityARHitTestResult));

    if (s_LastHitTestResults != nil && index >= 0 && index < [s_LastHitTestResults count])
    {
        ARHitTestResult* hitResult = s_LastHitTestResults[index];
        unityResult.type = hitResult.type;
        unityResult.distance = hitResult.distance;
        ARKitMatrixToUnityARMatrix4x4(hitResult.localTransform, &unityResult.localTransform);
        ARKitMatrixToUnityARMatrix4x4(hitResult.worldTransform, &unityResult.worldTransform);
        unityResult.anchorPtr = (void*)[hitResult.anchor.identifier.UUIDString UTF8String];
        unityResult.isValid = true;
    }

    return unityResult;
}

extern "C" UnityARTextureHandles GetVideoTextureHandles()
{
    UnityARTextureHandles handles;
    handles.textureY = (__bridge_retained void*)s_CapturedImageTextureY;
    handles.textureCbCr = (__bridge_retained void*)s_CapturedImageTextureCbCr;

    return handles;
}

extern "C" bool GetARPointCloud(float** verts, unsigned int* vertLength)
{
    *verts = (float*)s_PointCloud;
    *vertLength = (unsigned int)s_PointCloudSize * 4;
    return YES;
}

extern "C" UnityARMatrix4x4 GetCameraProjectionMatrix()
{
    return s_CameraProjectionMatrix;
}

extern "C" float GetAmbientIntensity()
{
    return s_AmbientIntensity;
}

extern "C" int GetTrackingQuality()
{
    return s_TrackingQuality;
}

extern "C" bool IsARKitWorldTrackingSessionConfigurationSupported()
{
    return ARWorldTrackingConfiguration.isSupported;
}

extern "C" bool IsARKitSessionConfigurationSupported()
{
    return AROrientationTrackingConfiguration.isSupported;
}

extern "C" void EnumerateVideoFormats(UNITY_AR_VIDEOFORMAT_CALLBACK videoFormatCallback)
{
    if (UnityIsARKit_1_5_Supported())
    {
        for(ARVideoFormat* arVideoFormat in ARWorldTrackingConfiguration.supportedVideoFormats)
        {
            UnityARVideoFormat videoFormat;
            videoFormat.ptrVideoFormat = (__bridge void *)arVideoFormat;
            videoFormat.imageResolutionWidth = arVideoFormat.imageResolution.width;
            videoFormat.imageResolutionHeight = arVideoFormat.imageResolution.height;
            videoFormat.framesPerSecond = arVideoFormat.framesPerSecond;
            videoFormatCallback(videoFormat);
        }
    }
}

extern "C" bool Native_IsARKit_1_5_Supported()
{
    return UnityIsARKit_1_5_Supported();
}

extern "C" bool IsARKitFaceTrackingConfigurationSupported()
{
#if ARKIT_USES_FACETRACKING
    return ARFaceTrackingConfiguration.isSupported;
#else
    [NSException raise:@"UnityARKitPluginFaceTrackingNotEnabled" format:@"UnityARKitPlugin: Checking FaceTracking device support without enabling it in settings."];
#endif
}

extern "C" void GetBlendShapesInfo(void* ptrDictionary, void (*visitorFn)(const char* key, const float value))
{
#if ARKIT_USES_FACETRACKING
    // Get your NSDictionary
    NSDictionary<ARBlendShapeLocation, NSNumber*> * dictionary = (__bridge NSDictionary<ARBlendShapeLocation, NSNumber*> *) ptrDictionary;
    
    for(NSString* key in dictionary)
    {
        NSNumber* value = [dictionary objectForKey:key];
        visitorFn([key UTF8String], [value floatValue]);
    }
#endif
}

#ifdef __cplusplus
extern "C" {
#endif
    
void session_GetCurrentWorldMap(void* sessionPtr, const void* callbackPtr)
{
    if (sessionPtr == nullptr)
        return;
    
    UnityARSession* nativeSession = (__bridge UnityARSession*)sessionPtr;
    if (!UnityAreFeaturesSupported(kUnityARKitSupportedFeaturesWorldMap))
    {
        // If 2.0 is not supported, then invoke callback immediately with a null world map
        nativeSession->_arSessionWorldMapCompletionHandler(callbackPtr, nullptr);
        return;
    }
    
    [nativeSession->_session getCurrentWorldMapWithCompletionHandler:^(ARWorldMap* worldMap, NSError* error)
     {
         if (error)
             NSLog(@"%@", error);

         nativeSession->_arSessionWorldMapCompletionHandler(callbackPtr, (__bridge_retained void*)worldMap);
     }];
}

void session_ExtractReferenceObject(void * sessionPtr, UnityARMatrix4x4 unityTransform, UnityARVector3 unityCenter, UnityARVector3 unityExtent, const void* callbackPtr)
{
    if (sessionPtr == nullptr)
        return;
    
    UnityARSession* nativeSession = (__bridge UnityARSession*)sessionPtr;

    if (!UnityAreFeaturesSupported(kUnityARKitSupportedFeaturesReferenceObject))
    {
        // If 2.0 is not supported, then invoke callback immediately with a null reference object
        nativeSession->_arSessionRefObjExtractCompletionHandler(callbackPtr, nullptr);
        return;
    }
    
    matrix_float4x4 transform;
    UnityARMatrix4x4ToARKitMatrix(unityTransform, &transform);
    
    const vector_float3 center{unityCenter.x, unityCenter.y, unityCenter.z};
    const vector_float3 extent{unityExtent.x, unityExtent.y, unityExtent.z};

    [nativeSession->_session createReferenceObjectWithTransform:transform center:center extent:extent completionHandler:^(ARReferenceObject * referenceObject, NSError * error)
    {
        if (error)
            NSLog(@"%@", error);
        nativeSession->_arSessionRefObjExtractCompletionHandler(callbackPtr, (__bridge_retained void*)referenceObject);
        
    }];
}
    
bool sessionConfig_IsEnvironmentTexturingSupported()
{
    if ([AREnvironmentProbeAnchor class])
    {
        return true;
    }
    else
    {
        return  false;
    }
}
  

#ifdef __cplusplus
}
#endif
