//
//  LeaderboardViewModel.swift
//  app
//
//  Created by Stuart Kuentzel on 2025/05/21.
//
import Foundation
import SwiftUI
import URnetworkSdk

extension LeaderboardView {

    @MainActor
    class ViewModel: ObservableObject {

        private let urApiService: UrApiServiceProtocol

        private var isLoadingRanking = true
        private var isApplyingRankingState = false
        private var lastSavedNetworkRankingPublic = false

        @Published var networkRankingPublic: Bool = false {
            didSet {
                guard !isLoadingRanking, !isApplyingRankingState else { return }
                guard oldValue != networkRankingPublic else { return }
                Task {
                    await setNetworkRankingPublic(networkRankingPublic, previousValue: oldValue)
                }
            }
        }

        @Published private(set) var leaderboardEarners: [LeaderboardEntry] = []

        @Published private(set) var networkRank: Int = 0
        @Published private(set) var netProvidedFormatted: String = ""

        @Published private(set) var isLoading: Bool = false
        @Published private(set) var isInitializing: Bool = true

        @Published private(set) var isSettingRankingVisibility: Bool = false

        init(apiService: UrApiServiceProtocol) {
            self.urApiService = apiService

            Task {
                await fetchLeaderboardData()
            }

        }

        func fetchLeaderboardData() async {

            if isLoading {
                return
            }

            self.isLoading = true

            async let rankingResult = getRanking()
            async let leaderboardResult = getLeaderboard()

            // Wait for both to complete
            let (ranking, leaderboard) = await (rankingResult, leaderboardResult)

            switch (ranking, leaderboard) {
            case (.success, .success):
                print("Both API calls completed successfully")
            case (.failure(let rankingError), _):
                print("Ranking error: \(rankingError)")
            case (_, .failure(let leaderboardError)):
                print("Leaderboard error: \(leaderboardError)")
            }

            self.isLoading = false
            if self.isInitializing {
                self.isInitializing = false
            }

        }

        private func getRanking() async -> Result<Void, Error> {

            do {
                defer {
                    self.isLoadingRanking = false
                }
                
                let result = try await urApiService.getLeaderboardRanking()

                if let networkRanking = result.networkRanking {
                    self.lastSavedNetworkRankingPublic = networkRanking.leaderboardPublic
                    self.applyNetworkRankingPublicState(networkRanking.leaderboardPublic)
                    self.networkRank = networkRanking.leaderboardRank
                    self.netProvidedFormatted = formatMiB(mib: networkRanking.netMiBCount)
                }

                return .success(())

            } catch (let error) {
                print("get network ranking error \(error)")

                return .failure(error)
            }

        }

        private func getLeaderboard() async -> Result<Void, Error> {

            do {
                
                let earners = try await urApiService.getLeaderboard()

                self.leaderboardEarners = earners

                return .success(())

            } catch (let error) {
                print("get leaderboard error \(error)")

                return .failure(error)
            }

        }

        func setNetworkRankingPublic(_ isPublic: Bool) async -> Result<Void, Error> {
            await setNetworkRankingPublic(isPublic, previousValue: nil)
        }

        private func setNetworkRankingPublic(_ isPublic: Bool, previousValue: Bool?) async -> Result<Void, Error> {

            if self.isSettingRankingVisibility {
                applyNetworkRankingPublicState(previousValue ?? lastSavedNetworkRankingPublic)
                return .failure(SetRankingVisibilityError.isLoading)
            }

            self.isSettingRankingVisibility = true

            do {
                
                try await urApiService.setNetworkRankingPublic(isPublic)
                lastSavedNetworkRankingPublic = isPublic
                
                let _ = await self.getLeaderboard()

                self.isSettingRankingVisibility = false

                return .success(())

            } catch (let error) {
                print("set ranking visibility error \(error)")

                applyNetworkRankingPublicState(previousValue ?? lastSavedNetworkRankingPublic)
                self.isSettingRankingVisibility = false

                return .failure(error)
            }

        }

        private func applyNetworkRankingPublicState(_ value: Bool) {
            isApplyingRankingState = true
            networkRankingPublic = value
            isApplyingRankingState = false
        }

    }

}
