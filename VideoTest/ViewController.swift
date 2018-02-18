//
//  ViewController.swift
//  VideoTest
//
//  Created by Tae-hoon Kim on 09/02/2018.
//  Copyright © 2018 Tae-hoon Kim. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController {
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    
    let MaxTrackingAge = 15
    let overlayView = UIView()
    var visionSequenceHandler: VNSequenceRequestHandler!
    var videoCapture: VideoCapture!
    var request_fd: VNDetectFaceRectanglesRequest!
    var request_ot: VNTrackObjectRequest!
    var lastTrackingObservation: VNDetectedObjectObservation!
    var trackingObservationAge = 0
    var startTimes: [CFTimeInterval] = []
    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    var frameSize: CGSize!
    let semaphore = DispatchSemaphore(value: 2)
    let queueArrayMT = DispatchQueue(label: "ArrayQueue")

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpVision()
        setUpCamera()
        
        self.overlayView.frame = self.videoPreview.frame
        self.view.addSubview(self.overlayView)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self as VideoCaptureDelegate
        videoCapture.fps = 50
        videoCapture.setUp { success in
            if success {
                // Add the video preview into the UI.
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                    self.videoPreview.contentMode = .scaleToFill
                }
                self.videoCapture.start()
            }
        }
    }
    
    func setUpVision() {
        self.request_fd = VNDetectFaceRectanglesRequest(completionHandler: self.onFaceDetected)
        self.request_ot = nil
    }
    
    //
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizePreviewLayer()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    //
    func detectFace(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame. Note that
        // predict() can be called on the next frame while the previous one is
        // still being processed. Hence the need to queue up the start times.
        self.queueArrayMT.async {
            self.startTimes.append(CACurrentMediaTime())
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([self.request_fd])
    }
    
    func trackFace(pixelBuffer: CVPixelBuffer) {
        self.queueArrayMT.async {
            self.startTimes.append(CACurrentMediaTime())
        }

        if self.visionSequenceHandler == nil {
            self.visionSequenceHandler = VNSequenceRequestHandler()
        }
        if self.request_ot == nil {
            self.request_ot = VNTrackObjectRequest(detectedObjectObservation: self.lastTrackingObservation, completionHandler: self.onObjectTrackingUpdated)
        }
        self.request_ot.trackingLevel = .accurate
        self.request_ot.inputObservation = self.lastTrackingObservation
        try? self.visionSequenceHandler.perform([self.request_ot], on: pixelBuffer)
    }
    
    func onFaceDetected(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNDetectedObjectObservation] {
            // The observations appear to be sorted by confidence already, so we
            // take the top 5 and map them to an array of (String, Double) tuples.
            DispatchQueue.main.async {
                if observations.count > 0 {
                    self.trackingObservationAge += 1
                }
                else {
                    self.trackingObservationAge = 0
                }
                for faceObservation in observations {
                    self.lastTrackingObservation = faceObservation
                    break
                }
                self.show(results:observations)
                self.semaphore.signal()
            }
        }
    }
    
    private func onObjectTrackingUpdated(_ request: VNRequest, error: Error?) {
        // Dispatch to the main queue because we are touching non-atomic, non-thread safe properties of the view controller
        if let observations = request.results as? [VNDetectedObjectObservation] {
            DispatchQueue.main.async {
                if let newObservation = observations.first {
                    self.lastTrackingObservation = newObservation
                    //
                    self.trackingObservationAge += 1
                    if self.trackingObservationAge > self.MaxTrackingAge {
                        self.trackingObservationAge = 0
                    }
                    //
                    self.show(results:[newObservation])
                }
                else {
                    self.trackingObservationAge = 0
                }
                self.semaphore.signal()
            }
        }
    }

    //
    func show(results: [VNDetectedObjectObservation]) {
        self.overlayView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        if (results.count > 0) {
            for faceObservation in results {
                let boundingRect = faceObservation.boundingBox
                predictionLabel.text = String(format:"%.2f,%.2f,%.2f,%.2f", boundingRect.origin.x, boundingRect.origin.y, boundingRect.size.width, boundingRect.size.height)
            }
            //
            let imageRect = AVMakeRect(aspectRatio: self.frameSize, insideRect: self.overlayView.bounds)
            results.map { $0.faceShapeLayer(in: imageRect) }.forEach(self.overlayView.layer.addSublayer)
        }
        else {
            predictionLabel.text = "No Face"
        }
        
        let fps = self.measureFPS()
        self.queueArrayMT.sync {
            let elapsed = CACurrentMediaTime() - self.startTimes.remove(at: 0)
            timeLabel.text = String(format: "Elapsed %.5f seconds - %.2f FPS", elapsed, fps)
        }
    }
    
    func measureFPS() -> Double {
        // Measure how many frames were actually delivered per second.
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        return currentFPSDelivered
    }
}

extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.
            if self.frameSize == nil {
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                self.frameSize = CGSize(width:width, height:height)
            }
            semaphore.wait()
            DispatchQueue.global().async {
                if self.trackingObservationAge == 0 {
                    self.visionSequenceHandler = nil
                    self.detectFace(pixelBuffer: pixelBuffer)
                }
                else {
                    self.trackFace(pixelBuffer: pixelBuffer)
                }
            }
        }
    }
}

private extension VNDetectedObjectObservation {
    func faceShapeLayer(in imageRect:CGRect) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = faceRect(in: imageRect)
        layer.borderColor = UIColor.blue.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 3
        return layer
    }
    
    func faceRect(in imageRect:CGRect) -> CGRect {
        if boundingBox.origin.x.isNaN {
            return CGRect(x: -1, y: -1, width: 1, height: 1)
        }
        let w = boundingBox.size.width * imageRect.width
        let h = boundingBox.size.height * imageRect.height
        let x = boundingBox.origin.x * imageRect.width
        let y = imageRect.maxY - (boundingBox.origin.y * imageRect.height) - h
        return CGRect(x: x , y: y, width: w, height: h)
    }
}

