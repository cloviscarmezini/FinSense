// Sources/FinSense/Views/SyncStatusIndicatorView.swift
import SwiftUI

public struct SyncStatusIndicatorView: View {
    @ObservedObject public var syncService: CloudSyncService
    @ObservedObject public var authService = AuthService.shared
    @State private var isPopoverPresented: Bool = false

    public init(syncService: CloudSyncService) {
        self.syncService = syncService
    }

    public var body: some View {
        // Exibe o ícone APENAS se autenticado E com sync ativado
        if authService.isAuthenticated && syncService.isEnabled {
            Button {
                isPopoverPresented.toggle()
            } label: {
                Group {
                    if syncService.isSyncing {
                        ZStack {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#F59E0B").opacity(0.18))
                            Image(systemName: "icloud")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: "#F59E0B"))
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.62)
                                .tint(Color(hex: "#F59E0B"))
                        }
                    } else {
                        Image(systemName: syncService.syncStatus.iconSymbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(syncService.isSyncing ? "Sincronizando com o servidor (\(Int(round(syncService.syncProgress * 100)))%)..." : syncService.syncStatus.statusDescription)
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                SyncDetailPopoverContent(syncService: syncService)
            }
        }
    }

    private var iconColor: Color {
        switch syncService.syncStatus {
        case .disabled: return .secondary.opacity(0.6)
        case .synced: return Color(hex: "#10B981")
        case .syncing: return Color(hex: "#F59E0B")
        case .outOfSync: return Color(hex: "#F59E0B")
        case .authError: return Color(hex: "#EF4444")
        }
    }
}

public struct SyncDetailPopoverContent: View {
    @ObservedObject public var syncService: CloudSyncService

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if syncService.isSyncing {
                    ZStack {
                        Image(systemName: "icloud.fill")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "#F59E0B").opacity(0.18))
                        Image(systemName: "icloud")
                            .font(.title2)
                            .foregroundStyle(Color(hex: "#F59E0B"))
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .tint(Color(hex: "#F59E0B"))
                    }
                } else {
                    Image(systemName: syncService.syncStatus.iconSymbol)
                        .font(.title2)
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sincronização em Nuvem")
                        .font(.headline)
                    if syncService.isSyncing {
                        Text("Sincronizando \(Int(round(syncService.syncProgress * 100)))%")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#F59E0B"))
                    } else if let last = syncService.lastSyncDate, case .synced = syncService.syncStatus {
                        Text("Sincronizado em \(BRLFormatters.dateTime(last))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(syncService.syncStatus.statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if syncService.isSyncing {
                ProgressView(value: max(0.05, syncService.syncProgress), total: 1.0)
                    .progressViewStyle(.linear)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Alterações locais pendentes:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(syncService.pendingMutationsCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                }

                if let lastSync = syncService.lastSyncDate {
                    HStack {
                        Text("Última sincronização:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(BRLFormatters.dateTime(lastSync))
                            .font(.caption)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    syncService.performSync()
                } label: {
                    Label("Sincronizar Agora", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(syncService.isSyncing || syncService.isSeeding || !syncService.canSync)
                .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var iconColor: Color {
        switch syncService.syncStatus {
        case .disabled: return .secondary.opacity(0.6)
        case .synced: return Color(hex: "#10B981")
        case .syncing: return Color(hex: "#F59E0B")
        case .outOfSync: return Color(hex: "#F59E0B")
        case .authError: return Color(hex: "#EF4444")
        }
    }
}
