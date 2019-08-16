//
//  ImagePollOption.swift
//  Rover
//
//  Created by Sean Rucker on 2019-08-15.
//  Copyright © 2019 Rover Labs Inc. All rights reserved.
//

import UIKit

class ImagePollOption: UIView {
    let stackView = UIStackView()
    let image: ImagePollOptionImage
    let label: ImagePollOptionLabel
    let overlay: ImagePollOptionOverlay
    
    let option: ImagePollBlock.ImagePoll.Option
    let tapHandler: () -> Void
    
    init(option: ImagePollBlock.ImagePoll.Option, tapHandler: @escaping () -> Void) {
        self.option = option
        self.tapHandler = tapHandler
        image = ImagePollOptionImage(option: option)
        label = ImagePollOptionLabel(option: option)
        overlay = ImagePollOptionOverlay(option: option)
        super.init(frame: .zero)
        
        clipsToBounds = true
        
        // stackView
        
        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        // image
        stackView.addArrangedSubview(image)
        
        // label
        stackView.addArrangedSubview(label)
        
        // overlay
        
        overlay.alpha = 0
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.bottomAnchor.constraint(equalTo: image.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: image.leadingAnchor),
            overlay.topAnchor.constraint(equalTo: image.topAnchor),
            overlay.trailingAnchor.constraint(equalTo: image.trailingAnchor)
        ])
        
        // gestureRecognizer
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(gestureRecognizer)
        
        // configuration
        
        configureOpacity(opacity: option.opacity)
        configureBackgroundColor(color: option.background.color, opacity: option.opacity)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setResult(_ result: PollCell.OptionResult, animated: Bool) {
        overlay.fillBar.setFillPercentage(to: result.fraction, animated: animated)
//        label.setPercentage(to: result.percentage, animated: animated)
        overlay.label.text = "\(result.percentage)%"
        label.isSelected = result.selected
        
        let duration: TimeInterval = animated ? 0.167 : 0
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut], animations: { [weak self] in
            self?.overlay.alpha = 1
        })
    }
    
    func clearResult() {
        label.isSelected = false
        overlay.alpha = 0
    }
    
    // MARK: Actions
    
    @objc
    private func didTap(gestureRecognizer: UIGestureRecognizer) {
        tapHandler()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        configureBorder(border: option.border, constrainedByFrame: self.frame)
    }
}