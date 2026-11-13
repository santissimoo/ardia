import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class KeyboardTracker {
  private(set) var animation: Animation? = KeyboardTracker.animation(duration: 0.25, curve: KeyboardTracker.systemCurve)
  private(set) var announcedHeight: CGFloat?
  @ObservationIgnored private var observers: [NSObjectProtocol] = []

  static let systemCurve = 7

  func start() {
    guard observers.isEmpty else { return }
    for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
      let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
        let info = notification.userInfo ?? [:]
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? Self.systemCurve
        let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let isHiding = notification.name == UIResponder.keyboardWillHideNotification
        MainActor.assumeIsolated {
          self?.animation = Self.animation(duration: duration, curve: curve)
          guard let endFrame, let screenHeight = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.screen.bounds.height }).first else { return }
          self?.announcedHeight = isHiding ? 0 : max(screenHeight - endFrame.minY, 0)
        }
      }
      observers.append(observer)
    }
  }

  static func animation(duration: Double, curve: Int) -> Animation? {
    guard duration > 0 else { return nil }
    if curve == systemCurve {
      return Animation(KeyboardCurve(rate: KeyboardCurve.rateTimesDuration / duration))
    }
    return .easeInOut(duration: duration)
  }
}
