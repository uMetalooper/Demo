//
//  ViewController.swift
//  AILab_DOJI_Demo
//
//  Created by Computing on 05/11/2022.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Capture Session
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "Camera Queue")
    
    // MARK: - CoreVideo + Metal
    private var metalDevice = MTLCreateSystemDefaultDevice()!
    private var textureCache: CVMetalTextureCache?
    
    // MARK: - Properties
    @IBOutlet weak var previewMetalView: PreviewMetalView!
    @IBOutlet weak var debugLabel: UILabel!
    
    // MARK: - Vision + CoreML
    private lazy var model = { return try! BackgroundRemover_ImageType().model }()
    private var visionRequest: VNCoreMLRequest!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        setupCaptureSession()
        session.startRunning()
        
        createTextureCache()
    }

    func setupCaptureSession() {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        
        let position: AVCaptureDevice.Position = .back
        
        let device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position).devices.first!
        
        let videoInput = try! AVCaptureDeviceInput(device: device)
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        } else {
            print("Cannot add input device.")
            session.commitConfiguration()
            return
        }
               
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        } else {
            print("Cannot add video output.")
            session.commitConfiguration()
            return
        }
        
        guard let connection = videoOutput.connection(with: .video) else {
            session.commitConfiguration()
            return
        }
        connection.videoOrientation = .portrait
        
        session.commitConfiguration()
    }
    
    func createTextureCache() {
        var newTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &newTextureCache) == kCVReturnSuccess {
            textureCache = newTextureCache
        } else {
            assertionFailure("Unable to allocate texture cache")
        }
    }
    
    func setupModel() {
        if let visionModel = try? VNCoreMLModel(for: model) {
            visionRequest = VNCoreMLRequest(model: visionModel)
            visionRequest.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError()
        }
    }
}

extension ViewController {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let previewPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let width = CVPixelBufferGetWidth(previewPixelBuffer)
        let height = CVPixelBufferGetHeight(previewPixelBuffer)
        
        debugLabel.text = "width=\(width), height=\(height)"
        
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  textureCache!,
                                                  previewPixelBuffer,
                                                  nil,
                                                  .bgra8Unorm,
                                                  width,
                                                  height,
                                                  0,
                                                  &cvTextureOut)
        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            return
        }
        
        previewMetalView.currentTexture = texture
    }
}
