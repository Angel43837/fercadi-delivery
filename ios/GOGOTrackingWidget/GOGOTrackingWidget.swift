//
//  GOGOTrackingWidget.swift
//  Widget de pantalla de inicio para GOGO Food.
//  Muestra el estado del pedido activo del cliente, con un mini-mapa (tamaño
//  mediano) renderizado via MKMapSnapshotter con timeout: si Apple Maps no
//  responde a tiempo (com.apple.locationd.GeoMapTilesPreloaderServiceDownload
//  puede diferir la descarga de tiles en segundo plano), se cae al diseño de
//  solo texto en vez de mostrar el ícono de error de MapKit.
//

import SwiftUI
import WidgetKit
import MapKit
import UIKit

private let appGroupId = "group.com.fercadi.app"
private let mapSnapshotTimeout: TimeInterval = 4.0
private let mapSnapshotSize = CGSize(width: 342, height: 162)

// Reintenta este widget de nuevo en ~15 min. iOS decide el momento real
// (mismo tipo de límite de energía que la descarga de tiles del mapa) — no
// hay garantía de que sea exacto, pero permite que el widget se refresque
// solo sin que el usuario abra la app.
private let widgetReloadInterval: TimeInterval = 15 * 60

private let supabaseUrl = "https://mmjzyqvjdwhzefbaiums.supabase.co"
private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1tanp5cXZqZHdoemVmYmFpdW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg4NzMyMzAsImV4cCI6MjA5NDQ0OTIzMH0.5RC11kFCcKtPCeHFarByZDc9zzVBBvsZPYlI5Ed-PNM"

// Consulta directo a Supabase (sin pasar por Flutter) para que el widget se
// pueda refrescar aunque la app esté cerrada. Usa el token de sesión del
// último usuario logueado (guardado por tracking_screen.dart); si no hay
// token o la consulta falla, simplemente deja los datos en caché tal cual.
private func refreshOrderFromSupabase(completion: @escaping (Bool) -> Void) {
  let data = UserDefaults(suiteName: appGroupId)
  guard let orderId = data?.string(forKey: "orderId"), !orderId.isEmpty else {
    completion(false)
    return
  }
  let token = data?.string(forKey: "authToken") ?? supabaseAnonKey

  var urlString = "\(supabaseUrl)/rest/v1/orders"
  urlString += "?id=eq.\(orderId)&select=status,current_lat,current_lng"
  guard let url = URL(string: urlString) else {
    completion(false)
    return
  }

  var request = URLRequest(url: url, timeoutInterval: 6.0)
  request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

  URLSession.shared.dataTask(with: request) { responseData, _, error in
    guard error == nil, let responseData = responseData,
          let rows = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]],
          let row = rows.first,
          let status = row["status"] as? String else {
      completion(false)
      return
    }

    let stillActive = status != "delivered" && status != "cancelled"
    let stepIndex = status == "accepted" ? 1 : (status == "delivering" ? 2 : 0)
    let statusLabel = ["Pedido recibido", "Repartidor va al restaurante",
                        "Repartidor en camino"][min(stepIndex, 2)]

    data?.set(stillActive, forKey: "hasActiveOrder")
    if stillActive {
      data?.set(statusLabel, forKey: "statusText")
      data?.set(stepIndex, forKey: "stepIndex")
      if let lat = row["current_lat"] as? Double, let lng = row["current_lng"] as? Double {
        data?.set(lat, forKey: "motoLat")
        data?.set(lng, forKey: "motoLng")
      }
    } else {
      data?.set(3, forKey: "stepIndex")
    }
    completion(true)
  }.resume()
}

struct GOGOTrackingProvider: TimelineProvider {
  func placeholder(in context: Context) -> GOGOTrackingEntry {
    GOGOTrackingEntry(date: Date(), hasOrder: true,
                       restaurantName: "Pollo Feliz", statusText: "En camino", mapImageData: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (GOGOTrackingEntry) -> Void) {
    buildEntry(completion: completion)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GOGOTrackingEntry>) -> Void) {
    refreshOrderFromSupabase { _ in
      buildEntry { entry in
        let policy: TimelineReloadPolicy = entry.hasOrder
          ? .after(Date().addingTimeInterval(widgetReloadInterval))
          : .never
        completion(Timeline(entries: [entry], policy: policy))
      }
    }
  }

  private func buildEntry(completion: @escaping (GOGOTrackingEntry) -> Void) {
    let data = UserDefaults(suiteName: appGroupId)
    let hasOrder = data?.bool(forKey: "hasActiveOrder") ?? false
    let restaurantName = data?.string(forKey: "restaurantName") ?? ""
    let statusText = data?.string(forKey: "statusText") ?? ""

    func coord(_ latKey: String, _ lngKey: String) -> CLLocationCoordinate2D? {
      guard let lat = data?.object(forKey: latKey) as? Double,
            let lng = data?.object(forKey: lngKey) as? Double else { return nil }
      return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    guard hasOrder,
          let r = coord("restaurantLat", "restaurantLng"),
          let c = coord("customerLat", "customerLng"),
          let m = coord("motoLat", "motoLng") else {
      completion(GOGOTrackingEntry(date: Date(), hasOrder: hasOrder,
                                    restaurantName: restaurantName, statusText: statusText,
                                    mapImageData: nil))
      return
    }

    renderMapSnapshot(restaurantCoord: r, customerCoord: c, motoCoord: m) { imageData in
      completion(GOGOTrackingEntry(date: Date(), hasOrder: hasOrder,
                                    restaurantName: restaurantName, statusText: statusText,
                                    mapImageData: imageData))
    }
  }
}

// Renderiza el mapa + pines a una imagen usando la API imperativa (con manejo de
// error/timeout real), en vez del `Map` declarativo de SwiftUI que no expone
// ningún hook para saber si falló la carga de tiles.
private func renderMapSnapshot(
  restaurantCoord: CLLocationCoordinate2D,
  customerCoord: CLLocationCoordinate2D,
  motoCoord: CLLocationCoordinate2D,
  completion: @escaping (Data?) -> Void
) {
  let lats = [restaurantCoord.latitude, customerCoord.latitude, motoCoord.latitude]
  let lngs = [restaurantCoord.longitude, customerCoord.longitude, motoCoord.longitude]
  let center = CLLocationCoordinate2D(
    latitude: (lats.min()! + lats.max()!) / 2,
    longitude: (lngs.min()! + lngs.max()!) / 2
  )
  let span = MKCoordinateSpan(
    latitudeDelta: max((lats.max()! - lats.min()!) * 3.2, 0.035),
    longitudeDelta: max((lngs.max()! - lngs.min()!) * 3.2, 0.035)
  )

  let options = MKMapSnapshotter.Options()
  options.region = MKCoordinateRegion(center: center, span: span)
  options.size = mapSnapshotSize
  options.scale = 3.0
  options.showsBuildings = false

  let snapshotter = MKMapSnapshotter(options: options)

  var didFinish = false
  let finishOnce: (Data?) -> Void = { imageData in
    if !didFinish {
      didFinish = true
      completion(imageData)
    }
  }

  // iOS puede diferir la descarga de tiles en segundo plano (política de
  // energía de dasd) — sin este timeout, el widget se queda esperando
  // indefinidamente y muestra el ícono de error nativo de MapKit.
  DispatchQueue.main.asyncAfter(deadline: .now() + mapSnapshotTimeout) {
    snapshotter.cancel()
    finishOnce(nil)
  }

  snapshotter.start(with: .main) { snapshot, error in
    guard let snapshot = snapshot, error == nil else {
      finishOnce(nil)
      return
    }
    let composed = UIGraphicsImageRenderer(size: mapSnapshotSize).image { _ in
      snapshot.image.draw(at: .zero)

      func drawPin(at coordinate: CLLocationCoordinate2D, color: UIColor) {
        let point = snapshot.point(for: coordinate)
        let radius: CGFloat = 7
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                           width: radius * 2, height: radius * 2)
        let path = UIBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        UIColor.white.setStroke()
        path.lineWidth = 2
        path.stroke()
      }

      drawPin(at: restaurantCoord, color: .darkGray)
      drawPin(at: motoCoord, color: UIColor(red: 244 / 255, green: 81 / 255, blue: 12 / 255, alpha: 1))
      drawPin(at: customerCoord, color: .systemGreen)
    }
    finishOnce(composed.pngData())
  }
}

struct GOGOTrackingEntry: TimelineEntry {
  let date: Date
  let hasOrder: Bool
  let restaurantName: String
  let statusText: String
  let mapImageData: Data?
}

extension View {
  // iOS 17+ exige containerBackground; en versiones anteriores se usa background() normal.
  @ViewBuilder
  func widgetBackground(_ color: Color) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(color, for: .widget)
    } else {
      background(color)
    }
  }
}

private struct StatusFooter: View {
  let restaurantName: String
  let statusText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(restaurantName)
        .font(.subheadline)
        .fontWeight(.bold)
        .foregroundColor(.white)
        .lineLimit(1)
      Text(statusText)
        .font(.caption)
        .foregroundColor(.white.opacity(0.85))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct EmptyOrderView: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "bag")
        .font(.title2)
        .foregroundColor(.white.opacity(0.8))
      Text("Sin pedidos activos")
        .font(.caption)
        .foregroundColor(.white.opacity(0.8))
        .multilineTextAlignment(.center)
    }
    .padding()
  }
}

struct GOGOTrackingWidgetEntryView: View {
  var entry: GOGOTrackingProvider.Entry
  @Environment(\.widgetFamily) private var family
  private let orange = Color(red: 244 / 255, green: 81 / 255, blue: 12 / 255)

  var body: some View {
    Group {
      if entry.hasOrder {
        if family == .systemMedium, let data = entry.mapImageData, let uiImage = UIImage(data: data) {
          ZStack(alignment: .bottomLeading) {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFill()
            LinearGradient(
              colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
              startPoint: .bottom, endPoint: .top
            )
            .frame(height: 60)
            .frame(maxHeight: .infinity, alignment: .bottom)
            StatusFooter(restaurantName: entry.restaurantName, statusText: entry.statusText)
              .padding(10)
          }
        } else {
          VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "bicycle")
              .font(.title2)
              .foregroundColor(.white)
            Spacer()
            StatusFooter(restaurantName: entry.restaurantName, statusText: entry.statusText)
          }
          .padding()
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
      } else {
        EmptyOrderView()
      }
    }
    .widgetBackground(orange)
  }
}

struct GOGOTrackingWidget: Widget {
  let kind: String = "GOGOTrackingWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: GOGOTrackingProvider()) { entry in
      GOGOTrackingWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("GOGO Food")
    .description("Muestra el estado de tu pedido activo, con mapa en el tamaño mediano.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct GOGOTrackingWidget_Previews: PreviewProvider {
  static var previews: some View {
    GOGOTrackingWidgetEntryView(
      entry: GOGOTrackingEntry(date: Date(), hasOrder: true,
                                restaurantName: "Pollo Feliz", statusText: "En camino",
                                mapImageData: nil)
    )
    .previewContext(WidgetPreviewContext(family: .systemMedium))
  }
}

// ── Segundo widget: tarjeta de pasos (Recibido / Preparando / En camino / Entregado) ──

private let stepLabels = ["Recibido", "Preparando", "En camino", "Entregado"]
private let stepIcons = ["checkmark", "fork.knife", "bicycle", "checkmark"]

struct GOGOTrackingStepsEntry: TimelineEntry {
  let date: Date
  let hasOrder: Bool
  let restaurantName: String
  let address: String
  let total: Double
  let stepIndex: Int
}

struct GOGOTrackingStepsProvider: TimelineProvider {
  func placeholder(in context: Context) -> GOGOTrackingStepsEntry {
    GOGOTrackingStepsEntry(date: Date(), hasOrder: true, restaurantName: "McDonalds",
                            address: "Clara Cordoba Moran #16", total: 35, stepIndex: 1)
  }

  func getSnapshot(in context: Context, completion: @escaping (GOGOTrackingStepsEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<GOGOTrackingStepsEntry>) -> Void) {
    refreshOrderFromSupabase { _ in
      let entry = currentEntry()
      let policy: TimelineReloadPolicy = entry.hasOrder
        ? .after(Date().addingTimeInterval(widgetReloadInterval))
        : .never
      completion(Timeline(entries: [entry], policy: policy))
    }
  }

  private func currentEntry() -> GOGOTrackingStepsEntry {
    let data = UserDefaults(suiteName: appGroupId)
    return GOGOTrackingStepsEntry(
      date: Date(),
      hasOrder: data?.bool(forKey: "hasActiveOrder") ?? false,
      restaurantName: data?.string(forKey: "restaurantName") ?? "",
      address: data?.string(forKey: "address") ?? "",
      total: data?.object(forKey: "total") as? Double ?? 0,
      stepIndex: data?.object(forKey: "stepIndex") as? Int ?? 0
    )
  }
}

struct GOGOTrackingStepsWidgetEntryView: View {
  var entry: GOGOTrackingStepsProvider.Entry
  private let orange = Color(red: 244 / 255, green: 81 / 255, blue: 12 / 255)

  var body: some View {
    Group {
      if entry.hasOrder {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .top) {
            ZStack {
              RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.18))
              Image(systemName: "storefront.fill").foregroundColor(.white).font(.title3)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
              Text(entry.restaurantName)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
              Text(entry.address)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            }
            Spacer()
            Text("$\(Int(entry.total)) MXN")
              .font(.subheadline)
              .fontWeight(.bold)
              .foregroundColor(.white)
          }

          GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Color.white.opacity(0.2)).frame(height: 4)
              Capsule().fill(Color.white)
                .frame(width: geo.size.width * CGFloat(entry.stepIndex + 1) / 4.0, height: 4)
            }
          }
          .frame(height: 4)

          HStack {
            ForEach(0..<4, id: \.self) { i in
              VStack(spacing: 3) {
                ZStack {
                  Circle()
                    .fill(i < entry.stepIndex ? Color.green
                          : (i == entry.stepIndex ? Color.blue : Color.white.opacity(0.15)))
                  Image(systemName: stepIcons[i])
                    .font(.caption)
                    .foregroundColor(i <= entry.stepIndex ? .white : .white.opacity(0.5))
                }
                .frame(width: 26, height: 26)
                Text(stepLabels[i])
                  .font(.system(size: 8))
                  .foregroundColor(i <= entry.stepIndex ? .white : .white.opacity(0.5))
                  .lineLimit(1)
              }
              if i < 3 { Spacer() }
            }
          }
        }
        .padding(12)
      } else {
        EmptyOrderView()
      }
    }
    .widgetBackground(orange)
  }
}

struct GOGOTrackingStepsWidget: Widget {
  let kind: String = "GOGOTrackingStepsWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: GOGOTrackingStepsProvider()) { entry in
      GOGOTrackingStepsWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("GOGO Food (pasos)")
    .description("Muestra el pedido activo con los 4 pasos: Recibido, Preparando, En camino, Entregado.")
    .supportedFamilies([.systemMedium])
  }
}

@main
struct GOGOWidgetBundle: WidgetBundle {
  var body: some Widget {
    GOGOTrackingWidget()
    GOGOTrackingStepsWidget()
  }
}
