import SwiftUI
import HidLensCore

@MainActor
final class MeasurementViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var statistics: MeasurementStatistics?
    @Published var errorMessage: String?
    @Published var progress: Double = 0.0
    @Published var showResults = false
    @Published var finalStats: MeasurementStatistics?

    var duration: TimeInterval = 5.0
    private var measureService: MeasurementService?
    private var progressTimer: Timer?
    private var startTime: Date?

    func startMeasurement(vendorID: Int, productID: Int) {
        isRunning = true
        statistics = nil
        errorMessage = nil
        progress = 0.0
        finalStats = nil
        showResults = false

        let service = MeasurementService()
        measureService = service
        startTime = Date()

        // Timer for smooth progress updates
        let dur = duration
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.progress = min(elapsed / dur, 1.0)
            }
        }

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let stats = try service.measure(
                    vendorID: vendorID,
                    productID: productID,
                    duration: dur,
                    onUpdate: { intermediateStats in
                        Task { @MainActor [weak self] in
                            self?.statistics = intermediateStats
                        }
                    }
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                    self.progress = 1.0
                    self.statistics = stats
                    self.finalStats = stats
                    self.isRunning = false
                    self.showResults = true
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.progressTimer?.invalidate()
                    self.progressTimer = nil
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                }
            }
        }
    }

    func stopMeasurement() {
        progressTimer?.invalidate()
        progressTimer = nil

        if let service = measureService {
            let stats = service.stop()
            statistics = stats
            finalStats = stats
            showResults = true
        }
        isRunning = false
        measureService = nil
    }
}
