//  GroceryItem.swift
//  Homvi
//  Grocery list item model, shared between meals and standalone shopping.

internal import Foundation

// MARK: - GroceryItem
struct GroceryItem: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var quantity: String
    var unit: String
    var category: GroceryCategory
    var isChecked: Bool
    var sourceMealID: UUID?      // nil = manually added

    init(
        id: UUID = UUID(),
        name: String,
        quantity: String = "1",
        unit: String = "",
        category: GroceryCategory = .other,
        isChecked: Bool = false,
        sourceMealID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = isChecked
        self.sourceMealID = sourceMealID
    }

    var displayQuantity: String {
        unit.isEmpty ? quantity : "\(quantity) \(unit)"
    }

    // MARK: - GroceryCategory
    enum GroceryCategory: String, Codable, CaseIterable, Identifiable {
        case produce    = "Produce"
        case dairy      = "Dairy"
        case meat       = "Meat & Seafood"
        case bakery     = "Bakery"
        case frozen     = "Frozen"
        case pantry     = "Pantry"
        case beverages  = "Beverages"
        case household  = "Household"
        case other      = "Other"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .produce:   return "leaf.fill"
            case .dairy:     return "drop.fill"
            case .meat:      return "flame.fill"
            case .bakery:    return "birthday.cake.fill"
            case .frozen:    return "snowflake"
            case .pantry:    return "cabinet.fill"
            case .beverages: return "cup.and.saucer.fill"
            case .household: return "house.fill"
            case .other:     return "ellipsis.circle.fill"
            }
        }
    }
}
