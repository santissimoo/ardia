import ArdiaBrowser
import ArdiaDesign
import SwiftUI

struct BottomBar: View {
  let hidesPlus: Bool
  var onTabs: () -> Void
  var onPlus: () -> Void
  var onMore: () -> Void
  var onStep: (Int) -> Void = { _ in }
  var onSelectTab: (UUID) -> Void = { _ in }
  var onCloseTab: () -> Void = {}

  @Environment(AppModel.self) private var app

  var body: some View {
    let order = app.deckOrder
    HStack(spacing: 0) {
      Button(action: onTabs) {
        PageBarTabsGlyph(tabs: Array(order.suffix(2)))
          .contentShape(.rect)
      }
      .buttonStyle(BarButtonStyle())
      .contextMenu { recentTabsMenu(order) }
      .accessibilityLabel("Tabs")
      .accessibilityValue(Text("^[\(order.count) tab](inflect: true)"))
      .accessibilityHint("Touch and hold for recent tabs.")
      .accessibilityActions {
        Button("Previous Tab") { onStep(-1) }
        Button("Next Tab") { onStep(1) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onPlus) {
        BarPlusGlyph()
          .frame(width: BrowseLayout.plusCapsule.width, height: BrowseLayout.plusCapsule.height)
          .glassEffect(.regular.interactive(), in: .capsule)
          .opacity(hidesPlus ? 0 : 1)
          .animation(nil, value: hidesPlus)
          .contentShape(.capsule)
      }
      .buttonStyle(BarButtonStyle())
      .accessibilityLabel("New Search")
      .accessibilityHidden(hidesPlus)
      .frame(width: BrowseLayout.plusCapsule.width, height: BrowseLayout.plusCapsule.height)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { app.browse.pagePlusFrame = $0 }

      Button(action: onMore) {
        BarChevronGlyph()
          .frame(width: BrowseLayout.hitTarget, height: BrowseLayout.hitTarget)
          .contentShape(.rect)
      }
      .buttonStyle(BarButtonStyle())
      .accessibilityLabel("Page Menu")
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, BrowseLayout.barSideInset - 4)
  }

  @ViewBuilder
  private func recentTabsMenu(_ order: [BrowserTab]) -> some View {
    let recent = order.dropLast().suffix(8).reversed()
    ForEach(Array(recent)) { tab in
      Button(TabText.title(for: tab)) { onSelectTab(tab.id) }
    }
    if !recent.isEmpty { Divider() }
    Button("Close Tab", systemImage: "xmark", role: .destructive, action: onCloseTab)
  }
}

struct BarPlusGlyph: View {
  var body: some View {
    Image(systemName: "plus")
      .font(.system(size: 18, weight: .medium))
      .foregroundStyle(.primary)
  }
}

struct BarChevronGlyph: View {
  var body: some View {
    Image(systemName: "chevron.up")
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.primary)
      .frame(width: BrowseLayout.chevronCircle, height: BrowseLayout.chevronCircle)
      .glassEffect(.regular.interactive(), in: .circle)
  }
}

struct PageBarSides: View {
  let tabs: [BrowserTab]

  var body: some View {
    HStack(spacing: 0) {
      PageBarTabsGlyph(tabs: tabs)
        .frame(maxWidth: .infinity, alignment: .leading)
      Color.clear
        .frame(width: BrowseLayout.plusCapsule.width, height: BrowseLayout.plusCapsule.height)
      BarChevronGlyph()
        .frame(width: BrowseLayout.hitTarget, height: BrowseLayout.hitTarget)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, BrowseLayout.barSideInset - 4)
    .frame(height: BrowseLayout.hitTarget)
    .padding(.top, BrowseLayout.barHeight - BrowseLayout.barCenterFromBottom - BrowseLayout.hitTarget / 2)
  }
}

struct PageBarTabsGlyph: View {
  let tabs: [BrowserTab]

  var body: some View {
    TabStackGlyph(tabs: tabs)
      .offset(x: -2.8)
      .frame(width: 47, height: BrowseLayout.hitTarget)
  }
}

enum BarPalette {
  static let plusFill = Color.adaptive(light: Color(hex: 0x767680, opacity: 0.16), dark: Color.white.opacity(0.16))
  static let chevronFill = Color.adaptive(light: Color(hex: 0x767680, opacity: 0.12), dark: Color.white.opacity(0.13))
  static let controlEdge = Color.adaptive(light: Color.black.opacity(0.06), dark: Color.white.opacity(0.1))
  static let tileFill = Color.adaptive(light: Color(hex: 0x767680, opacity: 0.2), dark: Color.white.opacity(0.2))
  static let tileEdge = Color.adaptive(light: Color.black.opacity(0.14), dark: Color.white.opacity(0.28))
}

struct BarBacking: View {
  let tone: ToneColor?
  var solid = false

  @Environment(\.profileLook) private var look

  var body: some View {
    ZStack {
      if let tone {
        if solid {
          tone.color
        } else {
          Rectangle().fill(.ultraThinMaterial)
          tone.color.opacity(0.9)
        }
        (tone.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.025))
      } else {
        if solid {
          look.surface
        } else {
          Rectangle().fill(.bar)
          look.surface.opacity(BrowseLayout.sheetTintShare)
        }
      }
    }
    .animation(Motion.barTone, value: tone)
  }
}

struct BarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? BrowseLayout.barControlScale : 1)
      .animation(configuration.isPressed ? Motion.barPressIn : Motion.barPressOut, value: configuration.isPressed)
      .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: configuration.isPressed) { _, pressed in pressed }
  }
}

struct TabStackGlyph: View {
  let tabs: [BrowserTab]

  var body: some View {
    ZStack {
      switch tabs.count {
      case 0:
        RoundedRectangle(cornerRadius: BrowseLayout.tabStackRadius, style: .continuous)
          .strokeBorder(BrowsePalette.foregroundSecondary, lineWidth: 1.5)
          .frame(width: BrowseLayout.tabStackTile.width, height: BrowseLayout.tabStackTile.height)
      case 1:
        TabThumbnail(tab: tabs[0])
          .rotationEffect(.degrees(-4))
      default:
        TabThumbnail(tab: tabs[0])
          .rotationEffect(.degrees(-12))
          .offset(x: -4, y: 1)
        TabThumbnail(tab: tabs[1])
          .rotationEffect(.degrees(6))
          .offset(x: 4, y: -1)
      }
    }
    .accessibilityHidden(true)
  }
}

struct TabThumbnail: View {
  let tab: BrowserTab

  @Environment(AppModel.self) private var app
  @State private var image: CGImage?

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: BrowseLayout.tabStackRadius, style: .continuous)
  }

  var body: some View {
    let size = BrowseLayout.tabStackTile
    ZStack {
      if let memory = app.browse.covers.image(for: tab.id) ?? app.deck.memoryImage(for: tab.id) {
        Image(uiImage: memory)
          .resizable()
          .scaledToFill()
          .frame(width: size.width, height: size.height, alignment: .top)
      } else if let image {
        Image(decorative: image, scale: 1)
          .resizable()
          .scaledToFill()
          .frame(width: size.width, height: size.height, alignment: .top)
      } else {
        fallback
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(shape)
    .overlay { shape.strokeBorder(BarPalette.tileEdge, lineWidth: 0.5) }
    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
    .task(id: tab.snapshotFileName) {
      guard let name = tab.snapshotFileName else {
        image = nil
        return
      }
      image = await app.web.snapshots.image(named: name)
    }
  }

  @ViewBuilder
  private var fallback: some View {
    if tab.isPrivate {
      TabsPalette.incognitoCard
      IncognitoGlyph(size: 12)
    } else {
      ZStack {
        if let theme = ToneColor(hex: tab.themeColorHex) { theme.color } else { BarPalette.tileFill }
        FaviconImage(iconURL: tab.faviconURL, pageURL: tab.url, size: 12)
      }
    }
  }
}

struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(Motion.press, value: configuration.isPressed)
  }
}
