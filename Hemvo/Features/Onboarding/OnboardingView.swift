//  OnboardingView.swift
//  Hemvo
//  Animated 5-page onboarding with CTA to start trial or sign in.

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - OnboardingView
struct OnboardingView: View {

    @State private var currentPage = 0
    @State private var showSignUp  = false
    @State private var showLogin   = false
    @State private var animateBg   = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon:      "house.circle.fill",
            gradient:  [Color(hex: "#4CAF74") ?? .green, Color(hex: "#1B5E34") ?? .green],
            accent:    Color(hex: "#A5D6A7") ?? .green,
            title:     "Welcome to Hemvo",
            subtitle:  "Your all-in-one home management app for busy working professionals.",
            tag:       "HOME"
        ),
        OnboardingPage(
            icon:      "fork.knife.circle.fill",
            gradient:  [Color(hex: "#FF9800") ?? .orange, Color(hex: "#E65100") ?? .orange],
            accent:    Color(hex: "#FFCC80") ?? .orange,
            title:     "Plan Meals Effortlessly",
            subtitle:  "Build weekly meal plans and auto-generate your grocery list in seconds.",
            tag:       "MEALS"
        ),
        OnboardingPage(
            icon:      "dollarsign.circle.fill",
            gradient:  [Color(hex: "#2196F3") ?? .blue, Color(hex: "#0D47A1") ?? .blue],
            accent:    Color(hex: "#90CAF9") ?? .blue,
            title:     "Master Your Budget",
            subtitle:  "Track expenses, set category limits, and never miss a bill payment.",
            tag:       "BUDGET"
        ),
        OnboardingPage(
            icon:      "calendar.circle.fill",
            gradient:  [Color(hex: "#9C27B0") ?? .purple, Color(hex: "#4A148C") ?? .purple],
            accent:    Color(hex: "#CE93D8") ?? .purple,
            title:     "Sync Your Family",
            subtitle:  "Share a calendar with every household member.",
            tag:       "SCHEDULE"
        ),
        OnboardingPage(
            icon:      "wrench.and.screwdriver",
            gradient:  [Color(hex: "#F44336") ?? .red, Color(hex: "#B71C1C") ?? .red],
            accent:    Color(hex: "#EF9A9A") ?? .red,
            title:     "Stay Ahead of Maintenance",
            subtitle:  "Track tasks, delegate them to household members.",
            tag:       "MAINTENANCE"
        ),
    ]

    var currentGradient: [Color] { pages[currentPage].gradient }

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: currentGradient,
                startPoint: animateBg ? .topLeading : .bottomTrailing,
                endPoint:   animateBg ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: currentPage)

            // Decorative blobs
            decorativeBlobs

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        showSignUp = true
                    }
                    .font(.subheadline).bold()
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { i in
                        OnboardingPageView(page: pages[i])
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                .animation(.easeInOut, value: currentPage)

                // Bottom section
                VStack(spacing: 20) {
                    // Page dots
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage
                                      ? Color.white
                                      : Color.white.opacity(0.35))
                                .frame(width: i == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    // Next / Get Started button
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation(.spring(response: 0.4)) { currentPage += 1 }
                        } else {
                            showSignUp = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(currentPage < pages.count - 1 ? "Next" : "Start Free Trial")
                                .font(.headline).bold()
                            Image(systemName: currentPage < pages.count - 1
                                  ? "arrow.right" : "checkmark.circle.fill")
                        }
                        .foregroundColor(currentGradient.first ?? .green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.white)
                        .cornerRadius(18)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                    }
                    .animation(.easeInOut(duration: 0.2), value: currentPage)

                    // Login link
                    HStack(spacing: 4) {
                        Text("Already have an account?")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Button("Sign In") { showLogin = true }
                            .font(.subheadline).bold()
                            .foregroundColor(.white)
                            .underline()
                    }

                    Text("No credit card required · Cancel anytime")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
            }
        }
        .fullScreenCover(isPresented: $showSignUp) { LoginView(mode: .signUp) }
        .fullScreenCover(isPresented: $showLogin)  { LoginView(mode: .login) }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                animateBg = true
            }
        }
    }

    // MARK: - Decorative Blobs
    private var decorativeBlobs: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 300)
                .offset(x: 140, y: -200)
                .animation(.easeInOut(duration: 0.6), value: currentPage)
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 200)
                .offset(x: -100, y: 250)
                .animation(.easeInOut(duration: 0.6), value: currentPage)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 120)
                .offset(x: 120, y: 300)
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.white.opacity(0.04))
                .frame(width: 160, height: 160)
                .rotationEffect(.degrees(30))
                .offset(x: -130, y: -300)
        }
        .ignoresSafeArea()
    }
}

// MARK: - OnboardingPage Model
struct OnboardingPage {
    let icon:     String
    let gradient: [Color]
    let accent:   Color
    let title:    String
    let subtitle: String
    let tag:      String
}

// MARK: - OnboardingPageView
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var appear = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Feature tag
            Text(page.tag)
                .font(.system(size: 11, weight: .heavy))
                .kerning(2)
                .foregroundColor(page.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.18))
                .cornerRadius(20)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
                .animation(.spring(response: 0.5).delay(0.05), value: appear)

            // Icon with layered rings
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 170, height: 170)
                // Mid ring
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 130, height: 130)
                // Inner circle
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 100, height: 100)
                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 52))
                    .foregroundColor(.white)
            }
            .scaleEffect(appear ? 1 : 0.7)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appear)

            // Text
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title).bold()
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 16)
                    .animation(.spring(response: 0.5).delay(0.15), value: appear)

                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 16)
                    .animation(.spring(response: 0.5).delay(0.2), value: appear)
            }

            Spacer()
        }
        .onAppear {
            appear = false
            // Tiny delay so the animation fires after tab switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appear = true
            }
        }
        .onDisappear { appear = false }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthViewModel())
}
