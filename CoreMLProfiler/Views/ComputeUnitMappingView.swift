//
//  ComputeUnitMappingView.swift
//  CoreMLProfiler
//
//  Created by Fabio Guzman on 8/06/24.
//

import SwiftUI
import Charts

struct ComputeUnitMappingView: View {
    var totalCPU: Int
    var totalGPU: Int
    var totalANE: Int
    
    private var data: [ComputeUnitData] {
        [
            ComputeUnitData(category: "CPU", units: totalCPU),
            ComputeUnitData(category: "GPU", units: totalGPU),
            ComputeUnitData(category: "Neural Engine", units: totalANE)
        ]
    }
    
    private var totalUnits: Int {
        data.reduce(0) { $0 + $1.units }
    }

    var body: some View {
        VStack {
            HStack {
                Text("Compute Unit Mapping")
                Spacer()
                Text("Total Operations: \(totalUnits)")
                    .foregroundColor(.secondary)
            }
            chart
            customLegend
        }
        .padding(.horizontal)
    }

    private var chart: some View {
        Chart(data, id: \.category) { element in
            Plot {
                BarMark(
                    x: .value("Units", element.units)
                )
                .foregroundStyle(by: .value("Compute Unit", element.category))
            }
            .accessibilityLabel(element.category)
            .accessibilityValue("\(element.units)")
            
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color(.systemFill))
                .cornerRadius(8)
        }
        .accessibilityChartDescriptor(self)
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...totalUnits)
        .chartYScale(range: .plotDimension(endPadding: -8))
        .chartLegend(.hidden)
        .frame(height: 25)
    }

    private var customLegend: some View {
        HStack(spacing: 20) {
            legendItem(color: .blue, text: "CPU: \(totalCPU)")
            legendItem(color: .green, text: "GPU: \(totalGPU)")
            legendItem(color: .orange, text: "Neural Engine: \(totalANE)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 3)
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Data Model

struct ComputeUnitData {
    var category: String
    var units: Int
}

// MARK: - Accessibility

extension ComputeUnitMappingView: AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let min = data.map(\.units).min() ?? 0
        let max = data.map(\.units).max() ?? 0

        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Category",
            categoryOrder: data.map { $0.category }
        )

        let yAxis = AXNumericDataAxisDescriptor(
            title: "Units",
            range: Double(min)...Double(max),
            gridlinePositions: []
        ) { value in "\(Int(value))" }

        let series = AXDataSeriesDescriptor(
            name: "Compute Unit Mapping",
            isContinuous: false,
            dataPoints: data.map {
                .init(x: $0.category, y: Double($0.units))
            }
        )

        return AXChartDescriptor(
            title: "Compute Unit Mapping by category",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Preview

struct ComputeUnitMappingView_Previews: PreviewProvider {
    static var previews: some View {
        ComputeUnitMappingView(totalCPU: 6, totalGPU: 3, totalANE: 1)
    }
}
