//  ShoppingList.swift
//  Hemvo
//  Shopping list models — separate from grocery/meal lists.

internal import Foundation

// MARK: - ShoppingList
struct ShoppingList: Codable, Identifiable, Equatable, Hashable {
    var id:        UUID    = UUID()
    var name:      String
    var emoji:     String  = "🛒"
    var createdAt: Date    = Date()
    var createdBy: String?
    var items:     [ShoppingItem] = []

    var totalItems:     Int { items.count }
    var checkedItems:   Int { items.filter { $0.isChecked }.count }
    var progress: Double {
        totalItems == 0 ? 0 : Double(checkedItems) / Double(totalItems)
    }
    var isComplete: Bool { totalItems > 0 && checkedItems == totalItems }
}

// MARK: - ShoppingItem
struct ShoppingItem: Codable, Identifiable, Equatable, Hashable {
    var id:        UUID               = UUID()
    var name:      String
    var quantity:  String             = "1"
    var unit:      String             = ""
    var category:  ShoppingCategory   = .other
    var isChecked: Bool               = false
    var note:      String             = ""
    var createdBy: String?

    var displayQuantity: String {
        unit.isEmpty ? quantity : "\(quantity) \(unit)"
    }
}

// MARK: - ShoppingCategory
enum ShoppingCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case produce    = "Produce"
    case dairy      = "Dairy"
    case meat       = "Meat & Seafood"
    case bakery     = "Bakery"
    case frozen     = "Frozen"
    case pantry     = "Pantry"
    case beverages  = "Beverages"
    case household  = "Household"
    case clothing   = "Clothing"
    case electronics = "Electronics"
    case pharmacy   = "Pharmacy"
    case other      = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .produce:     return "leaf.fill"
        case .dairy:       return "drop.fill"
        case .meat:        return "flame.fill"
        case .bakery:      return "birthday.cake.fill"
        case .frozen:      return "snowflake"
        case .pantry:      return "cabinet.fill"
        case .beverages:   return "cup.and.saucer.fill"
        case .household:   return "house.fill"
        case .clothing:    return "tshirt.fill"
        case .electronics: return "bolt.fill"
        case .pharmacy:    return "cross.case.fill"
        case .other:       return "ellipsis.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .produce:     return "#3D7A52"
        case .dairy:       return "#2196F3"
        case .meat:        return "#C0392B"
        case .bakery:      return "#E67E22"
        case .frozen:      return "#00BCD4"
        case .pantry:      return "#795548"
        case .beverages:   return "#9C27B0"
        case .household:   return "#607D8B"
        case .clothing:    return "#E91E63"
        case .electronics: return "#FF9800"
        case .pharmacy:    return "#F44336"
        case .other:       return "#7A6A55"
        }
    }
}
