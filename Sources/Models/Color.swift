//
//  Color.swift
//  Rover
//
//  Created by Sean Rucker on 2017-10-19.
//  Copyright © 2017 Rover Labs Inc. All rights reserved.
//

import UIKit

public struct Color: Decodable {
    public var red: Int
    public var green: Int
    public var blue: Int
    public var alpha: Double
    
    public init(red: Int, green: Int, blue: Int, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

// MARK: Convenience Initializers

extension Color {
    var uiColor: UIColor {
        let red = CGFloat(self.red) / 255.0
        let green = CGFloat(self.green) / 255.0
        let blue = CGFloat(self.blue) / 255.0
        let alpha = CGFloat(self.alpha)
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    func uiColor(dimmedBy: Double) -> UIColor {
        let red = CGFloat(self.red) / 255.0
        let green = CGFloat(self.green) / 255.0
        let blue = CGFloat(self.blue) / 255.0
        let alpha = CGFloat(self.alpha) * CGFloat(dimmedBy)
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}