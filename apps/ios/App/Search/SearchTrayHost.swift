import ArdiaDesign
import SwiftUI

struct SearchTrayHost: View {
  @Environment(AppModel.self) private var app
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .title3) private var fieldScale: CGFloat = 1
  @AppStorage("trayKeyboardHeight") private var rememberedKeyboardHeight = 0.0
  @State private var shown: BrowseSession.SearchRequest?
  @State private var rest = TrayRest.floating
  @State private var presentation = 0
  @State private var isFocused = false
  @State private var isClosing = false
  @State private var isRaised = false
  @State private var keyboard = KeyboardTracker()
  @State private var keyboardHeight: CGFloat = 0
  @State private var keyboardLift: CGFloat = 0
  @State private var holdsLift = false
  @State private var dragOffset: CGFloat = 0
  @State private var isDragging = false
  @State private var trayHeight: CGFloat = 0
  @State private var screenHeight: CGFloat = 0
  @State private var settleTask: Task<Void, Never>?
  @State private var focusTask: Task<Void, Never>?
  @State private var restTask: Task<Void, Never>?
  @State private var removalTask: Task<Void, Never>?

  static let keyboardThreshold: CGFloat = 120

  var body: some View {
    ZStack {
      keyboardProbe
      tray
    }
  }

  private var tray: some View {
    GeometryReader { proxy in
      let safeBottom = proxy.safeAreaInsets.bottom
      let origin = proxy.frame(in: .global).origin
      let lift = max(keyboardLift, safeBottom)
      let maxHeight = maxHeight(in: proxy, lift: lift)
      let grows = !reduceMotion
      let dropToRest = rest == .pageBar ? maxHeight - BrowseLayout.barHeight : maxHeight
      let travel = max(lift - safeBottom + dropToRest, 1)
      let dragShare = min(max(dragOffset / travel, 0), 1)
      let morph: CGFloat = grows ? (isRaised ? 1 - dragShare : 0) : 1
      let raisedOffset = min(safeBottom - lift + dragOffset, safeBottom + dropToRest)
      let trayOffset = isRaised || !grows ? raisedOffset : safeBottom + dropToRest
      let trayTopAtRest = proxy.size.height + safeBottom - maxHeight + dropToRest
      let plus = rest == .pageBar ? app.browse.pagePlusFrame : app.browse.floatingPlusFrame
      let pillAtRest = plus.offsetBy(dx: -origin.x, dy: -origin.y - trayTopAtRest)
      ZStack(alignment: .bottom) {
        if let shown {
          dim(over: shown)
            .opacity(isRaised ? 1 - dragShare : 0)
            .animation(reduceMotion ? Motion.surfaceFade : Motion.trayDim, value: isRaised)
            .allowsHitTesting(isRaised && !isClosing)
            .ignoresSafeArea()
          SearchTray(
            request: shown,
            isFocused: $isFocused,
            maxHeight: maxHeight,
            morph: morph,
            dock: grows ? TrayDock(rest: rest, pill: pillAtRest) : nil,
            dismissDrag: dismissDrag
          )
          .id(presentation)
          .onAppear(perform: rise)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { trayHeight = $0 }
          .offset(y: trayOffset)
          .opacity(isRaised || grows ? 1 : 0)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .allowsHitTesting(!isClosing)
          .accessibilityAddTraits(.isModal)
        }
      }
      .onChange(of: proxy.size.height + proxy.safeAreaInsets.top + safeBottom, initial: true) { _, height in
        screenHeight = height
      }
    }
    .ignoresSafeArea(.keyboard)
    .onAppear { keyboard.start() }
    .task { await SearchSuggestionsModel.loadRecents(from: app.tabs) }
    .onChange(of: app.browse.search, initial: true) { _, request in
      if let request {
        present(request)
      } else if shown != nil {
        beginClosing()
      }
    }
  }

  private var keyboardProbe: some View {
    GeometryReader { proxy in
      Color.clear
        .onChange(of: proxy.safeAreaInsets.bottom, initial: true) { _, inset in
          followKeyboard(to: inset)
        }
        .onChange(of: keyboard.announcedHeight) { _, height in
          if let height { followKeyboard(to: height) }
        }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var expectedKeyboardHeight: CGFloat {
    rememberedKeyboardHeight > Self.keyboardThreshold ? rememberedKeyboardHeight : screenHeight * BrowseLayout.keyboardShareOfScreen
  }

  private var mayFocus: Bool {
    !app.settings.isShowingOnboarding && !app.browse.isVoicePresented
  }

  private func followKeyboard(to height: CGFloat) {
    let target = height > Self.keyboardThreshold ? height : 0
    guard abs(target - keyboardHeight) > 1 else { return }
    keyboardHeight = target
    if target > 0 {
      rememberedKeyboardHeight = target
      holdsLift = false
      guard isRaised, abs(target - keyboardLift) > 1 else { return }
      withAnimation(keyboard.animation) { keyboardLift = target }
    } else if isRaised, !isDragging, !holdsLift {
      withAnimation(keyboard.animation) { keyboardLift = 0 }
    }
  }

  private func dim(over request: BrowseSession.SearchRequest) -> some View {
    Color.black
      .opacity(request.origin == .page ? BrowseLayout.trayDim : 0.001)
      .contentShape(.rect)
      .onTapGesture { app.cancelSearch() }
      .accessibilityLabel("Close Search")
      .accessibilityAddTraits(.isButton)
  }

  private func maxHeight(in proxy: GeometryProxy, lift: CGFloat) -> CGFloat {
    let preferred = BrowseLayout.sheetAboveKeyboard + BrowseLayout.searchFieldHeight * (fieldScale - 1)
    let openLift = max(lift, keyboardHeight, isRaised ? 0 : expectedKeyboardHeight)
    let available = proxy.size.height + proxy.safeAreaInsets.bottom - openLift - Spacing.tight
    return max(min(preferred, available), 0)
  }

  private func present(_ request: BrowseSession.SearchRequest) {
    removalTask?.cancel()
    settleTask?.cancel()
    restTask?.cancel()
    let reopens = shown != nil && isClosing
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      if shown == nil || isClosing { presentation += 1 }
      if !reopens {
        rest = app.surface == .browsing ? .pageBar : .floating
        isRaised = false
        keyboardLift = 0
      }
      shown = request
      isClosing = false
      dragOffset = 0
      holdsLift = false
      isDragging = false
      app.browse.trayOwnsPlus = !reduceMotion
      app.browse.trayCoversPageBar = !reduceMotion && rest == .pageBar
    }
    app.browse.trayHoldsKeyboard = true
    restTask = Task {
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      restWithoutKeyboard()
    }
  }

  private func rise() {
    guard shown != nil, !isClosing else { return }
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.trayGrow) {
      isRaised = true
      keyboardLift = keyboardHeight > 0 ? keyboardHeight : mayFocus ? expectedKeyboardHeight : 0
    }
    guard !reduceMotion else { return }
    focusTask?.cancel()
    focusTask = Task {
      try? await Task.sleep(for: Motion.trayHeadStart)
      guard !Task.isCancelled, shown != nil, !isClosing, mayFocus else { return }
      isFocused = true
    }
  }

  private func restWithoutKeyboard() {
    guard shown != nil, isRaised, !isClosing, !isDragging, keyboardHeight == 0, keyboardLift > 0 else { return }
    holdsLift = false
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.traySettle) { keyboardLift = 0 }
  }

  private func refreshRecents() {
    let tabs = app.tabs
    Task {
      await SearchSuggestionsModel.loadRecents(from: tabs)
      try? await Task.sleep(for: .seconds(3))
      guard shown == nil else { return }
      await SearchSuggestionsModel.loadRecents(from: tabs)
    }
  }

  private func beginClosing() {
    guard !isClosing else { return }
    restTask?.cancel()
    settleTask?.cancel()
    focusTask?.cancel()
    isFocused = false
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.trayShrink) {
      isClosing = true
      isRaised = false
      dragOffset = 0
    }
    removalTask?.cancel()
    removalTask = Task {
      try? await Task.sleep(for: .milliseconds(480))
      guard !Task.isCancelled, isClosing else { return }
      finish()
      refreshRecents()
    }
  }

  private func finish() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      shown = nil
      isClosing = false
      isRaised = false
      keyboardLift = 0
      dragOffset = 0
      holdsLift = false
      isDragging = false
      app.browse.trayOwnsPlus = false
      app.browse.trayCoversPageBar = false
    }
    app.browse.trayHoldsKeyboard = false
  }

  private var dismissDrag: some Gesture {
    DragGesture(minimumDistance: 6, coordinateSpace: .global)
      .onChanged { value in
        guard !isClosing else { return }
        let translation = value.translation.height
        if !isDragging {
          isDragging = true
          settleTask?.cancel()
          restTask?.cancel()
        }
        if TrayDrag.releasesKeyboard(translation: translation), isFocused {
          holdsLift = true
          isFocused = false
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dragOffset = TrayDrag.offset(for: translation) }
      }
      .onEnded { value in
        guard isDragging else { return }
        isDragging = false
        if TrayDrag.shouldDismiss(translation: value.translation.height, velocity: value.velocity.height, trayHeight: trayHeight) {
          app.cancelSearch()
        } else {
          settle()
        }
      }
  }

  private func settle() {
    let wasHolding = holdsLift
    if wasHolding, !app.settings.isShowingOnboarding { isFocused = true }
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.traySettle) { dragOffset = 0 }
    guard wasHolding else { return }
    settleTask = Task {
      try? await Task.sleep(for: .milliseconds(650))
      guard !Task.isCancelled else { return }
      restWithoutKeyboard()
    }
  }
}

enum TrayRest {
  case pageBar
  case floating
}

struct TrayDock: Equatable {
  let rest: TrayRest
  let pill: CGRect
}
