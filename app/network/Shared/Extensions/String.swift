//
//  String.swift
//  app
//
//  Created by Stuart Kuentzel on 2025/05/16.
//
import Foundation

extension String {
    func isEmail() -> Bool {
        return ValidationUtils.isValidEmail(self)
    }
}
