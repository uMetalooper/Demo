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
    @IBOutlet weak var filterSwitch: UISwitch!
    
    // MARK: - Vision + CoreML
    private lazy var model = { return try! BackgroundRemover_ImageType().model }()
    private var visionRequest: VNCoreMLRequest?
    
    // MARK: - Image processing
    private var filter = WhiteningAndSmoothEffect()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        setupCaptureSession()
        session.startRunning()
        
        createTextureCache()
        
        setupModel()
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
            visionRequest?.imageCropAndScaleOption = .scaleFill
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
        
        guard let backgroundTexture = createImageTexture(previewPixelBuffer: previewPixelBuffer) else {
            return
        }
        
        if filterSwitch.isOn {
            // CoreML inference
//            let imageHandler = VNImageRequestHandler(cvPixelBuffer: previewPixelBuffer, options: [:])
//            guard let visionRequest = visionRequest else {
//                return
//            }
//
//            try? imageHandler.perform([visionRequest])
//            guard let observations = visionRequest.results as? [VNCoreMLFeatureValueObservation] else {
//                return
//            }
//            var outputMask: MLMultiArray?
//            for obs in observations {
//                if obs.featureName == "output_mask" {
//                    outputMask = obs.featureValue.multiArrayValue
//                }
//            }
//            guard let unwrappedOutputMask = outputMask else { return }
            
            // Metal effect
            // if let maskTexture = outputMaskToTexture(outputMask: unwrappedOutputMask),
            
            if let processedTexture = filter.process(backgroundTexture: backgroundTexture) {
                previewMetalView.currentTexture = processedTexture
            } else {
                previewMetalView.currentTexture = backgroundTexture
            }
        } else {
            previewMetalView.currentTexture = backgroundTexture
        }
    }
    
    private func createImageTexture(previewPixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(previewPixelBuffer)
        let height = CVPixelBufferGetHeight(previewPixelBuffer)
        
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
            return nil
        }
        return texture
    }
    
    private func outputMaskToTexture(outputMask: MLMultiArray) -> MTLTexture? {
        let maskHeight = outputMask.shape[2] as! Int
        let maskWidth = outputMask.shape[3] as! Int
        var skinMask = [UInt8](repeating: 0, count: maskWidth * maskHeight * 4)
        for row in 0..<maskHeight {
            for col in 0..<maskWidth {
                let key = [0, 0, row, col] as [NSNumber]
                let val = outputMask[key] as! Float32
                if val > 0.8 {
                    skinMask[(row * maskWidth + col) * 4] = 255
                    skinMask[(row * maskWidth + col) * 4 + 1] = 255
                    skinMask[(row * maskWidth + col) * 4 + 2] = 255
                    skinMask[(row * maskWidth + col) * 4 + 3] = 255
                }
            }
        }
        
        let maskTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: maskWidth, height: maskHeight, mipmapped: false)
        maskTextureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        let maskTexture = metalDevice.makeTexture(descriptor: maskTextureDescriptor)
        let region = MTLRegionMake2D(0, 0, maskWidth, maskHeight)
        maskTexture?.replace(region: region, mipmapLevel: 0, withBytes: skinMask, bytesPerRow: maskWidth * 4)
        return maskTexture
    }
}
