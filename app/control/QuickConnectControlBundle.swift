//
//  QuickConnectControlBundle.swift
//  URnetwork Quick Connect control
//
//  Entry point for the control (widget) extension.
//

import SwiftUI
import WidgetKit

@main
struct QuickConnectControlBundle: WidgetBundle {

    @WidgetBundleBuilder
    var body: some Widget {
        if #available(iOS 18.0, *) {
            QuickConnectControl()
        }
    }
}
