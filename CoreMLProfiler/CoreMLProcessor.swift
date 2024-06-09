//
//  CoreMLProcessor.swift
//  CoreMLProfiler
//
//  Created by Fabio Guzman on 8/06/24.
//

import Foundation
import CoreML
import TabularData

@available(macOS 14.4, *)
class CoreMLProcessor: ObservableObject {
    static let shared = CoreMLProcessor()
    
    private init() {}
    
    @Published var consoleOutput: String = ""
    @Published var compileTime: Double = 0.0
    @Published var loadTime: Double = 0.0
    @Published var compileTimes: [Double] = []
    @Published var loadTimes: [Double] = []
    var modelPath: String = ""
    var processingUnit: Int = 0
    
    private func processingUnitsMap() -> [MLComputeUnits] {
        return [.all, .cpuOnly, .cpuAndGPU, .cpuAndNeuralEngine]
    }
    
    func processingUnitDescriptions() -> [String] {
        return ["all", "cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine"]
    }

    public func run() async throws -> OperationCounts {
        guard (0...3).contains(processingUnit) else {
            throw NSError(domain: "CoreMLProcessor", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid processing unit value. Must be between 0 and 3."])
        }

        guard modelPath.hasSuffix(".mlpackage") else {
            throw NSError(domain: "CoreMLProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid file type. Load the CoreML file with .mlpackage extension."])
        }

        let packageURL = URL(fileURLWithPath: self.modelPath)
        let config = MLModelConfiguration()
        config.computeUnits = processingUnitsMap()[processingUnit]

        log("Processing Unit Selected: \(processingUnitDescriptions()[processingUnit])")

        let (compiledModelURL, compileTimes) = try await compileModel(at: packageURL)
        DispatchQueue.main.async {
            self.compileTimes = compileTimes
            self.compileTime = compileTimes[compileTimes.count / 2] // Default to median
        }
        log("Time taken to compile model (median): \(compileTimes[compileTimes.count / 2]) ms")

        let (model, loadTimes) = try await loadModel(at: compiledModelURL, configuration: config)
        DispatchQueue.main.async {
            self.loadTimes = loadTimes
            self.loadTime = loadTimes[loadTimes.count / 2] // Default to median
        }
        log("Time taken to load model (median): \(loadTimes[loadTimes.count / 2]) ms")

        var medianPredictTime: Double = 0.0
        
        if let plan = try await getComputePlan(of: compiledModelURL, configuration: config) {
            let modelStructure = processModelStructure(plan.modelStructure, plan: plan, medianPredictTime: medianPredictTime, fullProfile: false)
            let jsonData = try JSONSerialization.data(withJSONObject: modelStructure, options: .prettyPrinted)
            
            try saveJSONToFile(jsonData: jsonData, fileName: "compute_plan.json")
            let counts = try processAndSaveSelectedColumns(from: jsonData, fullProfile: false)
            
            return counts
        } else {
            log("Failed to load the compute plan.")
            return OperationCounts(totalOp: 0, totalCPU: 0, totalGPU: 0, totalANE: 0)
        }
    }
    

//    private func compileModel(at packageURL: URL) async throws -> (URL, Double) {
//        var compileTimes: [Double] = []
//        var compiledModelURL: URL?
//
//        for _ in 1...10 {
//            let compileStartTime = DispatchTime.now()
//            let tempCompiledModelURL = try await MLModel.compileModel(at: packageURL)
//            let compileEndTime = DispatchTime.now()
//            let compileNanoTime = compileEndTime.uptimeNanoseconds - compileStartTime.uptimeNanoseconds
//            let compileTimeInterval = Double(compileNanoTime) / 1_000_000
//            compileTimes.append(compileTimeInterval)
//            compiledModelURL = tempCompiledModelURL
//        }
//
//        guard let finalCompiledModelURL = compiledModelURL else {
//            throw NSError(domain: "CoreMLProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to compile model."])
//        }
//
//        compileTimes.sort()
//        let medianCompileTime = compileTimes[compileTimes.count / 2]
//
//        log("Model compiled successfully at \(finalCompiledModelURL)")
//        log("Compilation times: \(compileTimes) ms")
//
//        return (finalCompiledModelURL, medianCompileTime)
//    }
    private func compileModel(at packageURL: URL) async throws -> (URL, [Double]) {
        var compileTimes: [Double] = []
        var compiledModelURL: URL?

        for _ in 1...10 {
            let compileStartTime = DispatchTime.now()
            let tempCompiledModelURL = try await MLModel.compileModel(at: packageURL)
            let compileEndTime = DispatchTime.now()
            let compileNanoTime = compileEndTime.uptimeNanoseconds - compileStartTime.uptimeNanoseconds
            let compileTimeInterval = Double(compileNanoTime) / 1_000_000
            compileTimes.append(compileTimeInterval)
            compiledModelURL = tempCompiledModelURL
        }

        guard let finalCompiledModelURL = compiledModelURL else {
            throw NSError(domain: "CoreMLProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to compile model."])
        }

        compileTimes.sort()
        log("Model compiled successfully at \(finalCompiledModelURL)")
        log("Compilation times: \(compileTimes) ms")

        return (finalCompiledModelURL, compileTimes)
    }

//    private func loadModel(at compiledModelURL: URL, configuration: MLModelConfiguration) async throws -> (MLModel, Double) {
//        var loadTimes: [Double] = []
//        var model: MLModel?
//
//        for _ in 1...10 {
//            let loadStartTime = DispatchTime.now()
//            let tempModel = try await MLModel.load(contentsOf: compiledModelURL, configuration: configuration)
//            let loadEndTime = DispatchTime.now()
//            let loadNanoTime = loadEndTime.uptimeNanoseconds - loadStartTime.uptimeNanoseconds
//            let loadTimeInterval = Double(loadNanoTime) / 1_000_000
//            loadTimes.append(loadTimeInterval)
//            model = tempModel
//        }
//
//        guard let finalModel = model else {
//            throw NSError(domain: "CoreMLProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load model."])
//        }
//
//        loadTimes.sort()
//        let medianLoadTime = loadTimes[loadTimes.count / 2]
//
//        log("Load times: \(loadTimes) ms")
//
//        return (finalModel, medianLoadTime)
//    }
    private func loadModel(at compiledModelURL: URL, configuration: MLModelConfiguration) async throws -> (MLModel, [Double]) {
        var loadTimes: [Double] = []
        var model: MLModel?

        for _ in 1...10 {
            let loadStartTime = DispatchTime.now()
            let tempModel = try await MLModel.load(contentsOf: compiledModelURL, configuration: configuration)
            let loadEndTime = DispatchTime.now()
            let loadNanoTime = loadEndTime.uptimeNanoseconds - loadStartTime.uptimeNanoseconds
            let loadTimeInterval = Double(loadNanoTime) / 1_000_000
            loadTimes.append(loadTimeInterval)
            model = tempModel
        }

        guard let finalModel = model else {
            throw NSError(domain: "CoreMLProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load model."])
        }

        loadTimes.sort()
        log("Load times: \(loadTimes) ms")

        return (finalModel, loadTimes)
    }

    private func getComputePlan(of modelURL: URL, configuration: MLModelConfiguration) async throws -> MLComputePlan? {
        return try await MLComputePlan.load(contentsOf: modelURL, configuration: configuration)
    }

    private func processModelStructure(_ modelStructure: MLModelStructure, plan: MLComputePlan, medianPredictTime: Double, fullProfile: Bool) -> [String: Any] {
        switch modelStructure {
        case .program(let program):
            return getProgramStructure(program: program, plan: plan, medianPredictTime: medianPredictTime, fullProfile: fullProfile)
        default:
            return ["error": "Unsupported model structure"]
        }
    }

    private func getProgramStructure(program: MLModelStructure.Program, plan: MLComputePlan, medianPredictTime: Double, fullProfile: Bool) -> [String: Any] {
        var programStructure: [String: Any] = [:]
        var operationCount = 0
        for (functionName, function) in program.functions {
            programStructure[functionName] = getFunctionStructure(function: function, plan: plan, operationCount: &operationCount, medianPredictTime: medianPredictTime, fullProfile: fullProfile)
        }
        return programStructure
    }

    private func getFunctionStructure(function: MLModelStructure.Program.Function, plan: MLComputePlan, operationCount: inout Int, medianPredictTime: Double, fullProfile: Bool) -> [String: Any] {
        var functionStructure: [String: Any] = [:]
        functionStructure["inputs"] = function.inputs.map { ["name": $0.name, "type": String(describing: $0.type)] }
        functionStructure["block"] = getBlockStructure(block: function.block, plan: plan, operationCount: &operationCount, medianPredictTime: medianPredictTime, fullProfile: fullProfile)
        return functionStructure
    }

    private func getBlockStructure(block: MLModelStructure.Program.Block, plan: MLComputePlan, operationCount: inout Int, medianPredictTime: Double, fullProfile: Bool) -> [String: Any] {
        var blockStructure: [String: Any] = [:]
        blockStructure["inputs"] = block.inputs.map { ["name": $0.name, "type": String(describing: $0.type)] }
        blockStructure["outputs"] = block.outputNames
        
        var opExecutionStartTime = 0.0
        var opExecutionEndTime = 0.0
       
        blockStructure["operations"] = block.operations.compactMap { operation in
            let cost = plan.estimatedCost(of: operation)
            guard let costWeight = cost?.weight else {
            return nil
            }
            opExecutionEndTime = opExecutionStartTime + (medianPredictTime) * costWeight
            let operationDict = getOperationStructure(operation: operation, plan: plan, operationCount: &operationCount, startTime: opExecutionStartTime, endTime: opExecutionEndTime, medianPredictTime: medianPredictTime, cost: costWeight, fullProfile: fullProfile)
            opExecutionStartTime = opExecutionEndTime
            return operationDict
        } as [[String: Any]]
        return blockStructure
    }

    private func getOperationStructure(operation: MLModelStructure.Program.Operation, plan: MLComputePlan, operationCount: inout Int, startTime: Double, endTime: Double, medianPredictTime: Double, cost: Double, fullProfile: Bool) -> [String: Any]? {
        let deviceUsage = plan.deviceUsage(for: operation)
        operationCount += 1
        var operationStructure: [String: Any] = [:]
        
        operationStructure["op_number"] = operationCount
        operationStructure["operatorName"] = operation.operatorName
        operationStructure["inputs"] = operation.inputs.map { ["name": $0.key, "bindings": $0.value.bindings.map { getName(for: $0) } ] }
        operationStructure["outputs"] = operation.outputs.map { ["name": $0.name, "type": String(describing: $0.type)] }
        operationStructure["blocks"] = operation.blocks.map { getBlockStructure(block: $0, plan: plan, operationCount: &operationCount, medianPredictTime: medianPredictTime, fullProfile: fullProfile) }
        operationStructure["cost"] = cost
        operationStructure["preferred_device"] = mapDeviceUsage(deviceUsage?.preferred)
        operationStructure["supported_devices"] = deviceUsage?.supported.map { mapDeviceUsage($0) }.joined(separator: ", ")
                
        return operationStructure
    }

    private func mapDeviceUsage(_ device: MLComputeDevice?) -> String {
        switch device {
        case .cpu(_):
            return "CPU"
        case .gpu(_):
            return "GPU"
        case .neuralEngine(_):
            return "ANE"
        default:
            return ""
        }
    }

    private func saveJSONToFile(jsonData: Data, fileName: String) throws {
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let filePath = URL(fileURLWithPath: currentPath).appendingPathComponent(fileName)
        try jsonData.write(to: filePath)
        log("JSON saved to \(filePath.path)")
    }

    private func getName(for binding: MLModelStructure.Program.Binding) -> String {
        switch binding {
        case .name(let n):
            return n
        case .value(_):
            return "value"
        @unknown default:
            return "unknown"
        }
    }

//    private func processAndSaveSelectedColumns(from jsonData: Data, fullProfile: Bool) throws {
//        let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
//        guard let jsonDict = json as? [String: Any],
//            let main = jsonDict["main"] as? [String: Any],
//            let block = main["block"] as? [String: Any],
//            let operations = block["operations"] as? [[String: Any]] else {
//            throw NSError(domain: "CoreMLProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure."])
//        }
//
//        let operationsData = try JSONSerialization.data(withJSONObject: operations, options: [])
//        let dataFrame = try DataFrame(jsonData: operationsData)
//
//        let selectedDataFrame: DataFrame
//        selectedDataFrame = dataFrame.selecting(columnNames: "op_number", "operatorName", "cost", "preferred_device", "supported_devices")
//
//        var options = JSONWritingOptions()
//        options.prettyPrint = true
//
//        let fileManager = FileManager.default
//        let currentPath = fileManager.currentDirectoryPath
//        let filePath = URL(fileURLWithPath: currentPath).appendingPathComponent("compute_plan_operation_table.json")
//
//        try selectedDataFrame.writeJSON(to: filePath, options: options)
//
//        log("JSON saved to \(filePath.path)")
//    }
    struct OperationCounts {
        var totalOp: Int
        var totalCPU: Int
        var totalGPU: Int
        var totalANE: Int
    }

    private func processAndSaveSelectedColumns(from jsonData: Data, fullProfile: Bool) throws -> OperationCounts {
        let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
        guard let jsonDict = json as? [String: Any],
              let main = jsonDict["main"] as? [String: Any],
              let block = main["block"] as? [String: Any],
              let operations = block["operations"] as? [[String: Any]] else {
            throw NSError(domain: "CoreMLProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure."])
        }

        let operationsData = try JSONSerialization.data(withJSONObject: operations, options: [])
        let dataFrame = try DataFrame(jsonData: operationsData)

        let selectedDataFrame: DataFrame
        selectedDataFrame = dataFrame.selecting(columnNames: "op_number", "operatorName", "cost", "preferred_device", "supported_devices")

        let totalOp = selectedDataFrame.rows.count
        let preferredDeviceColumn = ColumnID<String>("preferred_device", String.self)
        let totalCPU = selectedDataFrame.filter(on: preferredDeviceColumn) { $0 == "CPU" }.rows.count
        let totalGPU = selectedDataFrame.filter(on: preferredDeviceColumn) { $0 == "GPU" }.rows.count
        let totalANE = selectedDataFrame.filter(on: preferredDeviceColumn) { $0 == "ANE" }.rows.count

        var options = JSONWritingOptions()
        options.prettyPrint = true

        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        let filePath = URL(fileURLWithPath: currentPath).appendingPathComponent("compute_plan_operation_table.json")
        
        try selectedDataFrame.writeJSON(to: filePath, options: options)

        log("JSON saved to \(filePath.path)")

        return OperationCounts(totalOp: totalOp, totalCPU: totalCPU, totalGPU: totalGPU, totalANE: totalANE)
    }


    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.consoleOutput += message + "\n"
        }
    }
}
