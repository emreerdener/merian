import CoreGraphics

enum ExploreDetailZoomLayoutPolicy {
    static func resolvedSize(width: CGFloat?, height: CGFloat?) -> CGSize? {
        let finiteWidth = width.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }
        let finiteHeight = height.flatMap { value in
            value.isFinite && value > 0 ? value : nil
        }

        switch (finiteWidth, finiteHeight) {
        case let (width?, height?):
            return CGSize(width: width, height: height)
        case let (side?, nil), let (nil, side?):
            return CGSize(width: side, height: side)
        case (nil, nil):
            return nil
        }
    }
}
