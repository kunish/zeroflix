import SwiftUI

/// The faux iOS status bar drawn by the source design (real one is hidden).
struct StatusBarRow: View {
    var body: some View {
        HStack {
            Text("20:51")
                .font(.system(size: 16, weight: .semibold))
                .kerning(0.3)
            Spacer()
            HStack(spacing: 7) {
                Text("▪▪▪▪").font(.system(size: 13)).kerning(1)
                Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
                Text("66")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RFX.green, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .foregroundStyle(RFX.text)
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }
}

/// "今日热门剧集 ›" style section header.
struct SectionHeader: View {
    let title: String
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 23, weight: .heavy))
                .foregroundStyle(RFX.text)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }
}

/// A simple full-bleed loading shimmer placeholder block.
struct LoadingBlock: View {
    var height: CGFloat
    var cornerRadius: CGFloat = 16
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(RFX.card)
            .frame(height: height)
            .redacted(reason: .placeholder)
    }
}
