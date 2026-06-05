//  AddMealView.swift
//  Hemvo

internal import SwiftUI
internal import Foundation

// MARK: - AddMealView
struct AddMealView: View {
    @ObservedObject var mealVM: MealPlanViewModel
    @Environment(\.dismiss) var dismiss

    var preselectedDate: Date          = Date()
    var preselectedType: Meal.MealType = .breakfast
    var editingMeal:     Meal?         = nil

    @State private var name           = ""
    @State private var selectedDate   = Date()
    @State private var mealType       = Meal.MealType.breakfast
    @State private var notes          = ""
    @State private var prepTime       = 30
    @State private var servings       = 4
    @State private var ingredients:   [GroceryItem] = []
    @State private var newIngredient  = ""
    @State private var newQty         = ""

    private enum Field { case name, notes }
    @FocusState private var focus: Field?
    @FocusState private var ingredientNameFocused: Bool
    @FocusState private var ingredientQtyFocused: Bool

    var isEditing: Bool { editingMeal != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Details") {
                    TextField("Meal name (e.g. Pasta Primavera)", text: $name)
                        .foregroundColor(.primary)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .notes }

                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .foregroundColor(.blue)

                    Picker("Meal Type", selection: $mealType) {
                        ForEach(Meal.MealType.allCases) { t in
                            Label(t.label, systemImage: t.iconName).tag(t)
                        }
                    }
                    .foregroundColor(.blue)
                    .pickerStyle(.menu)

                    Stepper("Prep Time: \(prepTime) min", value: $prepTime, in: 5...240, step: 5)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...20)
                }

                Section("Ingredients") {
                    HStack {
                        TextField("Ingredient name", text: $newIngredient)
                            .focused($ingredientNameFocused)
                            .submitLabel(.next)
                            .onSubmit { ingredientQtyFocused = true }
                        TextField("Qty", text: $newQty)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .focused($ingredientQtyFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                guard !newIngredient.isEmpty else { return }
                                ingredients.append(
                                    GroceryItem(name: newIngredient, quantity: newQty.isEmpty ? "1" : newQty)
                                )
                                newIngredient = ""; newQty = ""
                                ingredientNameFocused = true
                            }
                        Button("Add") {
                            guard !newIngredient.isEmpty else { return }
                            ingredients.append(
                                GroceryItem(name: newIngredient, quantity: newQty.isEmpty ? "1" : newQty)
                            )
                            newIngredient = ""; newQty = ""
                        }
                        .foregroundColor(.blue)
                        .disabled(newIngredient.isEmpty)
                    }
                    ForEach(ingredients) { ing in
                        HStack {
                            Text(ing.name)
                            Spacer()
                            Text(ing.displayQuantity).foregroundColor(.secondary).font(.caption)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                }

                Section("Notes") {
                    TextField("Optional cooking notes…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focus, equals: .notes)
                        .submitLabel(.done)
                        .onSubmit { focus = nil }
                }
            }
            .navigationTitle(isEditing ? "Edit Meal" : "Add Meal")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.blue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.blue)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundColor(name.isEmpty ? .gray : .blue)
                        .disabled(name.isEmpty)
                }
            }
            .onAppear {
                prefill()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focus = .name }
            }
        }
    }

    private func prefill() {
        if let m = editingMeal {
            name         = m.name
            selectedDate = m.date
            mealType     = m.mealType
            notes        = m.notes
            prepTime     = m.prepTimeMinutes
            servings     = m.servings
            ingredients  = m.ingredients
        } else {
            selectedDate = preselectedDate
            mealType     = preselectedType
        }
    }

    private func save() {
        guard !name.isEmpty else { return }
        let meal = Meal(
            id:              editingMeal?.id ?? UUID(),
            name:            name,
            date:            selectedDate,
            mealType:        mealType,
            ingredients:     ingredients,
            notes:           notes,
            prepTimeMinutes: prepTime,
            servings:        servings
        )
        if isEditing {
            mealVM.updateMeal(meal)
        } else {
            mealVM.addMeal(meal)
        }
        DispatchQueue.main.async { dismiss() }
    }
}
