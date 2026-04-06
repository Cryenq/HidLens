import SwiftUI
import HidLensCore

struct ContentView: View {
    @StateObject private var deviceListVM = DeviceListViewModel()
    @State private var selectedDeviceID: UInt64?
    @AppStorage("showAllDevices") private var showAllDevices = false

    var body: some View {
        NavigationSplitView {
            DeviceListView(viewModel: deviceListVM, selection: $selectedDeviceID)
        } detail: {
            if let id = selectedDeviceID,
               let device = deviceListVM.devices.first(where: { $0.id == id }) {
                DeviceDetailView(device: device)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a controller")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Connect a DualShock 4 via USB to get started")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        .navigationTitle("HidLens")
        .onChange(of: showAllDevices) { _ in
            deviceListVM.showAllDevices = showAllDevices
            deviceListVM.applyFilter()
        }
    }
}
