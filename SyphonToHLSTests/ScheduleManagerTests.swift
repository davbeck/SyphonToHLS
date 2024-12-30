import Dependencies
import Foundation
import Testing

@testable import SyphonToHLS

struct MutableDateGenerator {
	let _now = LockIsolated(Date(timeIntervalSince1970: 1_234_567_890))

	var now: Date {
		get { _now.value }
		nonmutating set { _now.withValue { $0 = newValue } }
	}

	var dateGenerator: DateGenerator {
		DateGenerator { now }
	}

	init() {}
}

@MainActor
struct ScheduleManagerTests {
	var clock = TestClock()
	var configManager = ConfigManager(url: nil)
	let date = MutableDateGenerator()
	var calendar = Calendar(identifier: .gregorian)

	init() throws {
		calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

		configManager.config.schedule = .init(
			weekdays: [1],
			startHour: 10,
			startMinute: 0,
			duration: .hours(2)
		)
	}

	private func createSUT() -> ScheduleManager {
		withDependencies {
			$0.continuousClock = clock
			$0.configManager = configManager
			$0.calendar = calendar
			$0.date = date.dateGenerator
		} operation: {
			ScheduleManager()
		}
	}

	@Test func isNotActiveOnLaunch() async throws {
		let sut = createSUT()

		let isActive = sut.isActive
		#expect(!isActive)
	}

	@Test func isActiveOnLaunch() async throws {
		date.now = Date(timeIntervalSince1970: 1_234_721_400)
		let sut = createSUT()

		let isActive = sut.isActive
		#expect(isActive)
	}

	@Test func activatesAfterDelay() async throws {
		await withMainSerialExecutor {
			let sut = createSUT()

			date.now = Date(timeIntervalSince1970: 1_234_720_800)
			await clock.advance(by: .seconds(152_910))

			let isActive = sut.isActive
			#expect(isActive)
		}
	}

	@Test func deactivatesAfterDelay() async throws {
		await withMainSerialExecutor {
			date.now = Date(timeIntervalSince1970: 1_234_721_400)
			let sut = createSUT()
			
			date.now = Date(timeIntervalSince1970: 1_234_728_000)
			await clock.advance(by: .seconds(152_910))
			
			let isActive = sut.isActive
			#expect(!isActive)
		}
	}
}
