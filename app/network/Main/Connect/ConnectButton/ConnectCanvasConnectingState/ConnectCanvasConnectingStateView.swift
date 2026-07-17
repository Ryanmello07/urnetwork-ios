//
//  ConnectButtonConnectingStateView.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/28.
//

import SwiftUI
import URnetworkSdk

struct ConnectCanvasConnectingStateView: View {
    
    var gridPoints: [SdkId: SdkProviderGridPoint]
    var gridWidth: Int32
    // while connecting the grid animates live; once connected it freezes at its
    // last state (kept rendered as the background layer under the connector circles)
    var isConnecting: Bool = true

    @StateObject private var viewModel: ViewModel = ViewModel()
    
    var body: some View {
    
        Image("GlobeConnector")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 256, height: 256)
     
        Canvas { context, size in
            
            for (id, point) in viewModel.animatedPoints {
                
                let centerX = CGFloat(point.x) * viewModel.maxPointSize + viewModel.maxPointSize / 2
                let centerY = CGFloat(point.y) * viewModel.maxPointSize + viewModel.maxPointSize / 2
                
                // keep point centered
                let rect = CGRect(
                    x: centerX - point.currentSize / 2,
                    y: centerY - point.currentSize / 2,
                    width: point.currentSize,
                    height: point.currentSize
                )
                
                context.fill(Path(ellipseIn: rect), with: .color(viewModel.getStateColor(id)))
            }
            
        }
        .frame(width: viewModel.canvasWidth, height: viewModel.canvasWidth)
        .onChange(of: gridPoints) { newPoints in
            // freeze once connected: don't feed new points into the grid
            if isConnecting && gridWidth > 0 {
                viewModel.updateGridPoints(newPoints, gridWidth: gridWidth)
            }
        }
        .onChange(of: gridWidth) { newWidth in
            if isConnecting && newWidth > 0 && !gridPoints.isEmpty {
                viewModel.updateGridPoints(gridPoints, gridWidth: newWidth)
            }
        }
        .onChange(of: isConnecting) { nowConnecting in
            // re-seed + resume the live grid when connecting starts again
            // (reconnect); when it stops, the in-flight animation settles and the
            // 60fps timer invalidates itself, leaving the grid frozen in place
            if nowConnecting {
                viewModel.updateGridPoints(gridPoints, gridWidth: gridWidth)
            }
        }
        .onAppear {
            if isConnecting {
                viewModel.updateGridPoints(gridPoints, gridWidth: gridWidth)
            }
        }
        .onDisappear {
            viewModel.stopAnimations()
        }

    }
}

#Preview {
    ConnectCanvasConnectingStateView(
        gridPoints: [:],
        gridWidth: 16
    )
}
