import Foundation
import MetalKit

public class PreviewMetalView: MTKView {
    public var currentTexture: MTLTexture?

    private var renderPipelineState: MTLRenderPipelineState!
    private var commandQueue: MTLCommandQueue?
    
    private var vertexCoordBuffer: MTLBuffer!
    private var textureCoordBuffer: MTLBuffer!
    
    private var sampler: MTLSamplerState!

    public required init(coder: NSCoder) {
        super.init(coder: coder)

        device = MTLCreateSystemDefaultDevice()
        
        configureMetal()
        
        colorPixelFormat = .bgra8Unorm
    }
    
    func configureMetal() {
        let defaultLibrary = device!.makeDefaultLibrary()!
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "vertexPassThrough")
        pipelineDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "fragmentPassThrough")
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        sampler = device!.makeSamplerState(descriptor: samplerDescriptor)
        
        do {
            renderPipelineState = try device!.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Unable to create preview Metal view pipeline state. (\(error))")
        }
        
        commandQueue = device!.makeCommandQueue()
    }
    
    func setupTransform(width: Int, height: Int) {
        let vertexData: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
            1.0, -1.0, 0.0, 1.0,
            -1.0, 1.0, 0.0, 1.0,
            1.0, 1.0, 0.0, 1.0
        ]
        vertexCoordBuffer = device!.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: [])
        
        var widthRatio: Float = 1.0
        var heightRatio: Float = 1.0
        
        widthRatio = Float(bounds.width / CGFloat(width))
        heightRatio = Float(bounds.height / CGFloat(height))
        
        if widthRatio > heightRatio {
            heightRatio = widthRatio / heightRatio
            widthRatio = 1.0
        } else {
            widthRatio = heightRatio / widthRatio
            heightRatio = 1.0
        }
        
        var shiftX = (widthRatio - 1) / (2 * widthRatio)
        let shiftY = (heightRatio - 1) / (2 * heightRatio)
        
        let textData: [Float] = [
            shiftX, 1-shiftY,
            1-shiftX, 1-shiftY,
            shiftX, shiftY,
            1-shiftX, shiftY
        ]
        
        textureCoordBuffer = device?.makeBuffer(bytes: textData,
                                                length: textData.count * MemoryLayout<Float>.size,
                                                options: [])
    }

    public override func draw(_ rect:CGRect) {
        if let currentDrawable = self.currentDrawable, let imageTexture = currentTexture {
            let renderPassDescriptor = MTLRenderPassDescriptor()
            let attachment = renderPassDescriptor.colorAttachments[0]
            attachment?.clearColor = clearColor
            attachment?.texture = currentDrawable.texture
            attachment?.loadAction = .clear
            attachment?.storeAction = .store

            guard let commandQueue = commandQueue,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            setupTransform(width: imageTexture.width, height: imageTexture.height)

            commandEncoder.setRenderPipelineState(renderPipelineState)

            commandEncoder.setVertexBuffer(vertexCoordBuffer, offset: 0, index: 0)
            commandEncoder.setVertexBuffer(textureCoordBuffer, offset: 0, index: 1)
            commandEncoder.setFragmentTexture(imageTexture, index: 0)
            commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            commandEncoder.endEncoding()
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }
    }
}
