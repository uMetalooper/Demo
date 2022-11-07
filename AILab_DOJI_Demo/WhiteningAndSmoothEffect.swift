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
    
    private var mpsImageGaussianBlur: MPSImageGaussianBlur!
    
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
        
        mpsImageGaussianBlur = MPSImageGaussianBlur(device: device, sigma: 3.0)
    }
    
    func process(backgroundTexture: MTLTexture, maskTexture: MTLTexture) -> MTLTexture? {
        let blurredTexture = makeTexture(width: backgroundTexture.width, height: backgroundTexture.height)
        let outputTexture = makeTexture(width: backgroundTexture.width, height: backgroundTexture.height)
        
        guard let commandQueue = commandQueue,
              let commandBufferBlur = commandQueue.makeCommandBuffer() else {
            fatalError("Cannot create command buffer!")
        }
        mpsImageGaussianBlur.encode(commandBuffer: commandBufferBlur, sourceTexture: backgroundTexture, destinationTexture: blurredTexture)
        commandBufferBlur.commit()
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor.colorAttachments[0]
        attachment?.clearColor = MTLClearColorMake(1, 0, 0, 1)
        attachment?.texture = outputTexture
        attachment?.loadAction = .clear
        attachment?.storeAction = .store
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to create Metal command buffer")
        }
        
        guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            fatalError("Failed to create Metal command encoder")
        }
        
        commandEncoder.label = "Whitening and masking"
        commandEncoder.setRenderPipelineState(renderPipelineState)
        commandEncoder.setVertexBuffer(vertexCoordBuffer, offset: 0, index: 0)
        commandEncoder.setVertexBuffer(textureCoordBuffer, offset: 0, index: 1)
        commandEncoder.setFragmentTexture(backgroundTexture, index: 0)
        commandEncoder.setFragmentTexture(blurredTexture, index: 1)
        commandEncoder.setFragmentTexture(maskTexture, index: 2)
        commandEncoder.setFragmentSamplerState(sampler, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        
        return outputTexture
    }
    
    func makeTexture(width: Int, height: Int) -> MTLTexture {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        textureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            fatalError()
        }
        return texture
    }
}
