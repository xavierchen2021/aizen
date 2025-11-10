//
//  AnimationConstants.swift
//  aizen
//
//  Centralized animation constants for consistent UI transitions
//

import SwiftUI

enum AnimationConstants {
    // MARK: - Duration

    static let easeOutDuration: Double = 0.3
    static let scrollDuration: Double = 0.3

    // MARK: - Spring Parameters

    static let springResponse: Double = 0.3
    static let springDamping: Double = 0.7

    static let smoothSpringResponse: Double = 0.4
    static let smoothSpringDamping: Double = 0.8

    static let quickSpringResponse: Double = 0.2
    static let quickSpringDamping: Double = 0.8

    // MARK: - Convenience Animations

    /// Standard spring animation used throughout the app
    static var standardSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    /// Smoother spring for longer transitions
    static var smoothSpring: Animation {
        .spring(response: smoothSpringResponse, dampingFraction: smoothSpringDamping)
    }

    /// Quick spring for immediate feedback
    static var quickSpring: Animation {
        .spring(response: quickSpringResponse, dampingFraction: quickSpringDamping)
    }

    /// Ease out for scroll animations
    static var easeOut: Animation {
        .easeOut(duration: easeOutDuration)
    }
}
