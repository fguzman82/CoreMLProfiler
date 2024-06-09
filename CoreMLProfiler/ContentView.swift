//
//  ContentView.swift
//  CoreMLProfiler
//
//  Created by Fabio Guzman on 8/06/24.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let mlpackage = UTType(importedAs: "com.apple.coreml.mlpackage")
    static let json = UTType(importedAs: "public.json")
}


@available(macOS 14.4, *)
struct ContentView: View {
    @State private var fileLoaded: Bool = false
    @State private var fileName: String = ""
    @State private var operatorData: [OperatorData] = []
    @State private var sortOrder: [KeyPathComparator<OperatorData>] = [
        .init(\.op_number, order: .forward),
        .init(\.cost, order: .forward)
    ]
    @State private var processingUnit: String = "all"
    @ObservedObject private var processor = CoreMLProcessor.shared
    @State private var compileTime: String = ""
    @State private var loadTime: String = ""
    @State private var isLoading: Bool = false
    @State private var totalOp: Int = 0
    @State private var totalCPU: Int = 0
    @State private var totalGPU: Int = 0
    @State private var totalANE: Int = 0
    @State private var compileTimeOption: String = "Median"
    @State private var loadTimeOption: String = "Median"
    @State private var compileTimes: [Double] = []
    @State private var loadTimes: [Double] = []
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationSplitView {
            ScrollView(.vertical) {
                VStack(alignment: .leading) {
                    Text("1. Select Processing Units")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    Picker("", selection: $processingUnit) {
                        Text("All").tag("all")
                        Text("CPU only").tag("cpuOnly")
                        Text("CPU and GPU").tag("cpuAndGPU")
                        Text("CPU and Neural Engine").tag("cpuAndNeuralEngine")
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.bottom, 10)
                    
                    Text("2. Select CoreML Package")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    HStack {
                        Button(action: loadFile) {
                            Text("Load")
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if fileLoaded {
                            Text("File loaded successfully: \(fileName)")
                                .foregroundColor(colorScheme == .dark ? .green : .blue )
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No file loaded")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.bottom, 43)
                    
                    HStack {
                        Text("Log messages:")
                            .font(.headline)
                        Spacer()
                        if isLoading {
                            ActivityIndicator()
                                .frame(width: 20, height: 20)
                        }
                    }
                    .padding(.bottom, 5)
                    
                    TextEditor(text: $processor.consoleOutput)
                        .frame(height: 400)
                        .border(Color.gray, width: 1)
                        .padding(.bottom, 10)
                    
                    Button(action: rerun) {
                        Text("Rerun")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 10)
                }
                .padding([.horizontal, .bottom, .top])
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 310, max: 450)
            //.background(colorScheme == .light ? Color(white: 0.9) : Color(NSColor.windowBackgroundColor))
            
        } detail: {
            ScrollView(.vertical) {
                VStack(alignment: .center) {
                    // Llama a la vista ComputeUnitMappingView aquí
                    
                    HStack {
                        ComputeUnitMappingView(totalCPU: totalCPU, totalGPU: totalGPU, totalANE: totalANE)
                            
                       
                        VStack(alignment: .leading)  {
                            Text("Compute Units Selected")
                                .foregroundColor(.secondary)
                                .padding(.bottom, 2)
                            
                            
                            Text(getComputeUnitsSelected())
                                .foregroundColor(.primary)
                                //.padding(.bottom, 10)
                        }
                        .padding(.horizontal)
                    }
                    
                    HStack {
                        VStack() {
                            HStack {
                                Text("Compilation")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 2)
                                
                                Picker("", selection: $compileTimeOption) {
                                    Text("Average").tag("Average")
                                    Text("Median").tag("Median")
                                }
                                .frame(width: 100)
                                .onChange(of: compileTimeOption) {
                                    compileTime = calculateTime(option: compileTimeOption, times: compileTimes)
                                }
                            }
                            Text(compileTime)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 5)
                            
                            
                        }
                        .padding(.trailing, 50)
                        
                        VStack() {
                            HStack {
                                Text("Load")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 2)
                                
                                Picker("", selection: $loadTimeOption) {
                                    Text("Average").tag("Average")
                                    Text("Median").tag("Median")
                                }
                                .frame(width: 100)
                                .onChange(of: loadTimeOption) {
                                    loadTime = calculateTime(option: loadTimeOption, times: loadTimes)
                                }
                            }
                            Text(loadTime)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 5)
                            
                        }
                    }
//                    .padding(.bottom, 10)
                    
                    HStack (alignment: .center){
                        Table(operatorData, sortOrder: $sortOrder) {
                            TableColumn("Op Number", value: \.op_number) { data in
                                Text("\(data.op_number)")
                            }
                            TableColumn("Operator Name") { data in
                                Text(data.operatorName)
                            }
                            TableColumn("Cost", value: \.cost) { data in
                                ProgressBar(value: data.cost)
                                    .frame(height: 20)
                            }
                            .width(min: 100)
                            TableColumn("Preferred Device") { data in
                                Text(data.preferred_device)
                            }
                            TableColumn("Supported Devices") { data in
                                Text(data.supported_devices)
                            }
                        }
                        .onChange(of: sortOrder) {
                            operatorData.sort(using: sortOrder)
                        }
                        .task {
                            operatorData.sort(using: sortOrder)
                        }
                        .padding(3)
                    }
                    .frame(minHeight: 600)
                        
                    Button(action: exportToJson) {
                        Text("Export to JSON file")
                    }
                    .padding(.bottom)
                

                }
                .frame(minWidth: 880) // VStack
                //.background(Color(NSColor.windowBackgroundColor))
                //.background(RoundedRectangle(cornerRadius: 10)
                //.stroke(Color.gray, lineWidth: 2))
                
            }
            //.frame(minHeight: 600, maxHeight: .infinity) //  ScrollView
            
        }
        .padding(3)
        //.toolbar(.hidden)
        .frame(minHeight: 705) // Main window
    }
    
    private func getComputeUnitsSelected() -> String {
        let description = CoreMLProcessor.shared.processingUnitDescriptions()[CoreMLProcessor.shared.processingUnit]
        switch description {
        case "all":
            return "All (CPU, GPU, Neural Engine)"
        case "cpuOnly":
            return "CPU"
        case "cpuAndGPU":
            return "CPU and GPU"
        case "cpuAndNeuralEngine":
            return "CPU and Neural Engine"
        default:
            return description
        }
    }
    
    private func loadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.mlpackage]

        if panel.runModal() == .OK {
            if let url = panel.url {
                fileName = url.lastPathComponent
                CoreMLProcessor.shared.modelPath = url.path
                CoreMLProcessor.shared.processingUnit = mapProcessingUnit()
                fileLoaded = true
                rerun()
            }
        }
    }
    
    private func rerun() {
        CoreMLProcessor.shared.processingUnit = mapProcessingUnit()
        Task {
            do {
                isLoading = true
                let counts = try await CoreMLProcessor.shared.run()
                if let data = try? Data(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("compute_plan_operation_table.json")),
                   let decodedData = try? JSONDecoder().decode([OperatorData].self, from: data) {
                    operatorData = decodedData
                    compileTimes = CoreMLProcessor.shared.compileTimes
                    loadTimes = CoreMLProcessor.shared.loadTimes
                    
                    compileTime = calculateTime(option: compileTimeOption, times: compileTimes)
                    loadTime = calculateTime(option: loadTimeOption, times: loadTimes)
                    
                    totalOp = counts.totalOp
                    totalCPU = counts.totalCPU
                    totalGPU = counts.totalGPU
                    totalANE = counts.totalANE
                }
            } catch {
                processor.consoleOutput += "\n\(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func mapProcessingUnit() -> Int {
        switch processingUnit {
        case "cpuOnly":
            return 1
        case "cpuAndGPU":
            return 2
        case "cpuAndNeuralEngine":
            return 3
        default:
            return 0
        }
    }
    
    private func calculateTime(option: String, times: [Double]) -> String {
        if option == "Average" {
            let averageTime = times.reduce(0, +) / Double(times.count)
            return String(format: "%.3f ms", averageTime)
        } else {
            let medianTime = times[times.count / 2]
            return String(format: "%.3f ms", medianTime)
        }
    }


    private func exportToJson() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "compute_plan_operation_table.json"

        if panel.runModal() == .OK {
            if let url = panel.url {
                let currentPath = FileManager.default.currentDirectoryPath
                let sourceURL = URL(fileURLWithPath: currentPath).appendingPathComponent("compute_plan_operation_table.json")
                try? FileManager.default.copyItem(at: sourceURL, to: url)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
