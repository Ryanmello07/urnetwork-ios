//
//  UrSnackbarManager.swift
//  URnetwork
//
//  Created by Stuart Kuentzel on 2024/12/07.
//

import Foundation

@MainActor
class UrSnackbarManager: ObservableObject {

    @Published private(set) var message: String = ""
    @Published private(set) var isVisible: Bool = false

    private var hideWorkItem: DispatchWorkItem?

    func showSnackbar(message: String) {
        hideWorkItem?.cancel()

        self.message = message
        self.isVisible = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.isVisible = false
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

}
