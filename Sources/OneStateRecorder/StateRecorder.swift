import SwiftUI
import OneState
#if canImport(OneStateExtensions)
import OneStateExtensions
#endif

//TODO: move to separate package (and repo)

public extension View {
    func installStateRecorder<State>(for store: Store<State>, alignment: Alignment = .bottomTrailing) -> some View {
        modifier(StateRecorderModifier<State>(alignment: alignment))
            .modelEnvironment(store)
    }
}

struct StateRecorderModifier<StoreState>: ViewModifier {
    let alignment: Alignment
    @Store var store = StateRecorderModel<StoreState>.State()

    func body(content: Content) -> some View {
        ZStack(alignment: alignment) {
            content
            StateRecorderView(model: $store.viewModel(.init()), alignment: alignment)
        }
    }
}

struct StateRecorderModel<StoreState>: ViewModel {
    struct State {
        var updates: [Update] = []
        var newUpdates: [Update] = []
        var currentUpdate: Update?

        typealias Update = StateUpdate<StoreState, StoreState>
    }
    
    @ModelEnvironment private var store: Store<StoreState>
    @ModelState private var state: State
        
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
            $store.stateOverride.wrappedValue = update
        }

        onChange(of: \.currentUpdate, to: nil) {
            state.updates.append(contentsOf: state.newUpdates)
            state.newUpdates.removeAll()
        }
    }
    
    func startStateOverrideTapped() {
        state.currentUpdate = state.updates.last
    }

    func stopStateOverrideTapped() {
        state.currentUpdate = nil
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
        $state.binding(\.progress)
    }
    
#if canImport(OneStateExtensions)
    func printDiffTapped() {
        state.currentUpdate?.printDiff()
    }
#endif
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
        currentUpdate != nil
    }

    var maxIndex: Int {
        max(0, updates.count - 1)
    }
    
    var updateBounds: ClosedRange<Int> {
        0...maxIndex
    }
}
    
struct StateRecorderView<StoreState>: View {
    @Model var model: StateRecorderModel<StoreState>
    let alignment: Alignment

    var body: some View {
        ZStack(alignment: alignment) {
            if !model.isOverridingState {
                Button {
                    withAnimation {
                        model.startStateOverrideTapped()
                    }
                } label: {
                    Image(systemName: "pause.circle")
                        .padding(6)
                        .contentShape(Rectangle())
                        .recorderBackground(edges: .all)
                        .cornerRadius(8)
                }
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }

            if model.isOverridingState {
                if #available(iOS 14, macOS 11, *) {
                    Color.gray.opacity(0.1)
                        .ignoresSafeArea(.all, edges: .all)
                        .transition(.opacity)
                } else {
                    Color.gray.opacity(0.1)
                        .transition(.opacity)
                }

                VStack {
                    HStack {
                    //TODO: Add play button to replay using timestamp and optional speed up (x1, x2) or slow down
//                        Button {
//                        } label: {
//                            Image(systemName: model.isOverridingState ? "play.circle" : "pause.circle")
//                        }
                              
#if canImport(OneStateExtensions)
                        Button {
                            model.printDiffTapped()
                        } label: {
                            Image(systemName: "printer")
                        }
#endif
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
                            withAnimation {
                                model.stopStateOverrideTapped()
                            }
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    
                    Slider(value: model.progress)
                }
                .padding([.top, .horizontal], 8)
                .recorderBackground(edges: .all)
                .transition(.move(edge: .bottom))
            }
        }
        .buttonStyle(.plain)
        .imageScale(.large)
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
