//  AppWalkthroughView.swift
//  Hemvo
//  One-time feature walkthrough shown after the user completes household setup.
//  Dismissed by tapping "Get Started" on the last page or "Skip" on any page.

internal import SwiftUI

// MARK: - Walkthrough entry point

struct AppWalkthroughView: View {
    let onFinish: () -> Void

    @State private var currentPage = 0

    private let pages: [WalkthroughPage] = [
        WalkthroughPage(
            icon: "house.circle.fill",
            title: "Welcome to Hemvo",
            description: "Everything your household needs, all in one place. Let's show you what's inside.",
            color: Color(hex: "#4CAF74") ?? .green,
            gradient: [Color(hex: "#1B5E34") ?? .green, Color(hex: "#4CAF74") ?? .green]
        ),
        WalkthroughPage(
            icon: "fork.knife",
            title: "Meal Planner",
            description: "Plan your family's meals for the week. Hemvo builds your grocery list automatically as you add meals.",
            color: Color(hex: "#FF9800") ?? .orange,
            gradient: [Color(hex: "#E65100") ?? .orange, Color(hex: "#FF9800") ?? .orange]
        ),
        WalkthroughPage(
            icon: "dollarsign.circle.fill",
            title: "Budget",
            description: "Track bills and household spending. Get reminded before payments are due so nothing slips through.",
            color: Color(hex: "#2196F3") ?? .blue,
            gradient: [Color(hex: "#0D47A1") ?? .blue, Color(hex: "#2196F3") ?? .blue]
        ),
        WalkthroughPage(
            icon: "calendar",
            title: "Family Schedule",
            description: "Add events once and share them with every household member in real time.",
            color: Color(hex: "#9C27B0") ?? .purple,
            gradient: [Color(hex: "#4A148C") ?? .purple, Color(hex: "#9C27B0") ?? .purple]
        ),
        WalkthroughPage(
            icon: "wrench.and.screwdriver.fill",
            title: "Fix-It List",
            description: "Log home maintenance tasks, set due dates, and get reminded before anything goes overdue.",
            color: Color(hex: "#F44336") ?? .red,
            gradient: [Color(hex: "#B71C1C") ?? .red, Color(hex: "#F44336") ?? .red]
        )
    ]

    var isLastPage: Bool { currentPage == pages.count - 1 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: pages[currentPage].gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.45), value: currentPage)

            VStack(spacing: 0) {
                // Skip button row
                HStack {
                    Spacer()
                    if !isLastPage {
                        Button("Skip") { onFinish() }
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 24)
                    }
                }
                .frame(height: 56)
                .padding(.top, 8)

                // Swipeable pages
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        WalkthroughPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Dots + CTA
                VStack(spacing: 28) {
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(Color.white.opacity(index == currentPage ? 1.0 : 0.35))
                                .frame(width: index == currentPage ? 22 : 8, height: 8)
                                .animation(
                                    .spring(response: 0.35, dampingFraction: 0.7),
                                    value: currentPage
                                )
                        }
                    }

                    Button {
                        if isLastPage {
                            onFinish()
                        } else {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                currentPage += 1
                            }
                        }
                    } label: {
                        Text(isLastPage ? "Get Started" : "Next")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .foregroundColor(pages[currentPage].color)
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.top, 16)
                .padding(.bottom, 52)
            }
        }
    }
}

// MARK: - Data model

private struct WalkthroughPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let gradient: [Color]
}

// MARK: - Individual page view

private struct WalkthroughPageView: View {
    let page: WalkthroughPage
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 160, height: 160)
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 114, height: 114)
                Image(systemName: page.icon)
                    .font(.system(size: 54))
                    .foregroundColor(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(appeared ? 1.0 : 0.65)
            .opacity(appeared ? 1.0 : 0.0)
            .animation(.spring(response: 0.55, dampingFraction: 0.72).delay(0.08), value: appeared)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 36)
            }
            .offset(y: appeared ? 0 : 24)
            .opacity(appeared ? 1.0 : 0.0)
            .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15), value: appeared)

            Spacer()
            Spacer()
        }
        .onAppear  { appeared = true  }
        .onDisappear { appeared = false }
    }
}
