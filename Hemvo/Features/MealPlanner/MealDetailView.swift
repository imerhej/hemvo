//  MealDetailView.swift
//  Hemvo
//  Redesigned: warm editorial palette matching MealPlannerView.

internal import SwiftUI
internal import Combine

// MARK: - MealDetailView
struct MealDetailView: View {
    let mealID: UUID                              // stable identity
    @ObservedObject var mealVM: MealPlanViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showEditMeal    = false
    @State private var showDeleteAlert = false

    // Always reads the latest version from the VM — survives edits
    private var meal: Meal? {
        mealVM.meals.first(where: { $0.id == mealID })
    }

    // Match MealRecipeCard colors
    private func typeColor(for meal: Meal) -> Color {
        switch meal.mealType {
        case .breakfast: return Color(hex: "#C8922A")!
        case .lunch:     return Color(hex: "#4A9E6B")!
        case .dinner:    return Color(hex: "#3B7DD8")!
        case .snack:     return Color(hex: "#9A5CC4")!
        }
    }
    private func typeBg(for meal: Meal) -> Color {
        switch meal.mealType {
        case .breakfast: return Color(hex: "#FEF5E7")!
        case .lunch:     return Color(hex: "#EAF7EF")!
        case .dinner:    return Color(hex: "#EBF2FD")!
        case .snack:     return Color(hex: "#F5EEF9")!
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#FAF7F2")!.ignoresSafeArea()

                if let meal {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            heroCard(meal: meal)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)

                            ingredientsCard(meal: meal)
                                .padding(.horizontal, 20)

                            if !meal.notes.isEmpty {
                                notesCard(meal: meal)
                                    .padding(.horizontal, 20)
                            }

                            actionButtons(meal: meal)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 40)
                        }
                    }
                    .sheet(isPresented: $showEditMeal) {
                        AddMealView(mealVM: mealVM, editingMeal: meal)
                    }
                    .alert("Remove Meal", isPresented: $showDeleteAlert) {
                        Button("Remove", role: .destructive) {
                            mealVM.deleteMeal(meal)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("Remove \"\(meal.name)\" from your meal plan?")
                    }
                } else {
                    // Meal was deleted — dismiss automatically
                    Color.clear.onAppear { dismiss() }
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Hero Card
    private func heroCard(meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: type badge + Done
            HStack {
                // Meal type pill
                HStack(spacing: 5) {
                    Image(systemName: meal.mealType.iconName)
                        .font(.system(size: 10, weight: .bold))
                    Text(meal.mealType.label.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(1.2)
                }
                .foregroundColor(typeColor(for: meal))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(typeBg(for: meal))
                .cornerRadius(20)

                // Day pill
                Text(meal.day.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1)
                    .foregroundColor(Color(hex: "#7A6A55")!)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#F2EDE5")!)
                    .cornerRadius(20)

                Spacer()

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(typeColor(for: meal))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(typeBg(for: meal))
                        .cornerRadius(20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Colored top bar
            Rectangle()
                .fill(typeColor(for: meal))
                .frame(height: 3)

            VStack(alignment: .leading, spacing: 14) {
                // Meal name
                Text(meal.name)
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(Color(hex: "#1A1208")!)
                    .fixedSize(horizontal: false, vertical: true)

                // Stats row
                HStack(spacing: 12) {
                    DetailStatPill(icon: "clock.fill",   value: "\(meal.prepTimeMinutes) min", color: typeColor(for: meal))
                    DetailStatPill(icon: "person.2.fill", value: "\(meal.servings) servings",  color: typeColor(for: meal))
                    if !meal.ingredients.isEmpty {
                        DetailStatPill(icon: "list.bullet", value: "\(meal.ingredients.count) ingredients", color: typeColor(for: meal))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#E6DDD0")!, lineWidth: 1)
        )
        .shadow(color: Color(hex: "#1A1208")!.opacity(0.05), radius: 8, y: 3)
    }

    // MARK: - Ingredients Card
    private func ingredientsCard(meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(typeColor(for: meal))
                Text("INGREDIENTS")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.5)
                    .foregroundColor(Color(hex: "#7A6A55")!)
                Spacer()
                Text("\(meal.ingredients.count) items")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#7A6A55")!.opacity(0.7))
            }

            if meal.ingredients.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "cart.badge.plus")
                        .foregroundColor(typeColor(for: meal).opacity(0.5))
                    Text("No ingredients added.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#7A6A55")!)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(meal.ingredients) { ing in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(typeColor(for: meal).opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text(ing.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: "#1A1208")!)
                            Spacer()
                            if !ing.displayQuantity.isEmpty {
                                Text(ing.displayQuantity)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(hex: "#7A6A55")!)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "#F2EDE5")!)
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)

                        if ing.id != meal.ingredients.last?.id {
                            Color(hex: "#E6DDD0")!.frame(height: 1)
                                .padding(.leading, 32)
                        }
                    }
                }
                .background(Color(hex: "#FAFAF8")!)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: "#E6DDD0")!, lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#E6DDD0")!, lineWidth: 1)
        )
        .shadow(color: Color(hex: "#1A1208")!.opacity(0.04), radius: 6, y: 2)
    }

    // MARK: - Notes Card
    private func notesCard(meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "note.text")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(typeColor(for: meal))
                Text("NOTES")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.5)
                    .foregroundColor(Color(hex: "#7A6A55")!)
            }
            Text(meal.notes)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(hex: "#4A3F30")!)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(typeBg(for: meal).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(typeColor(for: meal).opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons
    private func actionButtons(meal: Meal) -> some View {
        VStack(spacing: 10) {
            // Edit — always visible for all household members
            Button { showEditMeal = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                    Text("Edit Meal")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(typeColor(for: meal))
                .cornerRadius(14)
                .shadow(color: typeColor(for: meal).opacity(0.35), radius: 10, y: 4)
            }

            // Delete — only for the creator
            if mealVM.canDelete(meal) {
                Button { showDeleteAlert = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Remove Meal")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.07))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
    }
}

// MARK: - DetailStatPill
private struct DetailStatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(20)
    }
}

#Preview {
    let vm = MealPlanViewModel()
    let sampleMeal = Meal(
        name: "Avocado Toast",
        day: .monday,
        mealType: .breakfast,
        ingredients: [
            GroceryItem(name: "Sourdough bread", quantity: "2", unit: "slices"),
            GroceryItem(name: "Avocado", quantity: "1"),
            GroceryItem(name: "Lemon", quantity: "½")
        ],
        notes: "Toast bread until golden. Mash avocado with lemon juice and salt.",
        prepTimeMinutes: 10,
        servings: 2
    )
    vm.addMeal(sampleMeal)
    return MealDetailView(mealID: sampleMeal.id, mealVM: vm)
}
