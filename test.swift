import Accelerate

func test() {
    var vBuffer = vImage_Buffer()
    var histogram = [vImagePixelCount](repeating: 0, count: 256)
    histogram.withUnsafeMutableBufferPointer { ptr in
        let err = vImageHistogramCalculation_Planar8(&vBuffer, ptr.baseAddress!, vImage_Flags(kvImageNoFlags))
    }
}
