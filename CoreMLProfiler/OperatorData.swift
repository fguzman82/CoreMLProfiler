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
    let operator_id: String
    let operatorName: String
    let cost: Double
    let preferred_device: String
    let supported_devices: String
    let start_time: Double
    let end_time: Double
    let op_time: Double
    let ane_msg: String
}

//struct OperationDetails {
//    var operation: String
//    var runtimes: [String: Double]
//    var selectedBackend: String
//    var name: String?
//    var validationMessages: [String: String]
//}

struct OperationDetails: Codable {
    let operation: String
    let runtimes: [String: Double]
    let selectedBackend: String
    let name: String?
    let validationMessages: [String: String]
    
    var dictionaryRepresentation: [String: Any] {
        return [
            "operation": operation,
            "runtimes": runtimes,
            "selectedBackend": selectedBackend,
            "name": name ?? "Unknown",
            "validationMessages": validationMessages
        ]
    }
}



