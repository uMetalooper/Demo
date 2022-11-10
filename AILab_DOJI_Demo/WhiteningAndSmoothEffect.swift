//
//  WhiteningAndSmoothEffect.swift
//  AILab_DOJI_Demo
//
//  Created by Computing on 07/11/2022.
//

import Metal
import MetalPerformanceShaders

class WhiteningAndSmoothEffect {
    private var device: MTLDevice
    private var renderPipelineState: MTLRenderPipelineState!
    private var commandQueue: MTLCommandQueue?
    
    private var vertexCoordBuffer: MTLBuffer!
    private var textureCoordBuffer: MTLBuffer!
    
    private var sampler: MTLSamplerState!
    
    private var mpsImageGaussianBlurImage: MPSImageGaussianBlur!
    private var mpsImageGaussianBlurSobel: MPSImageGaussianBlur!
    
    private var mpsImageSobel: MPSImageSobel!
    
    let blurredTexture: MTLTexture
    let maskTexture: MTLTexture
    let blurredMaskTexture: MTLTexture
    let outputTexture: MTLTexture
    
    init() {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.device = metalDevice
        } else {
            fatalError()
        }
        
        let defaultLibrary = device.makeDefaultLibrary()!
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "vertexEffect")
        pipelineDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "fragmentEffect")
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Unable to create preview Metal view pipeline state. (\(error))")
        }
        
        commandQueue = device.makeCommandQueue()
        
        let vertexData: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
            1.0, -1.0, 0.0, 1.0,
            -1.0, 1.0, 0.0, 1.0,
            1.0, 1.0, 0.0, 1.0
        ]
        vertexCoordBuffer = device.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: [])
        
        let textData: [Float] = [
            0, 1,
            1, 1,
            0, 0,
            1, 0
        ]
        
        textureCoordBuffer = device.makeBuffer(bytes: textData,
                                               length: textData.count * MemoryLayout<Float>.size,
                                               options: [])
        
        mpsImageGaussianBlurImage = MPSImageGaussianBlur(device: device, sigma: 5.0)
        mpsImageGaussianBlurSobel = MPSImageGaussianBlur(device: device, sigma: 1.0)
        
        let linearGrayColorTransform: [Float] = [ 0.22, 0.72, 0.072 ]
        mpsImageSobel = MPSImageSobel(device: device, linearGrayColorTransform: linearGrayColorTransform)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1080, height: 1920, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError()
        }
        blurredTexture = texture
        guard let texture2 = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError()
        }
        maskTexture    = texture2
        guard let texture3 = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError()
        }
        blurredMaskTexture = texture3
        guard let texture4 = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError()
        }
        outputTexture = texture4
    }
    
    func process(backgroundTexture: MTLTexture) -> MTLTexture? {
        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Cannot create command buffer!")
        }
        
        mpsImageGaussianBlurImage.encode(commandBuffer: commandBuffer, sourceTexture: backgroundTexture, destinationTexture: blurredTexture)
        
        mpsImageSobel.encode(commandBuffer: commandBuffer, sourceTexture: backgroundTexture, destinationTexture: maskTexture)
        
        mpsImageGaussianBlurSobel.encode(commandBuffer: commandBuffer, sourceTexture: maskTexture, destinationTexture: blurredMaskTexture)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]
        attachment?.clearColor = MTLClearColorMake(1, 0, 0, 1)
        attachment?.texture = outputTexture
        attachment?.loadAction = .clear
        attachment?.storeAction = .store
        
        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Failed to create Metal command encoder")
        }
        
        commandEncoder.label = "Whitening and masking"
        commandEncoder.setRenderPipelineState(renderPipelineState)
        commandEncoder.setVertexBuffer(vertexCoordBuffer, offset: 0, index: 0)
        commandEncoder.setVertexBuffer(textureCoordBuffer, offset: 0, index: 1)
        commandEncoder.setFragmentTexture(backgroundTexture, index: 0)
        commandEncoder.setFragmentTexture(blurredTexture, index: 1)
        commandEncoder.setFragmentTexture(blurredMaskTexture, index: 2)
        commandEncoder.setFragmentSamplerState(sampler, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        
        return outputTexture
    }
    
    public func makeTexture(width: Int, height: Int) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError()
        }
        return texture
    }
}
