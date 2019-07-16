//
//  ImageCell.swift
//  Rover
//
//  Created by Sean Rucker on 2017-08-17.
//  Copyright © 2017 Rover Labs Inc. All rights reserved.
//

import UIKit
import os

class ImageCell: BlockCell {
    let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleToFill
        return imageView
    }()
    
    override var content: UIView? {
        return imageView
    }
    
    override func configure(with block: Block) {
        super.configure(with: block)
        
        guard let imageBlock = block as? ImageBlock else {
            imageView.isHidden = true
            return
        }
        
        let originalBlockId = imageBlock.id
        self.imageView.configureAsImage(image: imageBlock.image) { [weak self] in
            return self?.block?.id == originalBlockId
        }
    }
}

extension UIImageView {
    func configureAsImage(image: Image, checkStillMatches: @escaping () -> Bool) {
        self.alpha = 0.0
        self.image = nil
        
        if frame == .zero {
            os_log("configureAsImage called with a zero frame. No good.", log: .rover)
            return
        }
        
        if let image = ImageStore.shared.image(for: image, frame: frame) {
            self.image = image
            self.alpha = 1.0
        } else {
            let originalFrame = self.frame
            ImageStore.shared.fetchImage(for: image, frame: frame) { [weak self] image in
                guard let image = image, checkStillMatches(), self?.frame == originalFrame else {
                    return
                }
                
                self?.image = image
                
                UIView.animate(withDuration: 0.25) {
                    self?.alpha = 1.0
                }
            }
        }
    }
}
