//
//  DateFormatter.swift
//  Rover
//
//  Created by Sean Rucker on 2019-05-10.
//  Copyright © 2019 Rover Labs Inc. All rights reserved.
//

import Foundation

extension DateFormatter {
    public static let rfc3339: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
