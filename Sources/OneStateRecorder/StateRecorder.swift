import SwiftUI
import Combine
import OneState
import CustomDump

public extension View {
    @MainActor func installStateRecorder<M: Model>(for store: Store<M>, isPaused: Binding<Bool>? = nil, edge: Edge = .bottom) -> some View where M.State: Sendable {
        modifier(StateRecorderModifier<M>(isPaused: isPaused, edge: edge, store: store))
    }
}

struct StateRecorderModifier<M: Model>: ViewModifier where M.State: Sendable {
    let isPaused: Binding<Bool>?
    let edge: Edge

    @StateObject var model: StateRecorderModel<M>

    init(isPaused: Binding<Bool>?, edge: Edge, store: Store<M>) {
        self.isPaused = isPaused
        self.edge = edge
        _model = .init(wrappedValue: StateRecorderModel(store: store))
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
    typealias State = M.State
    @Published var updates: [State] = []
    @Published var newUpdates: [State] = []
    @Published var updateIndex: Int?

    var updatesCount: Int { updates.count }

    var cancellables = Set<AnyCancellable>()

    init(store: Store<M>) {
        self.store = store

        updates.append(store.state)

        store.stateDidUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] in
                if self.isOverridingState {
                    self.newUpdates.append(store.state)
                } else {
                    self.updates.append(store.state)
                }
            }
            .store(in: &cancellables)

        let updateIndex = $updateIndex
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)

        updateIndex.sink { index in
            store.stateOverride = index.map { self.updates[$0] }
        }
        .store(in: &cancellables)

        updateIndex.filter { $0 == nil }.sink { [unowned self] _ in
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
        guard let state, index > 0 else { return }
        let previous = updates[index - 1]
        guard let diff = diff(previous, state) else { return }
        Swift.print("State did update:\n" + diff)
    }
}

extension StateRecorderModel {
    var index: Int {
        get { updateIndex ?? 0 }
        set { updateIndex = max(0, min(updatesCount-1, newValue)) }
    }

    var state: State? {
        updateIndex.map { updates[$0] }
    }

    var progress: Double {
        get {
            updates.isEmpty ? 1 : Double(index)/Double(maxIndex)
        }
        set {
            updateIndex = updates.isEmpty ? 0 : Int(round(newValue*Double(maxIndex)))
        }
    }

    var canStepBackward: Bool { index == 0 }
    var canStepForward: Bool { index == maxIndex }

    var isOverridingState: Bool {
        get {
            updateIndex != nil
        }
        set {
            guard newValue != isOverridingState else { return }

            if newValue {
                updateIndex = updatesCount - 1
            } else {
                updateIndex = nil
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

