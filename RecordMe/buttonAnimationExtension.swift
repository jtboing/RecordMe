//
//  buttonAnimationExtension.swift
//  Toastmasters
//
//  Created by JT on 24/12/17.
//  Copyright © 2017 Joseph Tobing. All rights reserved.
//

import Foundation
import UIKit

extension UIButton {
    
    func flash() {
        
        let flash = CABasicAnimation(keyPath: "opacity")
        flash.duration = 0.1
        flash.fromValue = 0.1
        flash.toValue = 1
        flash.timingFunction = CAMediaTimingFunction(name:kCAMediaTimingFunctionEaseInEaseOut)
        flash.autoreverses = true
        flash.repeatCount = 1
        
        layer.add(flash, forKey: nil)
    }
}
