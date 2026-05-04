//  GroceryListView.swift
//  Hemvo
//  Checked items persist at the bottom of each section until explicitly deleted.

internal import SwiftUI
internal import Combine

// MARK: - GroceryListView
struct GroceryListView: View {

    @ObservedObject var groceryVM: GroceryViewModel
    @Environment(\.dismiss) var dismiss

    @State private var showAddItem    = false
    @State private var showClearAlert = false
    @State private var newItemName    = ""
    @State private var newItemQty     = ""
    @State private var newItemCat     = GroceryItem.GroceryCategory.other

    private let green      = Color(hex: "#4A9E6B")!
    private let greenLight = Color(hex: "#EAF7EF")!
    private let cream      = Color(hex: "#FAF7F2")!
    private let surface    = Color(hex: "#FFFFFF")!
    private let divider    = Color(hex: "#E6DDD0")!
    private let textMain   = Color(hex: "#1A1208")!
    private let textSub    = Color(hex: "#7A6A55")!

    // All categories that have at least one item (checked or not)
    private let categoryOrder: [GroceryItem.GroceryCategory] = [
        .produce, .meat, .dairy, .bakery, .frozen,
        .pantry, .beverages, .household, .other
    ]

    private var orderedCategories: [GroceryItem.GroceryCategory] {
        categoryOrder.filter { cat in
            groceryVM.itemsByCategory[cat.rawValue]?.isEmpty == false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()

                VStack(spacing: 0) {
                    groceryHeader

                    if groceryVM.items.isEmpty {
                        emptyState
                    } else {
                        progressBar
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 20) {
                                ForEach(orderedCategories, id: \.self) { cat in
                                    if let allItems = groceryVM.itemsByCategory[cat.rawValue],
                                       !allItems.isEmpty {
                                        // Unchecked first, checked at the bottom
                                        let unchecked = allItems.filter { !$0.isChecked }
                                        let checked   = allItems.filter {  $0.isChecked }
                                        GroceryCategorySection(
                                            category:  cat,
                                            unchecked: unchecked,
                                            checked:   checked,
                                            onToggle:  { groceryVM.toggleItem(id: $0) },
                                            onDelete:  { groceryVM.deleteItem(id: $0) },
                                            canDelete: { groceryVM.canDelete(id: $0) }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 120)
                        }
                    }
                }

                // Floating + button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabButton
                        Spacer()
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddItem) { addSheet }
            .alert("Clear Checked Items", isPresented: $showClearAlert) {
                Button("Clear", role: .destructive) { groceryVM.clearChecked() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Permanently remove all \(groceryVM.checkedItems.count) checked items?")
            }
        }
    }

    // MARK: - Header
    private var groceryHeader: some View {
        ZStack {
            surface
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GROCERY LIST")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(3)
                        .foregroundColor(green)
                    Text("\(groceryVM.items.count) item\(groceryVM.items.count == 1 ? "" : "s")")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(textMain)
                }
                Spacer()
                HStack(spacing: 10) {
                    // Clear checked — only shown when there are checked items
                    if !groceryVM.checkedItems.isEmpty {
                        Button { showClearAlert = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("\(groceryVM.checkedItems.count)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.09))
                            .cornerRadius(20)
                        }
                    }
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(greenLight)
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 52)
            .padding(.bottom, 14)
        }
        .frame(height: 120)
        .overlay(alignment: .bottom) {
            divider.frame(height: 1)
        }
    }

    // MARK: - Progress Bar
    private var progressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(groceryVM.checkedItems.count) of \(groceryVM.items.count) checked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textSub)
                Spacer()
                Text("\(Int(groceryVM.progress * 100))%")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(green)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(divider)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(green)
                        .frame(width: geo.size.width * groceryVM.progress, height: 6)
                        .animation(.spring(response: 0.4), value: groceryVM.progress)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - FAB
    private var fabButton: some View {
        Button { showAddItem = true } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 28, height: 28)
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.white)
                }
                Text("Add Item")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(green)
                    .shadow(color: green.opacity(0.45), radius: 16, y: 6)
            )
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(greenLight).frame(width: 90, height: 90)
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 36))
                    .foregroundColor(green)
            }
            VStack(spacing: 6) {
                Text("List is Empty")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textMain)
                Text("Add meals to auto-generate your list,\nor tap + to add items manually.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textSub)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Add Item Sheet
    private var addSheet: some View {
        NavigationStack {
            ZStack {
                cream.ignoresSafeArea()
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ITEM NAME")
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(1.5)
                            .foregroundColor(textSub)
                        TextField("e.g. Whole milk", text: $newItemName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(textMain)
                            .padding(14)
                            .background(surface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(divider, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUANTITY")
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(1.5)
                            .foregroundColor(textSub)
                        TextField("e.g. 2 lbs", text: $newItemQty)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(textMain)
                            .padding(14)
                            .background(surface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(divider, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CATEGORY")
                            .font(.system(size: 9, weight: .heavy))
                            .kerning(1.5)
                            .foregroundColor(textSub)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(GroceryItem.GroceryCategory.allCases) { cat in
                                    let isSelected = newItemCat == cat
                                    Button { newItemCat = cat } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: cat.iconName)
                                                .font(.system(size: 10, weight: .bold))
                                            Text(cat.rawValue)
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundColor(isSelected ? .white : green)
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(isSelected ? green : greenLight)
                                        .cornerRadius(20)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    Button {
                        guard !newItemName.isEmpty else { return }
                        groceryVM.addItem(GroceryItem(
                            name:     newItemName,
                            quantity: newItemQty.isEmpty ? "1" : newItemQty,
                            category: newItemCat
                        ))
                        newItemName = ""; newItemQty = ""; newItemCat = .other
                        showAddItem = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 18))
                            Text("Add to List").font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(newItemName.isEmpty ? Color(hex: "#C5C0B8")! : green)
                        .cornerRadius(16)
                        .animation(.easeInOut(duration: 0.15), value: newItemName.isEmpty)
                    }
                    .disabled(newItemName.isEmpty)
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddItem = false }.foregroundColor(green)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - GroceryCategorySection
struct GroceryCategorySection: View {
    let category:  GroceryItem.GroceryCategory
    let unchecked: [GroceryItem]
    let checked:   [GroceryItem]
    let onToggle:  (UUID) -> Void
    let onDelete:  (UUID) -> Void
    var canDelete: (UUID) -> Bool = { _ in true }

    private let green      = Color(hex: "#4A9E6B")!
    private let greenLight = Color(hex: "#EAF7EF")!
    private let divider    = Color(hex: "#E6DDD0")!
    private let textSub    = Color(hex: "#7A6A55")!

    var allItems: [GroceryItem] { unchecked + checked }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(greenLight)
                        .frame(width: 26, height: 26)
                    Image(systemName: category.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(green)
                }
                Text(category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(1.5)
                    .foregroundColor(textSub)
                Spacer()
                // Show remaining unchecked count
                if !unchecked.isEmpty {
                    Text("\(unchecked.count) left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(textSub.opacity(0.7))
                } else {
                    // All done indicator
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(green)
                        Text("All done")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(green)
                    }
                }
            }

            // Items card: unchecked on top, checked at bottom separated by a divider
            VStack(spacing: 0) {
                // Unchecked items
                ForEach(unchecked) { item in
                    GroceryCheckRow(
                        item:      item,
                        canDelete: canDelete(item.id),
                        onToggle:  { onToggle(item.id) },
                        onDelete:  { onDelete(item.id) }
                    )
                    if item.id != unchecked.last?.id || !checked.isEmpty {
                        divider.frame(height: 1).padding(.leading, 52)
                    }
                }

                // Divider + "Checked" label before checked section
                if !checked.isEmpty && !unchecked.isEmpty {
                    HStack(spacing: 8) {
                        divider.frame(height: 1)
                        Text("CHECKED")
                            .font(.system(size: 8, weight: .heavy))
                            .kerning(1.2)
                            .foregroundColor(textSub.opacity(0.5))
                            .fixedSize()
                        divider.frame(height: 1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }

                // Checked items — dimmed, swipe to delete
                ForEach(checked) { item in
                    GroceryCheckRow(
                        item:      item,
                        canDelete: canDelete(item.id),
                        onToggle:  { onToggle(item.id) },
                        onDelete:  { onDelete(item.id) }
                    )
                    if item.id != checked.last?.id {
                        divider.frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(divider, lineWidth: 1)
            )
        }
    }
}

// MARK: - GroceryCheckRow
struct GroceryCheckRow: View {
    let item:      GroceryItem
    var canDelete: Bool = true
    let onToggle:  () -> Void
    let onDelete:  () -> Void

    private let green   = Color(hex: "#4A9E6B")!
    private let divider = Color(hex: "#E6DDD0")!

    var body: some View {
        HStack(spacing: 12) {
            // Tap to toggle check
            Button { onToggle() } label: {
                ZStack {
                    Circle()
                        .stroke(item.isChecked ? green : Color(hex: "#D0C8BE")!, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if item.isChecked {
                        Circle().fill(green).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.white)
                    }
                }
            }
            .animation(.spring(response: 0.25), value: item.isChecked)

            Text(item.name)
                .font(.system(size: 14, weight: item.isChecked ? .regular : .semibold))
                .strikethrough(item.isChecked, color: Color(hex: "#A09080")!)
                .foregroundColor(item.isChecked ? Color(hex: "#A09080")! : Color(hex: "#1A1208")!)
                .animation(.easeInOut(duration: 0.15), value: item.isChecked)

            Spacer()

            if !item.displayQuantity.isEmpty {
                Text(item.displayQuantity)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#7A6A55")!)
                    .opacity(item.isChecked ? 0.5 : 1)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: "#F2EDE5")!)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // Swipe left to delete — only for the item's creator
        .if(canDelete) { view in
            view.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        // Swipe right to uncheck (only for checked items)
        .if(item.isChecked) { view in
            view.swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { onToggle() } label: {
                    Label("Uncheck", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .tint(Color(hex: "#4A9E6B")!)
            }
        }
    }
}
