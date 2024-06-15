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
    @Published var compileTimes: [Double] = Array(repeating: 0.0, count: 10)
    @Published var loadTimes: [Double] = []
    @Published var predictTimes: [Double] = []
    var modelPath: String = ""
    var processingUnit: Int = 0
    var fullProfile: Bool = false
    
    private func processingUnitsMap() -> [MLComputeUnits] {
        return [.all, .cpuOnly, .cpuAndGPU, .cpuAndNeuralEngine]
    }
    
    func processingUnitDescriptions() -> [String] {
        return ["all", "cpuOnly", "cpuAndGPU", "cpuAndNeuralEngine"]
    }

    public func run() async throws -> (DataFrame, OperationCounts) {
        guard (0...3).contains(processingUnit) else {
            throw NSError(domain: "CoreMLProcessor", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid processing unit value. Must be between 0 and 3."])
        }

        guard modelPath.hasSuffix(".mlpackage") || modelPath.hasSuffix(".mlmodelc") else {
            throw NSError(domain: "CoreMLProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid file type. Load the CoreML file with .mlpackage or .mlmodelc extension."])
        }

        let packageURL = URL(fileURLWithPath: self.modelPath)
        let config = MLModelConfiguration()
        config.computeUnits = processingUnitsMap()[processingUnit]

        log("\nProcessing Unit Selected: \(processingUnitDescriptions()[processingUnit])\n")
        
        // Print the current directory path
        let currentPath = FileManager.default.currentDirectoryPath
        log("Current directory path: \(currentPath) \n")
        
        let additionalPath = currentPath + "/Library/Caches/com.fguzman82.CoreMLProfiler/com.apple.e5rt.e5bundlecache"
        log("Additional path: \(additionalPath) \n")
        
        var compiledModelURL = packageURL
//        compileTimes = Array(repeating: 0.0, count: 10)
        DispatchQueue.main.async {
            self.compileTimes = Array(repeating: 0.0, count: 10)
        }
        
        if modelPath.hasSuffix(".mlpackage") {
            let compileResult = try await compileModel(at: packageURL)
            compiledModelURL = compileResult.0
            let compileTimes = compileResult.1
            let medianCompileTime = compileTimes[compileTimes.count / 2]

            DispatchQueue.main.async {
                self.compileTimes = compileTimes
                self.compileTime = medianCompileTime // Default to median
            }

            log("Time taken to compile model (median): \(medianCompileTime) ms\n")
        }
        
        let (model, loadTimes) = try await loadModel(at: compiledModelURL, configuration: config)
        DispatchQueue.main.async {
            self.loadTimes = loadTimes
            self.loadTime = loadTimes[loadTimes.count / 2] // Default to median
        }
        log("Time taken to load model (median): \(loadTimes[loadTimes.count / 2]) ms\n")

        var medianPredictTime: Double = 0.0

        if fullProfile {
            // Create dummy input and perform prediction
            if let dummyInput = createDummyInput(for: model) {
                let predictTimes = try makePrediction(with: dummyInput, model: model)
                medianPredictTime = predictTimes[predictTimes.count / 2]
                log("Time taken to make prediction (median): \(medianPredictTime) ms\n")
                DispatchQueue.main.async {
                    self.predictTimes = predictTimes
                }
            }
        }

        if let plan = try await getComputePlan(of: compiledModelURL, configuration: config) {
            let modelStructure = processModelStructure(plan.modelStructure, plan: plan, medianPredictTime: medianPredictTime, fullProfile: fullProfile)
            let jsonData = try JSONSerialization.data(withJSONObject: modelStructure, options: .prettyPrinted)
            
            try saveJSONToFile(jsonData: jsonData, fileName: "compute_plan.json")
            var (selectedDataFrame, counts) = try processAndSaveSelectedColumns(from: jsonData, fullProfile: fullProfile)
            
            // Find and log the latest analytics.mil file
            if let latestAnalyticsFile = findLatestAnalyticsFile(in: additionalPath) {
                log("Latest analytics.mil file: \(latestAnalyticsFile.path)\n")
                
                // Decode the analytics.mil file
                let operations = decodeAnalyticsFile(at: latestAnalyticsFile)
//                log("Decoded operations: \(operations)\n")
                
                // Convert operations to DataFrame
                let analyticsDataFrame = try convertOperationsToDataFrame(operations: operations)
                print("Analytics DataFrame: \(analyticsDataFrame)\n")
                
                // Copy validation messages to selectedDataFrame
                copyValidationMessages(from: analyticsDataFrame, to: &selectedDataFrame)
                print("Consolided DataFrame: \(selectedDataFrame.selecting(columnNames: "validationMessages"))\n")
            }
            
            return (selectedDataFrame, counts)
        } else {
            log("Failed to load the compute plan.\n")
            return (DataFrame(), OperationCounts(totalOp: 0, totalCPU: 0, totalGPU: 0, totalANE: 0))
        }
    }

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
        log("Model compiled successfully at \(finalCompiledModelURL)\n")
        log("Compilation times:\n\(compileTimes) ms\n")

        return (finalCompiledModelURL, compileTimes)
    }

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
        log("Load times:\n \(loadTimes) ms\n")

        return (finalModel, loadTimes)
    }
    
    private func createDummyInput(for model: MLModel) -> MLFeatureProvider? {
        let modelDescription = model.modelDescription

        var inputDictionary = [String: MLFeatureValue]()

        for (name, description) in modelDescription.inputDescriptionsByName {
            log("\n\n [Prediction] Creating dummy input for \(description) ... \n")
            switch description.type {
            case .multiArray:
                if let multiArrayValue = createDummyMultiArray(from: description.multiArrayConstraint) {
                    inputDictionary[name] = multiArrayValue
                } else {
                    log("Failed to create dummy multi-array for \(name)\n")
                    return nil
                }
            case .int64:
                inputDictionary[name] = MLFeatureValue(int64: Int64.random(in: 0..<10))
            case .double:
                inputDictionary[name] = MLFeatureValue(double: Double.random(in: 0..<1))
            case .string:
                inputDictionary[name] = MLFeatureValue(string: "dummy_string")
            case .dictionary:
                if let dictionaryValue = createDummyDictionary(from: description.dictionaryConstraint) {
                    inputDictionary[name] = dictionaryValue
                } else {
                    log("Failed to create dummy dictionary for \(name)\n")
                    return nil
                }
            case .image:
                if let pixelBuffer = createDummyPixelBuffer(from: description.imageConstraint) {
                    inputDictionary[name] = MLFeatureValue(pixelBuffer: pixelBuffer)
                } else {
                    log("Failed to create dummy pixel buffer for \(name)\n")
                    return nil
                }
            case .sequence:
                if let sequenceValue = createDummySequence(from: description.sequenceConstraint) {
                    inputDictionary[name] = sequenceValue
                } else {
                    log("Failed to create dummy sequence for \(name)\n")
                    return nil
                }
            default:
                log("Unsupported input type for \(name)\n")
                return nil
            }
        }

        return try? MLDictionaryFeatureProvider(dictionary: inputDictionary)
    }

    private func makePrediction(with input: MLFeatureProvider, model: MLModel) throws -> [Double] {
        var predictTimes: [Double] = []

        for _ in 1...10 {
            let predictStartTime = DispatchTime.now()
            let _ = try model.prediction(from: input)
            let predictEndTime = DispatchTime.now()
            let predictNanoTime = predictEndTime.uptimeNanoseconds - predictStartTime.uptimeNanoseconds
            let predictTimeInterval = Double(predictNanoTime) / 1_000_000
            predictTimes.append(predictTimeInterval)
        }

        predictTimes.sort()
        
        log("Prediction times: \(predictTimes) ms\n")

        return predictTimes
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
        operationStructure["operator_id"] = operation.outputs.first?.name ?? "Unknown"
        operationStructure["operatorName"] = operation.operatorName
        operationStructure["inputs"] = operation.inputs.map { ["name": $0.key, "bindings": $0.value.bindings.map { getName(for: $0) } ] }
        operationStructure["outputs"] = operation.outputs.map { ["name": $0.name, "type": String(describing: $0.type)] }
        operationStructure["blocks"] = operation.blocks.map { getBlockStructure(block: $0, plan: plan, operationCount: &operationCount, medianPredictTime: medianPredictTime, fullProfile: fullProfile) }
        operationStructure["cost"] = cost
        operationStructure["preferred_device"] = mapDeviceUsage(deviceUsage?.preferred)
        operationStructure["supported_devices"] = deviceUsage?.supported.map { mapDeviceUsage($0) }.joined(separator: ", ")
        if fullProfile {
            operationStructure["start_time"] = startTime
            operationStructure["end_time"] = endTime
            operationStructure["op_time"] = endTime - startTime
        }
                
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

    struct OperationCounts {
        var totalOp: Int
        var totalCPU: Int
        var totalGPU: Int
        var totalANE: Int
    }

    private func processAndSaveSelectedColumns(from jsonData: Data, fullProfile: Bool) throws -> (DataFrame, OperationCounts) {
        let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
        guard let jsonDict = json as? [String: Any],
              let main = jsonDict["main"] as? [String: Any],
              let block = main["block"] as? [String: Any],
              let operations = block["operations"] as? [[String: Any]] else {
            throw NSError(domain: "CoreMLProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure."])
        }

        let operationsData = try JSONSerialization.data(withJSONObject: operations, options: [])
        let dataFrame = try DataFrame(jsonData: operationsData)

        // Select the columns
        let selectedDataFrame: DataFrame
        
        if fullProfile {
            selectedDataFrame = dataFrame.selecting(columnNames: "op_number", "operator_id", "operatorName", "cost", "preferred_device", "supported_devices", "start_time", "end_time", "op_time")
        } else {
            selectedDataFrame = dataFrame.selecting(columnNames: "op_number", "operator_id", "operatorName", "cost", "preferred_device", "supported_devices")
        }

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
        
        let counts = OperationCounts(totalOp: totalOp, totalCPU: totalCPU, totalGPU: totalGPU, totalANE: totalANE)

        return (selectedDataFrame, counts)
    }

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.consoleOutput += message + "\n"
        }
    }
    
    private func createDummyMultiArray(from constraint: MLMultiArrayConstraint?) -> MLFeatureValue? {
        guard let constraint = constraint else { return nil }
        let shape = constraint.shape
        let dataType = constraint.dataType
        let multiArray: MLMultiArray
        do {
            multiArray = try MLMultiArray(shape: shape as [NSNumber], dataType: dataType)
            for i in 0..<multiArray.count {
                switch dataType {
                case .double:
                    multiArray[i] = NSNumber(value: Double.random(in: 0..<1))
                case .float32:
                    multiArray[i] = NSNumber(value: Float.random(in: 0..<1))
                case .int32:
                    multiArray[i] = NSNumber(value: Int32.random(in: 0..<10))
                default:
                    break
                }
            }
            return MLFeatureValue(multiArray: multiArray)
        } catch {
            log("Failed to create MLMultiArray: \(error)\n")
            return nil
        }
    }

    private func createDummyPixelBuffer(from constraint: MLImageConstraint?) -> CVPixelBuffer? {
        guard let constraint = constraint else { return nil }
        let width = constraint.pixelsWide
        let height = constraint.pixelsHigh
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess else {
            log("Failed to create pixel buffer\n")
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer!, [])
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        let colorValue: UInt32 = 0xFFFF0000 // ARGB value for red color
        let pixelBufferBaseAddress = pixelData?.assumingMemoryBound(to: UInt32.self)
        for y in 0..<height {
            for x in 0..<width {
                pixelBufferBaseAddress?[y * width + x] = colorValue
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, [])
        return pixelBuffer
    }

    private func createDummyDictionary(from constraint: MLDictionaryConstraint?) -> MLFeatureValue? {
        guard let constraint = constraint else { return nil }

        switch constraint.keyType {
        case .string:
            let dict: [String: NSNumber] = ["key": NSNumber(value: Double.random(in: 0..<1))]
            return try? MLFeatureValue(dictionary: dict)
        case .int64:
            let dict: [NSNumber: NSNumber] = [NSNumber(value: Int64.random(in: 0..<10)): NSNumber(value: Double.random(in: 0..<1))]
            return try? MLFeatureValue(dictionary: dict)
        default:
            log("Unsupported dictionary key type\n")
            return nil
        }
    }

    private func createDummySequence(from constraint: MLSequenceConstraint?) -> MLFeatureValue? {
        guard let constraint = constraint else { return nil }
        let countRange = constraint.countRange
        let length = Int.random(in: countRange.lowerBound..<countRange.upperBound)

        switch constraint.valueDescription.type {
        case .int64:
            let sequence = (0..<length).map { _ in NSNumber(value: Int64.random(in: 0..<10)) }
            return MLFeatureValue(sequence: MLSequence(int64s: sequence))
        case .double:
            let sequence = (0..<length).map { _ in NSNumber(value: Double.random(in: 0..<1)) }
            return MLFeatureValue(sequence: MLSequence(int64s: sequence))
        case .string:
            let sequence = (0..<length).map { _ in "dummy_string" }
            return MLFeatureValue(sequence: MLSequence(strings: sequence))
        default:
            log("Unsupported sequence type\n")
            return nil
        }
    }
    
    private func findLatestAnalyticsFile(in directory: String) -> URL? {
        let fileManager = FileManager.default
        let expandedPath = NSString(string: directory).expandingTildeInPath
        
        log("Expanded search path: \(expandedPath)\n")

        guard let enumerator = fileManager.enumerator(atPath: expandedPath) else {
            log("Failed to create file enumerator.\n")
            return nil
        }
        
        var analyticsFiles: [String] = []
        
        for case let file as String in enumerator {
            if file.hasSuffix("analytics.mil") {
                let fullPath = expandedPath + "/" + file
                analyticsFiles.append(fullPath)
//                log("Found file: \(fullPath)\n")
            }
        }
        
        if analyticsFiles.isEmpty {
            log("No analytics.mil files found.\n")
            return nil
        }
        
        let latestFile = analyticsFiles.max(by: {
            (file1, file2) -> Bool in
            let file1Attributes = try? fileManager.attributesOfItem(atPath: file1)
            let file2Attributes = try? fileManager.attributesOfItem(atPath: file2)
            
            if let file1Date = file1Attributes?[.modificationDate] as? Date,
               let file2Date = file2Attributes?[.modificationDate] as? Date {
                return file1Date < file2Date
            }
            return false
        })
        
        if let latestFile = latestFile {
            return URL(fileURLWithPath: latestFile)
        } else {
            log("Failed to find the latest analytics.mil file.\n")
            return nil
        }
    }
    
    private func decodeAnalyticsFile(at url: URL) -> [OperationDetails] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            log("Failed to read the content of \(url.path)")
            return []
        }
        
        var operations = [OperationDetails]()
        
        let tensorOperations = content.split(separator: ";").map { String($0) }.filter { $0.contains("tensor") }
        
        for tensorOperation in tensorOperations {
            let operationDetails = extractSingle(tensorOperation: tensorOperation)
            operations.append(operationDetails)
        }
        
        return operations
    }
    
    private func extractSingle(tensorOperation: String) -> OperationDetails {
        let operationPattern = #"= (\w+)\("#
        let operationRegex = try? NSRegularExpression(pattern: operationPattern, options: [])
        var operation = "Not found"
        if let match = operationRegex?.firstMatch(in: tensorOperation, options: [], range: NSRange(location: 0, length: tensorOperation.utf16.count)) {
            if let range = Range(match.range(at: 1), in: tensorOperation) {
                operation = String(tensorOperation[range])
            }
        }
        
        let runtimePattern = #"EstimatedRuntime\s*=\s*dict<string,\s*fp64>\(\{\{(.*?)\}\}\)"#
        let runtimeRegex = try? NSRegularExpression(pattern: runtimePattern, options: [])
        var runtimes = [String: Double]()
        if let match = runtimeRegex?.firstMatch(in: tensorOperation, options: [], range: NSRange(location: 0, length: tensorOperation.utf16.count)) {
            if let range = Range(match.range(at: 1), in: tensorOperation) {
                let runtimesStr = String(tensorOperation[range])
                let runtimePairPattern = #""(\w+)",\s*([\d\.e\+\-]+)"#
                let runtimePairRegex = try? NSRegularExpression(pattern: runtimePairPattern, options: [])
                let matches = runtimePairRegex?.matches(in: runtimesStr, options: [], range: NSRange(location: 0, length: runtimesStr.utf16.count)) ?? []
                for match in matches {
                    if let backendRange = Range(match.range(at: 1), in: runtimesStr),
                       let runtimeRange = Range(match.range(at: 2), in: runtimesStr) {
                        let backend = String(runtimesStr[backendRange])
                        let runtime = Double(runtimesStr[runtimeRange]) ?? 0.0
                        runtimes[backend] = runtime
                    }
                }
            }
        }
        
        let backendPattern = #"SelectedBackend\s*=\s*string\("(.*?)"\)"#
        let backendRegex = try? NSRegularExpression(pattern: backendPattern, options: [])
        var selectedBackend = "Not found"
        if let match = backendRegex?.firstMatch(in: tensorOperation, options: [], range: NSRange(location: 0, length: tensorOperation.utf16.count)) {
            if let range = Range(match.range(at: 1), in: tensorOperation) {
                selectedBackend = String(tensorOperation[range])
            }
        }
        
        let namePattern = #"name\s*=\s*string\("(.*?)"\)"#
        let nameRegex = try? NSRegularExpression(pattern: namePattern, options: [])
        var name: String? = nil
        if let match = nameRegex?.firstMatch(in: tensorOperation, options: [], range: NSRange(location: 0, length: tensorOperation.utf16.count)) {
            if let range = Range(match.range(at: 1), in: tensorOperation) {
                name = String(tensorOperation[range])
            }
        }
        
        let validationMessagePattern = #"ValidationMessage\s*=\s*dict<string,\s*string>\(\{\{(.*?)\}\}\)"#
        let validationMessageRegex = try? NSRegularExpression(pattern: validationMessagePattern, options: [])
        var validationMessages = [String: String]()
        if let match = validationMessageRegex?.firstMatch(in: tensorOperation, options: [], range: NSRange(location: 0, length: tensorOperation.utf16.count)) {
            if let range = Range(match.range(at: 1), in: tensorOperation) {
                let validationMessagesStr = String(tensorOperation[range])
                let validationMessagePairPattern = #""(\w+)",\s*"(.*?)""#
                let validationMessagePairRegex = try? NSRegularExpression(pattern: validationMessagePairPattern, options: [])
                let matches = validationMessagePairRegex?.matches(in: validationMessagesStr, options: [], range: NSRange(location: 0, length: validationMessagesStr.utf16.count)) ?? []
                for match in matches {
                    if let backendRange = Range(match.range(at: 1), in: validationMessagesStr),
                       let messageRange = Range(match.range(at: 2), in: validationMessagesStr) {
                        let backend = String(validationMessagesStr[backendRange])
                        let message = String(validationMessagesStr[messageRange]).replacingOccurrences(of: "\\\"", with: "\"") + "\n"
                        validationMessages[backend] = message
                    }
                }
            }
        }
        
        return OperationDetails(
            operation: operation,
            runtimes: runtimes,
            selectedBackend: selectedBackend,
            name: name,
            validationMessages: validationMessages
        )
    }
    
    private func convertOperationsToDataFrame(operations: [OperationDetails]) throws -> DataFrame {
  
        let operationsData = try JSONSerialization.data(withJSONObject: operations.map { $0.dictionaryRepresentation }, options: [])
        var dataFrame = try DataFrame(jsonData: operationsData)
        dataFrame.removeRow(at: 0)
        
        var count = 0
        while count < 5, let operationValue = dataFrame["operation", String.self][0], operationValue.contains("string") {
            dataFrame.removeRow(at: 0)
            count += 1
        }
        
        return dataFrame.selecting(columnNames: "operation", "name", "validationMessages")
    }
    
    private func copyValidationMessages(from analyticsDataFrame: DataFrame, to selectedDataFrame: inout DataFrame) {
        // Crear la columna "validationMessages" en selectedDataFrame si no existe
        selectedDataFrame.append(column: Column<String>(name: "validationMessages", capacity: selectedDataFrame.rows.count))

        for index in 0..<selectedDataFrame.rows.count {
                let aneMessage = (analyticsDataFrame["validationMessages", Dictionary<String, Optional<Any>>.self][index]?["ane"] as? String) ?? ""
                selectedDataFrame["validationMessages", String.self][index] = aneMessage
            }
    }



}

//        if let validationMessagesColumn = dataFrame["validationMessages", Dictionary<String, Optional<Any>>.self][0],
//               let aneMessage = validationMessagesColumn["ane"] ?? nil {
//                print("Validation message for 'ane' at row 0: \(aneMessage ?? "")")
//            } else {
//                print("No validation messages found for 'ane' at row 0.")
//            }
