import UIKit
import AVFoundation
import CoreVideo
import Accelerate


public protocol VideoCaptureDelegate: class {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CVPixelBuffer?, timestamp: CMTime)
}

public class VideoCapture: NSObject {
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: VideoCaptureDelegate?
    public var fps = 50
    
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    let queue = DispatchQueue(label: "cameraQueue")
    
    var lastTimestamp = CMTime()
    
    public func setUp(sessionPreset: AVCaptureSession.Preset = .high,
                      completion: @escaping (Bool) -> Void) {
        queue.async {
            let success = self.setUpCamera(sessionPreset: sessionPreset)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    func setUpCamera(sessionPreset: AVCaptureSession.Preset) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset
        
        let position = AVCaptureDevice.Position.front
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: AVMediaType.video, position: position) else {
            print("Error: no video devices available")
            return false
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Error: could not create AVCaptureDeviceInput")
            return false
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        self.previewLayer = previewLayer
        
        let settings: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
        ]
        
        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // We want the buffers to be in portrait orientation otherwise they are
        // rotated by 90 degrees. Need to set this _after_ addOutput()!
        guard let connection = videoOutput.connection(with: AVFoundation.AVMediaType.video) else { return true}
        connection.videoOrientation = .portrait
        connection.isVideoMirrored = (position == .front)

        captureSession.commitConfiguration()
        return true
    }
    
    public func start() {
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
}

extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Because lowering the capture device's FPS looks ugly in the preview,
        // we capture at full speed but only call the delegate at its desired
        // framerate.
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let deltaTime = timestamp - lastTimestamp
        if deltaTime >= CMTimeMake(1, Int32(fps)) {
            lastTimestamp = timestamp
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            
            //let roiBuffer: CVPixelBuffer! = sampleBuffer.cropResize(destWidth: 128, destHeight: 128)
            
            delegate?.videoCapture(self, didCaptureVideoFrame: imageBuffer, timestamp: timestamp)
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("dropped frame")
    }
}

extension CMSampleBuffer {
    func cropResize(destWidth:UInt, destHeight:UInt)-> CVPixelBuffer! {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
        
        // Lock the image buffer
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        // Get information about the image
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let bytesPerRow = Int(CVPixelBufferGetBytesPerRow(imageBuffer))
        let height = UInt(CVPixelBufferGetHeight(imageBuffer))
        let width = UInt(CVPixelBufferGetWidth(imageBuffer))
        let options = [kCVPixelBufferCGImageCompatibilityKey:true,
                       kCVPixelBufferCGBitmapContextCompatibilityKey:true]
        let topMargin = (height - destHeight) / 2
        let leftMargin = (width - destWidth) * 2
        let baseAddressStart = UInt(bytesPerRow) * topMargin + leftMargin
        let addressPoint = baseAddress!.assumingMemoryBound(to: UInt8.self)
        
        var sourceBuffer = vImage_Buffer(data: addressPoint, height: height, width: width, rowBytes: bytesPerRow)
        
        //
        let destBytesPerRow = Int(destWidth * 4)
        let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(destHeight) * destBytesPerRow)
        defer {
            destData.deallocate(capacity: Int(destHeight) * destBytesPerRow)
        }
        var destBuffer = vImage_Buffer(data: destData, height: vImagePixelCount(destHeight),
                                       width: vImagePixelCount(destWidth), rowBytes: destBytesPerRow)

        var error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, numericCast(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return nil }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer,CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreateWithBytes(nil, Int(destWidth), Int(destHeight), pixelFormat, destData, destBytesPerRow, nil, nil, nil, &pixelBuffer)
        
        guard let pixelBuffer_ = pixelBuffer else {
            return nil
        }

        return pixelBuffer_;
    }
}
