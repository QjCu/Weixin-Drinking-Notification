#if canImport(UIKit) && canImport(SwiftUI) && !canImport(SipTimeCore)
import XCTest
import UIKit
import SwiftUI
@testable import SipTime

/// Measures the production grid after SwiftUI lays it out, including long labels and conflicts.
@MainActor
final class CourseTimetableLayoutTests: XCTestCase {
    func testAllSevenDaysFitPortraitAndEveryCourseBlockHasEqualBounds() async throws {
        for width: CGFloat in [320, 375, 430] {
            var frames: [CourseGridPosition: CGRect] = [:]
            let content = CourseTimetableGrid(courses: fixtureCourses(), week: 3,
                termStart: LocalDay(Date(timeIntervalSince1970: 1_792_368_000)),
                onCellFrames: { frames = $0 })
                .dynamicTypeSize(.large)
                .environment(\.colorScheme, .light)
                .background(Color.white)
            let host = UIHostingController(rootView: content)
            let window = mount(host, width: width, height: 1_200)
            defer {
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
                window.isHidden = true
            }
            let deadline = Date().addingTimeInterval(10)
            while frames.count != 84, Date() < deadline {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(frames.count, 84, "Missing rendered cells at \(width)pt")
            let reference = try XCTUnwrap(frames[CourseGridPosition(weekday: 1, period: 1)])
            XCTAssertGreaterThan(reference.width, 0)
            XCTAssertGreaterThan(reference.height, 0)
            for period in 1...12 {
                var previous: CGRect?
                for day in 1...7 {
                    let frame = try XCTUnwrap(frames[CourseGridPosition(weekday: day, period: period)])
                    XCTAssertEqual(frame.width, reference.width, accuracy: 0.5,
                                   "Unequal column at \(width)pt, day \(day), period \(period)")
                    XCTAssertEqual(frame.height, reference.height, accuracy: 0.5,
                                   "Long names/conflicts changed block height at \(width)pt")
                    XCTAssertGreaterThanOrEqual(frame.minX, -0.5)
                    XCTAssertLessThanOrEqual(frame.maxX, width + 0.5,
                                             "A weekday requires horizontal scrolling at \(width)pt")
                    if let previous {
                        XCTAssertGreaterThanOrEqual(frame.minX, previous.maxX - 0.5)
                        XCTAssertEqual(frame.minY, previous.minY, accuracy: 0.5)
                    }
                    previous = frame
                }
            }
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
            let image = renderer.image { context in
                if !host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) {
                    host.view.layer.render(in: context.cgContext)
                }
            }
            let screenshot = XCTAttachment(image: image)
            screenshot.name = "course-grid-\(Int(width))pt-long-names-and-conflict"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    private func fixtureCourses() -> [Course] {
        var courses = (1...7).map { day in
            var course = Course(title: "原始全称：跨学科数学与自然科学中的复杂系统专题讨论课程 \(day)",
                teacher: "姓名很长的教师与助教",
                meetings: [CourseMeeting(weekday: day, startPeriod: 1, endPeriod: 12,
                                         location: "很长的教学楼与教室名称102")])
            course.remark = "很长的个人课程显示名称与备注 \(day)"
            return course
        }
        courses.append(Course(title: "同一时段的另一门很长名称课程",
            meetings: [CourseMeeting(weekday: 4, startPeriod: 4, endPeriod: 4, kind: .odd,
                                     location: "二教407")]))
        return courses
    }

    private func mount(_ host: UIViewController, width: CGFloat, height: CGFloat) -> UIWindow {
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height)) }
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.loadViewIfNeeded()
        parent.addChild(host)
        host.view.autoresizingMask = []
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return window
    }
}
#endif
