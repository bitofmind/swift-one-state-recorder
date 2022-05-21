import SwiftUI
import Combine
import OneState

public extension View {
    func installStateRecorder<Model: ViewModel>(for store: Store<Model>, isPaused: Binding<Bool>? = nil, edge: Edge = .bottom, printDiff: ((StateUpdate<Model.State, Model.State>) -> Void)? = nil) -> some View {
        modifier(StateRecorderModifier<Model>(isPaused: isPaused, edge: edge))
            .modelEnvironment(store)
            .modelEnvironment(printDiff)
    }
}

struct StateRecorderModifier<Model: ViewModel>: ViewModifier {
    let isPaused: Binding<Bool>?
    let edge: Edge

    @Store<StateRecorderModel<Model>> var store = .init()

    func body(content: Content) -> some View {
        ZStack(alignment: edge.alignment) {
            content
            StateRecorderContainerView(model: $store.model, isPaused: isPaused, edge: edge)
        }
    }
}

struct StateRecorderModel<Model: ViewModel>: ViewModel {
    typealias StoreState = Model.State

    struct State: Equatable {
        var updates: [Update] = []
        var newUpdates: [Update] = []
        var currentUpdate: Update?

        typealias Update = StateUpdate<StoreState, StoreState>
    }

    @ModelEnvironment var store: Store<Model>
    @ModelEnvironment var printDiff: ((StateUpdate<StoreState, StoreState>) -> Void)?

    @ModelState var state: State

    func onAppear() {
        state.updates.append(store.latestUpdate)

        onReceive(store.stateDidUpdatePublisher) { update in
            if state.isOverridingState {
                state.newUpdates.append(update)
            } else {
                state.updates.append(update)
            }
        }

        onChange(of: \.currentUpdate) { update in
            store.stateOverride = update
        }

        onChange(of: \.currentUpdate, to: nil) {
            state.updates.append(contentsOf: state.newUpdates)
            state.newUpdates.removeAll()
        }
    }

    func startStateOverrideTapped() {
        state.isOverridingState = true
    }

    func stopStateOverrideTapped() {
        state.isOverridingState = false
    }

    func stepForwardTapped() {
        state.index += 1
    }

    func longStepForwardTapped() {
        state.index += 5
    }

    func stepBackwardTapped() {
        state.index -= 1
    }

    func longStepBackwardTapped() {
        state.index -= 5
    }

    var progress: Binding<Double> {
        Binding($state).progress
    }

    func printDiffTapped() {
        guard let update = state.currentUpdate else { return }

        if let printDiff = printDiff {
            printDiff(update)
        } else {
            print("previous", update.previous)
            print("current", update.current)
        }
    }
}

extension StateRecorderModel.State {
    var index: Int {
        get {
            guard let update = currentUpdate,
                  let index = updates.firstIndex(where: { $0 == update }) else {
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

struct StateRecorderContainerView<VM: ViewModel>: View {
    @Model var model: StateRecorderModel<VM>
    let isPaused: Binding<Bool>?
    let edge: Edge
    @State var _isPaused = false
    @State var prev = false

    var body: some View {
        let isPaused = isPaused?.wrappedValue ?? _isPaused

        ZStack(alignment: edge.alignment) {
            if model.isOverridingState {
                if #available(iOS 14, macOS 11, *) {
                    Color.gray.opacity(0.1)
                        .ignoresSafeArea(.all, edges: .all)
                        .transition(.opacity)
                } else {
                    Color.gray.opacity(0.1)
                        .transition(.opacity)
                }

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
        .onReceive(model.stateDidUpdatePublisher) { update in
            guard let isPaused = update.isOverridingState else { return }
            self.isPaused?.wrappedValue = isPaused
        }
    }
}

struct StateRecorderView<VM: ViewModel>: View {
    @Model var model: StateRecorderModel<VM>

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

                Text("\(model.index)/\(model.updates.count-1)")

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

            Slider(value: model.progress)
        }
        .padding([.top, .horizontal], 8)
    }
}

extension View {
    @ViewBuilder
    func recorderBackground(edges: Edge.Set) -> some View {
        if #available(iOS 15, macOS 12, *) {
            background(Rectangle().fill(.ultraThinMaterial).opacity(0.95).ignoresSafeArea(edges: edges))
        } else if #available(iOS 14, macOS 11, *) {
            background(Color.gray.opacity(0.5).ignoresSafeArea(edges: edges))
        } else {
            background(Color.gray.opacity(0.5))
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

