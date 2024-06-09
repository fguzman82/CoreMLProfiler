//
//  ActivityIndicator.swift
//  CoreMLProfiler
//
//  Created by Fabio Guzman on 8/06/24.
//

import SwiftUI

struct ActivityIndicator: View {
    @State private var isAnimating: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                ForEach(0..<12) { index in
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: size / 10, height: size / 3)
                        .offset(y: -size / 2.5)
                        .rotationEffect(.degrees(Double(index) / 12 * 360))
                        .opacity(isAnimating ? Double(index) / 12 : 1)
                }
            }
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    self.isAnimating = true
                }
            }
            .onDisappear { self.isAnimating = false }
        }
    }
}
