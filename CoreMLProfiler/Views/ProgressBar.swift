//
//  ProgressBar.swift
//  CoreMLProfiler
//
//  Created by Fabio Guzman on 8/06/24.
//

import SwiftUI

struct ProgressBar: View {
    var value: Double
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .foregroundColor(Color.gray.opacity(0.3))
                Rectangle()
                    .foregroundColor(.red)
                    .frame(width: geometry.size.width * CGFloat(value))
                
                Text(String(format: "%.6f", value))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.leading, 5)
            }
            .cornerRadius(4.0)
        }
    }
}

