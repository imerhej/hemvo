//  AddMealView.swift
//  Hemvo

internal import SwiftUI
internal import StoreKit
internal import CoreData
internal import CloudKit
internal import Foundation
internal import Combine
internal import UserNotifications

// MARK: - AddMealView
struct AddMealView: View {
    @ObservedObject var mealVM: MealPlanViewModel
    @Environment(\.dismiss) var dismiss

    var preselectedDay:  Meal.Weekday  = .monday
    var preselectedType: Meal.MealType = .breakfast   // ← new param
    var editingMeal:     Meal?         = nil

    @State private var name           = ""
    @State private var day            = Meal.Weekday.monday
    @State private var mealType       = Meal.MealType.breakfast   // default breakfast
    @State private var notes          = ""
    @State private var prepTime       = 30
    @State private var servings       = 4
    @State private var ingredients:   [GroceryItem] = []
    @State private var newIngredient  = ""
    @State private var newQty         = ""

    var isEditing: Bool { editingMeal != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Details") {
                    TextField("Meal name (e.g. Pasta Primavera)", text: $name)
                        .foregroundColor(.primary)

                    Picker("Day", selection: $day) {
                        ForEach(Meal.Weekday.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .foregroundColor(.blue)
                    .pickerStyle(.menu)

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
                        TextField("Qty", text: $newQty)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
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
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        if let m = editingMeal {
            // Editing an existing meal — restore all fields
            name        = m.name
            day         = m.day
            mealType    = m.mealType
            notes       = m.notes
            prepTime    = m.prepTimeMinutes
            servings    = m.servings
            ingredients = m.ingredients
        } else {
            // New meal — apply preselected day AND type from the tapped slot
            day      = preselectedDay
            mealType = preselectedType
        }
    }

    private func save() {
        guard !name.isEmpty else { return }
        let meal = Meal(
            id:              editingMeal?.id ?? UUID(),
            name:            name,
            day:             day,
            mealType:        mealType,
            ingredients:     ingredients,
            notes:           notes,
            prepTimeMinutes: prepTime,
            servings:        servings
        )
        mealVM.addMeal(meal)
        DispatchQueue.main.async { dismiss() }
    }
}
