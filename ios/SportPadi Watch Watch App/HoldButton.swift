import Foundation
import SwiftUI
import WatchKit

/// Press and hold to confirm — for the actions that can't be undone on a
/// wrist (kick-off, end of period, full time, exit). A ring fills over the
/// hold; letting go early cancels with a soft tap; completing fires once with
/// a firm one.
struct HoldButton: View {
  let label: String
  var systemImage: String = "flag.fill"
  var tint: Color = .green
  var seconds: Double = 1.5
  var disabled = false
  let action: () -> Void

  @State private var progress: Double = 0
  @State private var holding = false
  @State private var timer: Timer?
  @State private var fired = false

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14).fill(tint.opacity(disabled ? 0.25 : 0.85))
      GeometryReader { geo in
        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.28))
          .frame(width: geo.size.width * progress)
      }
      .allowsHitTesting(false)
      HStack(spacing: 6) {
        Image(systemName: systemImage)
        Text(holding ? "Hold…" : label).lineLimit(1).minimumScaleFactor(0.7)
      }
      .font(.system(size: 15, weight: .bold, design: .rounded))
      .foregroundStyle(.white)
    }
    .frame(height: 44)
    .opacity(disabled ? 0.6 : 1)
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in if !holding && !disabled { begin() } }
        .onEnded { _ in end() }
    )
    .accessibilityLabel(label)
    .accessibilityHint("Press and hold to confirm")
  }

  private func begin() {
    holding = true
    fired = false
    progress = 0
    WKInterfaceDevice.current().play(.click)
    let step = 0.05
    timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { _ in
      progress = min(1, progress + step / seconds)
      if progress >= 1 && !fired {
        fired = true
        timer?.invalidate()
        WKInterfaceDevice.current().play(.success)
        action()
        holding = false
        progress = 0
      }
    }
  }

  private func end() {
    timer?.invalidate()
    timer = nil
    if holding && !fired { WKInterfaceDevice.current().play(.directionDown) }
    holding = false
    progress = 0
  }
}
