import Dependencies
import Foundation
import Observation
import OSLog
import Sharing

@MainActor
@Observable
final class ScheduleManager {
	@ObservationIgnored
	@Dependency(\.continuousClock) private var continuousClock
	@ObservationIgnored
	@Dependency(\.date) private var date
	@ObservationIgnored
	@Dependency(\.calendar) private var calendar

	@ObservationIgnored
	@Shared(.scheduleConfig) private var schedule

	let logger = Logger(category: "Schedule")

	var isActive: Bool = false

	init() {
		trackActive()
	}

	deinit {
		scheduleTask?.cancel()
	}

	@ObservationIgnored
	private var scheduleTask: Task<Void, Error>?

	func trackActive() {
		scheduleTask?.cancel()

		let schedule = withObservationTracking {
			self.schedule
		} onChanged: { [weak self] in
			self?.trackActive()
		}

		let firstDelay = self.updateActive(with: schedule)

		scheduleTask = Task { [weak self, continuousClock] in
			try await continuousClock.sleep(for: firstDelay)

			while !Task.isCancelled {
				let delay = self?.updateActive(with: schedule) ?? .seconds(60)

				try await continuousClock.sleep(for: delay)
			}
		}
	}

	/// Updates `isActive` and returns the delay until the next change.
	private func updateActive(with schedule: ScheduleConfig) -> Duration {
		let now = date.now

		guard
			let start = schedule.startingDateComponents
				.compactMap({
					calendar.nextDate(
						after: now - schedule.duration.seconds,
						matching: $0,
						matchingPolicy: .nextTime
					)
				})
				.min()
		else {
			logger.error("no next")
			if isActive {
				self.isActive = false
			}
			return .seconds(60)
		}
		let next = DateInterval(start: start, duration: schedule.duration.seconds)

		logger.info("next scheduled after \(now) is \(next)")

		let startDelay = now.timeIntervalUntil(next.start)
		logger.info("delay to active: \(startDelay)")
		if startDelay > 0 {
			if isActive {
				self.isActive = false
			}

			return .seconds(startDelay)
		} else {
			if !isActive {
				self.isActive = true
			}

			let delay = now.timeIntervalUntil(next.end)
			logger.info("delay to inactive: \(delay)")
			return .seconds(delay)
		}
	}
}
