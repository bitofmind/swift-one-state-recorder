import SwiftUI
import Combine
import OneState

public extension View {
    @MainActor func installStateRecorder<M: Model>(for store: Store<M>, isPaused: Binding<Bool>? = nil, edge: Edge = .bottom, printDiff: (@Sendable (StateUpdate<M.State>) -> Void)? = nil) -> some View where M.State: Sendable {
        modifier(StateRecorderModifier<M>(isPaused: isPaused, edge: edge, store: store, printDiff: printDiff))
    }
}

struct StateRecorderModifier<M: Model>: ViewModifier where M.State: Sendable {
    let isPaused: Binding<Bool>?
    let edge: Edge

    @StateObject var model: StateRecorderModel<M>

    init(isPaused: Binding<Bool>?, edge: Edge, store: Store<M>, printDiff: (@Sendable (StateUpdate<M.State>) -> Void)?) {
        self.isPaused = isPaused
        self.edge = edge
        _model = .init(wrappedValue: StateRecorderModel(store: store, printDiff: printDiff))
    }

    func body(content: Content) -> some View {
        ZStack(alignment: edge.alignment) {
            content
            StateRecorderContainerView(model: model, isPaused: isPaused, edge: edge)
        }
    }
}

class StateRecorderModel<M: Model>: ObservableObject where M.State: Sendable {
    let store: Store<M>
    let printDiff: ((Update) -> Void)?

    typealias Update = StateUpdate<M.State>
    @Published var updates: [Update] = []
    @Published var newUpdates: [Update] = []
    @Published var currentUpdate: Update?

    var updatesCount: Int { updates.count }

    var cancellables = Set<AnyCancellable>()

    init(store: Store<M>, printDiff: ((Update) -> Void)?) {
        self.store = store
        self.printDiff = printDiff

        updates.append(store.latestUpdate)

        store.stateUpdatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] update in
                if self.isOverridingState {
                    self.newUpdates.append(update)
                } else {
                    self.updates.append(update)
                }
            }
            .store(in: &cancellables)

        let update = $currentUpdate
            .removeDuplicates(by: { $0?.id == $1?.id })
            .dropFirst()
            .receive(on: DispatchQueue.main)

        update.sink {
            store.stateOverride = $0
        }
        .store(in: &cancellables)

        $currentUpdate
            .removeDuplicates(by: { $0?.id == $1?.id })
            .dropFirst()
            .sink {
                store.stateOverride = $0
            }
            .store(in: &cancellables)

        update.filter { $0 == nil }.sink { [unowned self] _ in
            self.updates.append(contentsOf: self.newUpdates)
            self.newUpdates.removeAll()
        }
        .store(in: &cancellables)
    }
}

extension StateRecorderModel {
    func startStateOverrideTapped() {
        isOverridingState = true
    }

    func stopStateOverrideTapped() {
        isOverridingState = false
    }

    func stepForwardTapped() {
        index += 1
    }

    func longStepForwardTapped() {
        index += 5
    }

    func stepBackwardTapped() {
        index -= 1
    }

    func longStepBackwardTapped() {
        index -= 5
    }

    var progressBinding: Binding<Double> {
        .init {
            self.progress
        } set: {
            self.progress = $0
        }
    }

    func printDiffTapped() {
        guard let update = currentUpdate else { return }

        if let printDiff = printDiff {
            printDiff(update)
        } else {
            print("previous", update.previous)
            print("current", update.current)
        }
    }
}

extension StateRecorderModel {
    var index: Int {
        get {
            guard let update = currentUpdate,
                  let index = updates.firstIndex(where: { $0.id == update.id }) else {
                      return max(0, updates.count - 1)
                  }

            return index
        }
        set {
            currentUpdate = updates[max(0, min(newValue, maxIndex))]
        }
    }

    var progress: Double {
        get {
            updates.isEmpty ? 1 : Double(index)/Double(maxIndex)
        }
        set {
            index = updates.isEmpty ? 0 : Int(round(newValue*Double(maxIndex)))
        }
    }

    var canStepBackward: Bool { index == 0 }
    var canStepForward: Bool { index == maxIndex }

    var isOverridingState: Bool {
        get {
            currentUpdate != nil
        }
        set {
            guard newValue != isOverridingState else { return }

            if newValue {
                currentUpdate = updates.last
            } else {
                currentUpdate = nil
            }
        }
    }

    var maxIndex: Int {
        max(0, updates.count - 1)
    }

    var updateBounds: ClosedRange<Int> {
        0...maxIndex
    }
}

struct StateRecorderContainerView<M: Model>: View where M.State: Sendable {
    @ObservedObject var model: StateRecorderModel<M>
    let isPaused: Binding<Bool>?
    let edge: Edge
    @State var _isPaused = false
    @State var prev = false

    var body: some View {
        let isPaused = isPaused?.wrappedValue ?? _isPaused

        ZStack(alignment: edge.alignment) {
            if model.isOverridingState {
                Color.gray.opacity(0.1)
                    .ignoresSafeArea(.all, edges: .all)
                    .transition(.opacity)

                StateRecorderView(model: model)
                    .recorderBackground(edges: .all)
                    .transition(.move(edge: edge))

            } else if self.isPaused == nil {
                Button {
                    model.startStateOverrideTapped()
                } label: {
                    Image(systemName: "pause.circle")
                        .padding(6)
                        .contentShape(Rectangle())
                        .recorderBackground(edges: .all)
                        .cornerRadius(8)
                }
                .transition(.move(edge: edge))
                .zIndex(1)
            }
        }
        .animation(.default, value: model.isOverridingState)
        .buttonStyle(.plain)
        .imageScale(.large)
        .onReceive(Just(isPaused)) { isPaused in
            guard isPaused != prev else { return }
            prev = isPaused

            if isPaused {
                model.startStateOverrideTapped()
            } else {
                model.stopStateOverrideTapped()
            }
        }
        .onChange(of: model.isOverridingState) { isPaused in
            self.isPaused?.wrappedValue = isPaused
        }
    }
}

struct StateRecorderView<M: Model>: View where M.State: Sendable {
    @ObservedObject var model: StateRecorderModel<M>

    var body: some View {
        VStack {
            HStack {
                //TODO: Add play button to replay using timestamp and optional speed up (x1, x2) or slow down
                //                        Button {
                //                        } label: {
                //                            Image(systemName: model.isOverridingState ? "play.circle" : "pause.circle")
                //                        }

                Button {
                    model.printDiffTapped()
                } label: {
                    Image(systemName: "printer")
                }

                Spacer()

                Button {
                    model.longStepBackwardTapped()
                } label: {
                    Image(systemName: "chevron.backward.2")
                }
                .disabled(model.canStepBackward)


                Button {
                    model.stepBackwardTapped()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(model.canStepBackward)

                Text("\(model.index)/\(model.updatesCount - 1)")

                Button {
                    model.stepForwardTapped()
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .disabled(model.canStepForward)

                Button {
                    model.longStepForwardTapped()
                } label: {
                    Image(systemName: "chevron.forward.2")
                }
                .disabled(model.canStepForward)

                Spacer()

                Button {
                    model.stopStateOverrideTapped()
                } label: {
                    Image(systemName: "xmark.circle")
                }
            }

            Slider(value: model.progressBinding)
        }
        .padding([.top, .horizontal], 8)
    }
}

extension View {
    @ViewBuilder
    func recorderBackground(edges: Edge.Set) -> some View {
        if #available(iOS 15, macOS 12, *) {
            background(Rectangle().fill(.ultraThinMaterial).opacity(0.95).ignoresSafeArea(edges: edges))
        } else {
            background(Color.gray.opacity(0.5).ignoresSafeArea(edges: edges))
        }
    }
}

extension Edge {
    var alignment: Alignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

