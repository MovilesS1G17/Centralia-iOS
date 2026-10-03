import Combine
import CoreMotion
import SwiftUI
import UIKit

/// Listens to the accelerometer while a view is on screen and calls the action
/// when the person shakes their device. It supports undoing a video deletion.
@MainActor
final class ShakeMonitor {
    private let motion = CMMotionManager()
    private var detector = ShakeDetector()

    func start(onShake: @escaping () -> Void) {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        detector = ShakeDetector()
        motion.accelerometerUpdateInterval = 1.0 / 50.0
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let acceleration = data.acceleration
            let milliseconds = Int64((data.timestamp * 1000).rounded())
            if self.detector.register(
                x: acceleration.x,
                y: acceleration.y,
                z: acceleration.z,
                atMillis: milliseconds
            ) {
                onShake()
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }
}

extension Notification.Name {
    /// Posted by the simulator's Device > Shake command, which has no accelerometer.
    static let centraliaSimulatorShake = Notification.Name("CentraliaSimulatorShake")
}

#if targetEnvironment(simulator)
extension UIWindow {
    /// Routes the simulator's Device > Shake command to the active undo toast.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .centraliaSimulatorShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
#endif

private struct ShakeModifier: ViewModifier {
    let action: () -> Void
    @State private var monitor = ShakeMonitor()
    @State private var shakes = 0

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor.start {
                    shakes += 1
                    action()
                }
            }
            .onDisappear { monitor.stop() }
            .onReceive(NotificationCenter.default.publisher(for: .centraliaSimulatorShake)) { _ in
                shakes += 1
                action()
            }
            .sensoryFeedback(.impact(weight: .heavy), trigger: shakes)
    }
}

extension View {
    /// Calls `action` when the user shakes the phone while this view is visible.
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeModifier(action: action))
    }
}
