import SwiftUI
import XCTest
@testable import DSHKit

final class MotionPolicyTests: XCTestCase {
    func testPassesAnimationThroughNormally() {
        let animation = Animation.easeInOut(duration: 0.2)
        XCTAssertNotNil(MotionPolicy.animation(animation, reduceMotion: false))
    }

    func testDropsAnimationWhenReduceMotion() {
        XCTAssertNil(MotionPolicy.animation(.easeInOut(duration: 0.2), reduceMotion: true))
    }

    func testNilInputStaysNil() {
        XCTAssertNil(MotionPolicy.animation(nil, reduceMotion: false))
    }
}
