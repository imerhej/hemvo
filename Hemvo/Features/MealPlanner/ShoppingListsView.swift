//  ShoppingListsView.swift
//  Hemvo

internal import SwiftUI
internal import Combine

// MARK: - Icon helper
private func listIcon(from stored: String) -> (symbol: String, color: Color) {
    if stored.hasPrefix("sf:") {
        let parts  = stored.dropFirst(3).components(separatedBy: ":")
        let symbol = parts.first ?? "cart.fill"
        let color  = parts.count > 1 ? (Color(hex: parts[1]) ?? Color(hex: "#C8922A")!) : Color(hex: "#C8922A")!
        return (symbol, color)
    }
    // Legacy / fallback
    return ("cart.fill", Color(hex: "#C8922A")!)
}

// MARK: - Palette
private let slAmber   = Color(hex: "#C8922A")!
private let slAmberBg = Color(hex: "#F5E4C3")!
private let slBrown   = Color(hex: "#1A1208")!
private let slMuted   = Color(hex: "#7A6A55")!
private let slDivider = Color(hex: "#E6DDD0")!
private let slCream   = Color(hex: "#FAF7F2")!

// MARK: - ShoppingListsView
struct ShoppingListsView: View {

    @StateObject private var vm = ShoppingListViewModel()
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var showNewList     = false
    @State private var listToDelete:   ShoppingList? = nil
    @State private var showDeleteAlert = false

    private var canWrite: Bool {
        let role = authVM.profile?.role ?? ""
        return role != "Teen" && role != "Child"
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                slCream.ignoresSafeArea()

                if vm.lists.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 14) {
                            ForEach(vm.lists) { list in
                                NavigationLink(value: list) {
                                    ShoppingListCard(list: list, canDelete: vm.canDelete(list)) {
                                        listToDelete   = list
                                        showDeleteAlert = true
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                }

                // FAB
                if canWrite {
                    Button { showNewList = true } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.25)).frame(width: 28, height: 28)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundColor(.white)
                            }
                            Text("New List")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 13)
                        .background(Capsule().fill(slAmber)
                            .shadow(color: slAmber.opacity(0.45), radius: 16, y: 6))
                    }
                    .padding(.trailing, 20).padding(.bottom, 28)
                }
            }
            .navigationTitle("Shopping Lists")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: ShoppingList.self) { list in
                ShoppingListDetailView(listID: list.id, vm: vm)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(slMuted)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewList) { NewShoppingListSheet(vm: vm) }
        .alert("Delete List", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let l = listToDelete { vm.deleteList(l) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(listToDelete?.name ?? "")\" and all its items?")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(slAmberBg).frame(width: 100, height: 100)
                Image(systemName: "cart.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(slAmber)
            }
            VStack(spacing: 8) {
                Text("No Lists Yet")
                    .font(.system(size: 22, weight: .black)).foregroundColor(slBrown)
                Text("Tap + to create your first shopping list.")
                    .font(.system(size: 14, weight: .medium)).foregroundColor(slMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ShoppingListCard
struct ShoppingListCard: View {
    let list:      ShoppingList
    var canDelete: Bool = true
    let onDelete:  () -> Void

    var body: some View {
        let icon = listIcon(from: list.emoji)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(icon.color.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon.symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(icon.color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(list.name)
                        .font(.system(size: 16, weight: .bold)).foregroundColor(slBrown)
                    HStack(spacing: 6) {
                        Text("\(list.totalItems) items")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(slMuted)
                        if list.totalItems > 0 {
                            Text("·").foregroundColor(slMuted)
                            Text("\(list.checkedItems) done")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(list.isComplete ? Color(hex: "#3D7A52")! : slMuted)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if list.isComplete && list.totalItems > 0 {
                        Text("DONE")
                            .font(.system(size: 9, weight: .heavy)).kerning(1)
                            .foregroundColor(Color(hex: "#3D7A52")!)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(hex: "#3D7A52")!.opacity(0.1))
                            .cornerRadius(20)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(slMuted)
                }
            }

            if list.totalItems > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#F5F0EB")!).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(list.isComplete ? Color(hex: "#3D7A52")! : icon.color)
                            .frame(width: geo.size.width * list.progress, height: 5)
                            .animation(.spring(response: 0.4), value: list.progress)
                    }
                }
                .frame(height: 5)
            }

            HStack {
                Text(list.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium)).foregroundColor(slMuted)
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.red.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.07)).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(slMuted.opacity(0.5))
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(slDivider, lineWidth: 1))
        .shadow(color: slBrown.opacity(0.04), radius: 6, y: 2)
    }
}

// MARK: - ShoppingListDetailView
struct ShoppingListDetailView: View {
    let listID: UUID
    @ObservedObject var vm: ShoppingListViewModel
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var showAddItem     = false
    @State private var itemToEdit:     ShoppingItem? = nil
    @State private var itemToDelete:   ShoppingItem? = nil
    @State private var showDeleteAlert = false
    @State private var showClearAlert  = false
    @State private var selectedCategory: ShoppingCategory? = nil

    private var canWrite: Bool {
        let role = authVM.profile?.role ?? ""
        return role != "Teen" && role != "Child"
    }

    private var list: ShoppingList? { vm.lists.first { $0.id == listID } }

    private var filteredItems: [ShoppingItem] {
        guard let list else { return [] }
        let items = selectedCategory == nil
            ? list.items
            : list.items.filter { $0.category == selectedCategory }
        return items.filter { !$0.isChecked } + items.filter { $0.isChecked }
    }

    private var categories: [ShoppingCategory] {
        guard let list else { return [] }
        return ShoppingCategory.allCases.filter { cat in list.items.contains { $0.category == cat } }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            slCream.ignoresSafeArea()
            VStack(spacing: 0) {
                if let list { progressHeader(list: list) }
                if categories.count > 1 { categoryFilter }
                if filteredItems.isEmpty { emptyItems }
                else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredItems) { item in
                                ShoppingItemRow(
                                    item:      item,
                                    canDelete: vm.canDeleteItem(item),
                                    canEdit:   canWrite,
                                    onToggle:  { vm.toggleItem(item, in: listID) },
                                    onEdit:    { itemToEdit = item },
                                    onDelete:  { itemToDelete = item; showDeleteAlert = true }
                                )
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 100)
                    }
                }
            }

            if canWrite {
                Button { showAddItem = true } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.25)).frame(width: 28, height: 28)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .black)).foregroundColor(.white)
                        }
                        Text("Add Item").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(Capsule().fill(slAmber).shadow(color: slAmber.opacity(0.45), radius: 16, y: 6))
                }
                .padding(.trailing, 20).padding(.bottom, 28)
            }
        }
        .navigationTitle(list?.name ?? "List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if let list, list.checkedItems > 0 {
                        Button { showClearAlert = true } label: {
                            Label("Clear Checked", systemImage: "checkmark.circle")
                        }
                        Button { vm.uncheckAll(in: listID) } label: {
                            Label("Uncheck All", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundColor(slAmber)
                }
            }
        }
        .sheet(isPresented: $showAddItem) { ShoppingItemFormSheet(listID: listID, vm: vm) }
        .sheet(item: $itemToEdit) { item in ShoppingItemFormSheet(listID: listID, vm: vm, editingItem: item) }
        .alert("Delete Item", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { if let i = itemToDelete { vm.deleteItem(i, from: listID) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Remove \"\(itemToDelete?.name ?? "")\">?") }
        .alert("Clear Checked Items", isPresented: $showClearAlert) {
            Button("Clear", role: .destructive) { vm.clearChecked(from: listID) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Remove all checked items from this list?") }
    }

    private func progressHeader(list: ShoppingList) -> some View {
        let icon = listIcon(from: list.emoji)
        return ZStack {
            LinearGradient(
                colors: [icon.color, icon.color.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.2)).frame(width: 50, height: 50)
                        Image(systemName: icon.symbol)
                            .font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(list.name)
                            .font(.system(size: 20, weight: .black)).foregroundColor(.white)
                        Text(list.totalItems == 0
                             ? "No items yet"
                             : "\(list.checkedItems) of \(list.totalItems) done")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.8))
                    }
                    Spacer()
                    if list.totalItems > 0 {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: list.progress)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.4), value: list.progress)
                            Text("\(Int(list.progress * 100))%")
                                .font(.system(size: 12, weight: .black)).foregroundColor(.white)
                        }
                        .frame(width: 52, height: 52)
                    }
                }
                .padding(.horizontal, 20)

                if list.totalItems > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.3)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 3).fill(Color.white)
                                .frame(width: geo.size.width * list.progress, height: 5)
                                .animation(.spring(response: 0.4), value: list.progress)
                        }
                    }
                    .frame(height: 5)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
        .frame(minHeight: list.totalItems > 0 ? 120 : 100)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", icon: "square.grid.2x2.fill",
                           color: slAmber, isSelected: selectedCategory == nil) {
                    withAnimation { selectedCategory = nil }
                }
                ForEach(categories) { cat in
                    filterChip(title: cat.rawValue, icon: cat.icon,
                               color: Color(hex: cat.color)!,
                               isSelected: selectedCategory == cat) {
                        withAnimation { selectedCategory = selectedCategory == cat ? nil : cat }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) { slDivider.frame(height: 1) }
    }

    private func filterChip(title: String, icon: String, color: Color,
                             isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(isSelected ? .white : slMuted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(isSelected ? color : Color(hex: "#F5F0EB")!)
            .cornerRadius(20)
            .overlay(RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? color : slDivider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyItems: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bag.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(slAmber.opacity(0.3))
            Text("No items yet").font(.system(size: 18, weight: .black)).foregroundColor(slBrown)
            Text("Tap + to add your first item.")
                .font(.system(size: 14, weight: .medium)).foregroundColor(slMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ShoppingItemRow
struct ShoppingItemRow: View {
    let item:      ShoppingItem
    var canDelete: Bool = true
    var canEdit:   Bool = true
    let onToggle:  () -> Void
    let onEdit:    () -> Void
    let onDelete:  () -> Void

    private var catColor: Color { Color(hex: item.category.color)! }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    Circle().stroke(item.isChecked ? catColor : slDivider, lineWidth: 2)
                        .frame(width: 26, height: 26)
                    if item.isChecked {
                        Circle().fill(catColor).frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black)).foregroundColor(.white)
                    }
                }
                .animation(.spring(response: 0.25), value: item.isChecked)
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(catColor.opacity(item.isChecked ? 0.06 : 0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: item.category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(item.isChecked ? catColor.opacity(0.4) : catColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 14, weight: .bold))
                    .strikethrough(item.isChecked, color: slMuted)
                    .foregroundColor(item.isChecked ? slMuted : slBrown)
                HStack(spacing: 8) {
                    if !item.displayQuantity.isEmpty {
                        Text(item.displayQuantity)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(item.isChecked ? slMuted.opacity(0.6) : slAmber)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(item.isChecked ? Color(hex: "#F5F0EB")! : slAmberBg)
                            .cornerRadius(20)
                    }
                    Text(item.category.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(item.isChecked ? slMuted.opacity(0.5) : slMuted)
                    if !item.note.isEmpty {
                        Text("· \(item.note)")
                            .font(.system(size: 11)).foregroundColor(slMuted.opacity(0.7)).lineLimit(1)
                    }
                }
            }

            Spacer()

            if canEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(slAmber)
                        .frame(width: 28, height: 28).background(slAmberBg).clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.red.opacity(0.7))
                        .frame(width: 28, height: 28).background(Color.red.opacity(0.07)).clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(item.isChecked ? Color(hex: "#F5F0EB")! : Color.white)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(item.isChecked ? slDivider : catColor.opacity(0.15), lineWidth: 1))
        .shadow(color: slBrown.opacity(item.isChecked ? 0.02 : 0.04), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.15), value: item.isChecked)
    }
}

// MARK: - NewShoppingListSheet
struct NewShoppingListSheet: View {
    @ObservedObject var vm: ShoppingListViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name          = ""
    @State private var selectedIcon  = "cart.fill"
    @State private var selectedColor = "#C8922A"
    @FocusState private var focused: Bool

    private let icons: [(symbol: String, color: String, label: String)] = [
        ("cart.fill",                   "#C8922A", "Shopping"),
        ("house.fill",                  "#3D7A52", "Home"),
        ("gift.fill",                   "#E91E63", "Gift"),
        ("heart.fill",                  "#C0392B", "Health"),
        ("fork.knife",                  "#E67E22", "Food"),
        ("tshirt.fill",                 "#9C27B0", "Clothes"),
        ("bolt.fill",                   "#FF9800", "Electronics"),
        ("cross.case.fill",             "#F44336", "Pharmacy"),
        ("book.fill",                   "#2196F3", "Books"),
        ("wrench.and.screwdriver.fill", "#607D8B", "Tools"),
        ("leaf.fill",                   "#3D7A52", "Garden"),
        ("pawprint.fill",               "#795548", "Pets"),
    ]

    private var accent: Color { Color(hex: selectedColor)! }

    var body: some View {
        NavigationStack {
            ZStack {
                slCream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        // Preview
                        VStack(spacing: 10) {
                            ZStack {
                                Circle().fill(accent.opacity(0.15)).frame(width: 80, height: 80)
                                Image(systemName: selectedIcon)
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(accent)
                            }
                            .animation(.spring(response: 0.3), value: selectedIcon)

                            Text(name.isEmpty ? "New List" : name)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(name.isEmpty ? slMuted : slBrown)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(18)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(slDivider, lineWidth: 1))

                        // Icon grid
                        VStack(alignment: .leading, spacing: 12) {
                            slLabel(icon: "square.grid.2x2.fill", text: "CHOOSE ICON")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                                spacing: 12
                            ) {
                                ForEach(icons, id: \.symbol) { item in
                                    let isSel     = selectedIcon == item.symbol
                                    let itemColor = Color(hex: item.color)!
                                    Button {
                                        withAnimation(.spring(response: 0.25)) {
                                            selectedIcon  = item.symbol
                                            selectedColor = item.color
                                        }
                                    } label: {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(isSel ? itemColor : itemColor.opacity(0.1))
                                                .frame(width: 44, height: 44)
                                            Image(systemName: item.symbol)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(isSel ? .white : itemColor)
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isSel ? itemColor : Color.clear, lineWidth: 2)
                                        )
                                        .scaleEffect(isSel ? 1.08 : 1.0)
                                        .animation(.spring(response: 0.25), value: isSel)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(slDivider, lineWidth: 1))

                        // Name field
                        VStack(alignment: .leading, spacing: 10) {
                            slLabel(icon: "tag.fill", text: "LIST NAME")
                            TextField("e.g. Weekly Groceries", text: $name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(slBrown)
                                .focused($focused)
                        }
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(focused ? accent.opacity(0.6) : slDivider,
                                    lineWidth: focused ? 2 : 1))
                        .animation(.easeInOut(duration: 0.15), value: focused)

                        // Create button
                        Button {
                            vm.addList(name: name, emoji: "sf:\(selectedIcon):\(selectedColor)")
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 18))
                                Text("Create List").font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color(hex: "#C5C0B8")! : accent)
                            .cornerRadius(16)
                            .shadow(color: name.isEmpty ? .clear : accent.opacity(0.4), radius: 10, y: 4)
                            .animation(.easeInOut(duration: 0.15), value: name.isEmpty)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(accent)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func slLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundColor(slMuted)
            Text(text).font(.system(size: 9, weight: .heavy)).kerning(1.3).foregroundColor(slMuted)
        }
    }
}

// MARK: - ShoppingItemFormSheet
struct ShoppingItemFormSheet: View {
    let listID: UUID
    @ObservedObject var vm: ShoppingListViewModel
    var editingItem: ShoppingItem? = nil
    @Environment(\.dismiss) var dismiss

    @State private var name:     String           = ""
    @State private var quantity: String           = "1"
    @State private var unit:     String           = ""
    @State private var category: ShoppingCategory = .other
    @State private var note:     String           = ""
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { editingItem != nil }
    private var isValid:   Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                slCream.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {

                        fieldCard(icon: "tag.fill", label: "ITEM NAME") {
                            TextField("e.g. Whole Milk", text: $name)
                                .font(.system(size: 16, weight: .semibold)).foregroundColor(slBrown)
                                .focused($nameFocused)
                        }

                        HStack(spacing: 12) {
                            fieldCard(icon: "number", label: "QTY") {
                                TextField("1", text: $quantity)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 16, weight: .semibold)).foregroundColor(slBrown)
                            }
                            fieldCard(icon: "scalemass.fill", label: "UNIT") {
                                TextField("kg, L, pcs…", text: $unit)
                                    .font(.system(size: 16, weight: .semibold)).foregroundColor(slBrown)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            slFormLabel(icon: "square.grid.2x2.fill", text: "CATEGORY")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                                spacing: 8
                            ) {
                                ForEach(ShoppingCategory.allCases) { cat in
                                    let isSel     = category == cat
                                    let catColor  = Color(hex: cat.color)!
                                    Button { category = cat } label: {
                                        VStack(spacing: 4) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(isSel ? catColor : catColor.opacity(0.1))
                                                    .frame(width: 44, height: 44)
                                                Image(systemName: cat.icon)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(isSel ? .white : catColor)
                                            }
                                            Text(cat.rawValue.components(separatedBy: " ").first ?? cat.rawValue)
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(isSel ? catColor : slMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16).background(Color.white).cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(slDivider, lineWidth: 1))

                        fieldCard(icon: "note.text", label: "NOTE (OPTIONAL)") {
                            TextField("Brand, size, or any detail…", text: $note, axis: .vertical)
                                .lineLimit(2...3).font(.system(size: 14)).foregroundColor(slBrown)
                        }

                        Button { save() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isEditing ? "checkmark.circle.fill" : "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text(isEditing ? "Save Changes" : "Add Item")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 17)
                            .background(isValid ? slAmber : Color(hex: "#C5C0B8")!)
                            .cornerRadius(16)
                            .shadow(color: isValid ? slAmber.opacity(0.4) : .clear, radius: 10, y: 4)
                            .animation(.easeInOut(duration: 0.15), value: isValid)
                        }
                        .disabled(!isValid)
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 40)
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(slAmber)
                }
            }
            .onAppear {
                if let item = editingItem {
                    name = item.name; quantity = item.quantity
                    unit = item.unit; category = item.category; note = item.note
                }
                nameFocused = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        if isEditing, var updated = editingItem {
            updated.name = name.trimmingCharacters(in: .whitespaces)
            updated.quantity = quantity; updated.unit = unit
            updated.category = category; updated.note = note
            vm.updateItem(updated, in: listID)
        } else {
            vm.addItem(to: listID, name: name, quantity: quantity,
                       unit: unit, category: category, note: note)
        }
        dismiss()
    }

    @ViewBuilder
    private func fieldCard<C: View>(icon: String, label: String,
                                    @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            slFormLabel(icon: icon, text: label)
            content()
        }
        .padding(16).background(Color.white).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(slDivider, lineWidth: 1))
    }

    private func slFormLabel(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundColor(slMuted)
            Text(text).font(.system(size: 9, weight: .heavy)).kerning(1.3).foregroundColor(slMuted)
        }
    }
}

#Preview { ShoppingListsView() }
