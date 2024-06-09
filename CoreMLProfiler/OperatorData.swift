//
//  OperatorData.swift
//  CoreMLProfiler
//
//  Created by Fabio Guzman on 8/06/24.
//

import Foundation

struct OperatorData: Codable, Identifiable {
    var id: Int { op_number }
    let op_number: Int
    let operatorName: String
    let cost: Double
    let preferred_device: String
    let supported_devices: String
}

